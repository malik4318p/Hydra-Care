import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import pool from '../src/db/pool.js';

const migration = readFileSync(
  new URL('../database/migrations/010_customer_security.sql', import.meta.url),
  'utf8'
);
const nullableCustomersMigration = readFileSync(
  new URL('../database/migrations/009_ledger_only_customers.sql', import.meta.url),
  'utf8'
);

describe('customer security and bottle ledgers', () => {
  it('defines separate protected ledgers, admin-only RPCs, and the product-1 boundary', () => {
    assert.match(migration, /CREATE TABLE public\.customer_security_ledger/);
    assert.match(migration, /CREATE TABLE public\.customer_bottle_ledger/);
    assert.match(migration, /ALTER TABLE public\.customer_security_ledger ENABLE ROW LEVEL SECURITY/);
    assert.match(migration, /ALTER TABLE public\.customer_bottle_ledger ENABLE ROW LEVEL SECURITY/);
    assert.match(migration, /FOR UPDATE/);
    assert.match(migration, /product_id = 1/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.collect_customer_security/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.refund_customer_security/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.issue_customer_bottles/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.return_customer_bottles/);
    assert.match(migration, /'security_history'/);
    assert.match(migration, /'bottle_history'/);
    assert.match(nullableCustomersMigration, /ALTER COLUMN email DROP NOT NULL/);
  });

  it('collects/refunds security, issues/returns bottles, and prevents overdraws', async () => {
    const client = await pool.connect();
    const stamp = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;

    try {
      await client.query('BEGIN');
      await client.query(nullableCustomersMigration);
      await client.query(migration);

      const admin = await client.query(
        `SELECT auth_user_id
         FROM public.users
         WHERE role = 'admin' AND auth_user_id IS NOT NULL
         LIMIT 1`
      );
      assert.equal(admin.rowCount, 1, 'expected a linked admin');
      const adminAuthId = admin.rows[0].auth_user_id;

      const user = await client.query(
        `INSERT INTO public.users (name, phone, email, password_hash, role)
         VALUES ($1, $2, NULL, NULL, 'customer')
         RETURNING id`,
        [`Ledger Test ${stamp}`, `9${stamp}`]
      );
      const customer = await client.query(
        `INSERT INTO public.customers (user_id, address)
         VALUES ($1, NULL)
         RETURNING id`,
        [user.rows[0].id]
      );
      const customerId = customer.rows[0].id;

      await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminAuthId]);

      await client.query(
        `SELECT * FROM public.collect_customer_security($1, $2, $3)`,
        [customerId, 100, 'initial security']
      );
      await client.query(
        `SELECT * FROM public.refund_customer_security($1, $2, $3)`,
        [customerId, 40, 'partial refund']
      );

      await client.query('SAVEPOINT over_refund');
      await assert.rejects(
        client.query(
          `SELECT * FROM public.refund_customer_security($1, $2, NULL)`,
          [customerId, 61]
        ),
        (error) => error.code === '22023'
      );
      await client.query('ROLLBACK TO SAVEPOINT over_refund');

      await client.query(
        `SELECT * FROM public.issue_customer_bottles($1, $2, $3)`,
        [customerId, 3, 'delivery']
      );
      await client.query(
        `SELECT * FROM public.return_customer_bottles($1, $2, $3)`,
        [customerId, 2, 'two returned']
      );

      await client.query('SAVEPOINT over_return');
      await assert.rejects(
        client.query(
          `SELECT * FROM public.return_customer_bottles($1, $2, NULL)`,
          [customerId, 2]
        ),
        (error) => error.code === '22023'
      );
      await client.query('ROLLBACK TO SAVEPOINT over_return');

      const summary = await client.query(
        `SELECT public.get_customer_summary($1) AS summary`,
        [customerId]
      );
      const data = summary.rows[0].summary;
      assert.equal(Number(data.security_balance), 60);
      assert.deepEqual(data.bottles, { issued: 3, returned: 2, outstanding: 1 });
      assert.equal(data.security_history.length, 2);
      assert.equal(data.bottle_history.length, 2);

      await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [
        '99999999-9999-4999-8999-999999999999',
      ]);
      await assert.rejects(
        client.query(
          `SELECT * FROM public.collect_customer_security($1, $2, NULL)`,
          [customerId, 10]
        ),
        (error) => error.code === '42501'
      );
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }
  });
});
