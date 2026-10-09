import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import pool from '../src/db/pool.js';

const MIGRATION_SQL = readFileSync(
  new URL('../database/migrations/008_customer_archive.sql', import.meta.url),
  'utf8'
);

/**
 * Everything below runs inside one Postgres transaction that is always
 * rolled back, so no schema change, trigger, function, or row survives
 * this test. `SET LOCAL request.jwt.claim.sub` makes auth.uid() resolve to
 * a real admin's auth_user_id for the duration of the transaction only,
 * so the RPCs run their real authorization logic without needing a
 * Supabase access token or touching auth.users.
 */
describe('customer archive and search (live, rolled back)', { timeout: 60_000 }, () => {
  it('applies the migration, then exercises archive/restore/search, then rolls everything back', async () => {
    const client = await pool.connect();
    const stamp = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

    try {
      await client.query('BEGIN');
      await client.query(MIGRATION_SQL);

      // --- New-rule item 6: the transactions trigger exists; there is no payments guard trigger.
      const triggers = await client.query(
        `SELECT tgname FROM pg_trigger
         WHERE tgname IN ('trg_transactions_block_archived_customer', 'trg_payments_block_archived_customer')
           AND NOT tgisinternal`
      );
      const triggerNames = triggers.rows.map((row) => row.tgname);
      assert.ok(triggerNames.includes('trg_transactions_block_archived_customer'));
      assert.ok(!triggerNames.includes('trg_payments_block_archived_customer'));

      const admin = await client.query(
        `SELECT auth_user_id FROM public.users WHERE role = 'admin' AND auth_user_id IS NOT NULL LIMIT 1`
      );
      assert.equal(admin.rows.length, 1, 'expected at least one linked admin to test against');
      const adminAuthId = admin.rows[0].auth_user_id;

      const passwordHash = '$2b$10$0000000000000000000000000000000000000000000000000000';

      const productResult = await client.query(
        `INSERT INTO public.products (name, type, current_price)
         VALUES ($1, 'bottle', 10.00)
         RETURNING id`,
        [`Archive Test Product ${stamp}`]
      );
      const productId = productResult.rows[0].id;

      async function insertCustomer(name, phone, email) {
        const userResult = await client.query(
          `INSERT INTO public.users (name, phone, email, password_hash, role)
           VALUES ($1, $2, $3, $4, 'customer')
           RETURNING id`,
          [name, phone, email, passwordHash]
        );
        const userId = userResult.rows[0].id;
        const customerResult = await client.query(
          `INSERT INTO public.customers (user_id, address)
           VALUES ($1, 'Test Address')
           RETURNING id, active`,
          [userId]
        );
        return { userId, customerId: customerResult.rows[0].id, active: customerResult.rows[0].active };
      }

      // Names/phones/emails are built from a unique per-run stamp so this
      // test's own rows are the only possible match for its search
      // assertions, regardless of whatever real customers already exist.
      // --- (archive-feature item) existing customers default to active.
      const customerA = await insertCustomer(
        `Mega${stamp}Alpha`,
        `9${stamp}1`,
        `alpha.${stamp}@example.test`
      );
      assert.equal(customerA.active, true);

      const customerB = await insertCustomer(
        `Mega${stamp}Beta`,
        `9${stamp}2`,
        `beta.${stamp}@example.test`
      );
      assert.equal(customerB.active, true);

      async function actAsAdmin() {
        await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminAuthId]);
      }

      async function callRpc(sql, params) {
        await actAsAdmin();
        return client.query(sql, params);
      }

      // --- Item 9: an active customer can be used normally for a new sale and a new payment.
      const firstSale = await callRpc(
        `SELECT * FROM public.create_transaction($1, $2, $3, $4, $5)`,
        [customerA.customerId, productId, 2, 10.0, 'first sale']
      );
      const firstSaleId = firstSale.rows[0].id;
      assert.equal(Number(firstSale.rows[0].total_amount), 20);

      await callRpc(
        `SELECT * FROM public.create_payment($1, $2, $3, $4, $5)`,
        [customerA.customerId, null, 5.0, 'Cash', 'first payment']
      );

      async function balanceOf(customerId) {
        await actAsAdmin();
        const result = await client.query(`SELECT public.get_customer_balance($1) AS balance`, [
          customerId,
        ]);
        return result.rows[0].balance;
      }

      const balanceBefore = await balanceOf(customerA.customerId);
      assert.equal(Number(balanceBefore.total_charges), 20);
      assert.equal(Number(balanceBefore.total_payments), 5);
      assert.equal(Number(balanceBefore.outstanding_balance), 15);

      // --- Item 2: admin can archive a customer (application does UPDATE customers SET active = false).
      await client.query('UPDATE public.customers SET active = false WHERE id = $1', [
        customerA.customerId,
      ]);
      const afterArchive = await client.query('SELECT active FROM public.customers WHERE id = $1', [
        customerA.customerId,
      ]);
      assert.equal(afterArchive.rows[0].active, false);

      // --- Item 4: the customer row still exists after archiving.
      const stillExists = await client.query('SELECT id FROM public.customers WHERE id = $1', [
        customerA.customerId,
      ]);
      assert.equal(stillExists.rowCount, 1);

      // --- Items 5 & 6: existing transactions and payments for the archived customer remain.
      const remainingTransactions = await client.query(
        'SELECT count(*)::int AS n FROM public.transactions WHERE customer_id = $1',
        [customerA.customerId]
      );
      assert.equal(remainingTransactions.rows[0].n, 1);
      const remainingPayments = await client.query(
        'SELECT count(*)::int AS n FROM public.payments WHERE customer_id = $1',
        [customerA.customerId]
      );
      assert.equal(remainingPayments.rows[0].n, 1);

      // --- Item 15: balance is unchanged after archiving.
      const balanceAfterArchive = await balanceOf(customerA.customerId);
      assert.deepEqual(balanceAfterArchive, balanceBefore);

      // A Postgres error aborts the rest of the transaction until a
      // ROLLBACK, so every expected failure below runs inside its own
      // SAVEPOINT and is rolled back to that point immediately after.

      // --- Item 7: an archived customer cannot be used for a NEW sale, via the RPC...
      await client.query('SAVEPOINT rpc_sale_blocked');
      await assert.rejects(
        callRpc(`SELECT * FROM public.create_transaction($1, $2, $3, $4, $5)`, [
          customerA.customerId,
          productId,
          1,
          10.0,
          'blocked sale',
        ]),
        (error) => {
          assert.match(error.message, /archived/i);
          return true;
        }
      );
      await client.query('ROLLBACK TO SAVEPOINT rpc_sale_blocked');

      // ...and via the direct-insert trigger backstop (bypassing the RPC).
      await client.query('SAVEPOINT direct_insert_blocked');
      await assert.rejects(
        client.query(
          `INSERT INTO public.transactions (customer_id, product_id, quantity, unit_price, total_amount, created_by)
           SELECT $1, $2, 1, 10.00, 10.00, id FROM public.users WHERE auth_user_id = $3`,
          [customerA.customerId, productId, adminAuthId]
        ),
        (error) => {
          assert.match(error.message, /archived/i);
          return true;
        }
      );
      await client.query('ROLLBACK TO SAVEPOINT direct_insert_blocked');

      // --- Item 4: an archived customer CAN still receive a new payment
      // toward their existing balance (business rule change from the
      // original archive design, which blocked both).
      const paymentForArchivedCustomer = await callRpc(
        `SELECT * FROM public.create_payment($1, $2, $3, $4, $5)`,
        [customerA.customerId, null, 7.0, 'Cash', 'payment while archived']
      );
      assert.equal(Number(paymentForArchivedCustomer.rows[0].amount), 7);
      assert.equal(paymentForArchivedCustomer.rows[0].customer_id, customerA.customerId);

      // The payments table has no archived-customer trigger either, so a
      // direct insert (bypassing the RPC, as the Express fallback would)
      // also succeeds for an archived customer.
      const directPaymentInsert = await client.query(
        `INSERT INTO public.payments (customer_id, amount, payment_method, created_by)
         SELECT $1, 3.00, 'Cash', id FROM public.users WHERE auth_user_id = $2
         RETURNING id`,
        [customerA.customerId, adminAuthId]
      );
      assert.equal(directPaymentInsert.rowCount, 1);

      // --- Item 9: balance is correct after a payment made while archived
      // (charges unchanged, payments increased by exactly what was paid).
      const balanceAfterArchivedPayment = await balanceOf(customerA.customerId);
      assert.equal(Number(balanceAfterArchivedPayment.total_charges), Number(balanceBefore.total_charges));
      assert.equal(
        Number(balanceAfterArchivedPayment.total_payments),
        Number(balanceBefore.total_payments) + 7 + 3
      );
      assert.equal(
        Number(balanceAfterArchivedPayment.outstanding_balance),
        Number(balanceBefore.outstanding_balance) - 7 - 3
      );

      // Editing the EXISTING sale for the now-archived customer must still work
      // (only NEW records are blocked).
      const editedSale = await callRpc(
        `SELECT * FROM public.update_transaction($1, $2, $3, $4, $5)`,
        [firstSaleId, productId, 3, 10.0, 'edited after archive']
      );
      assert.equal(Number(editedSale.rows[0].total_amount), 30);

      // --- Item 3: admin can restore a customer.
      await client.query('UPDATE public.customers SET active = true WHERE id = $1', [
        customerA.customerId,
      ]);
      const afterRestore = await client.query('SELECT active FROM public.customers WHERE id = $1', [
        customerA.customerId,
      ]);
      assert.equal(afterRestore.rows[0].active, true);

      // A restored customer can be used normally again.
      const saleAfterRestore = await callRpc(
        `SELECT * FROM public.create_transaction($1, $2, $3, $4, $5)`,
        [customerA.customerId, productId, 1, 10.0, 'after restore']
      );
      assert.equal(Number(saleAfterRestore.rows[0].total_amount), 10);

      // --- Items 10-14: search semantics (case-insensitive, partial match,
      // combined with active/archived filtering). This mirrors exactly the
      // filter CustomerDataService.listCustomers builds for Postgrest:
      // ILIKE '%term%' across name/phone/email, joined through the same
      // fk_customers_user relationship, restricted by customers.active.
      async function search(term, activeOnly) {
        const pattern = `%${term}%`;
        const result = await client.query(
          `SELECT c.id
           FROM public.customers AS c
           JOIN public.users AS u ON u.id = c.user_id
           WHERE c.active = $2
             AND (u.name ILIKE $1 OR u.phone ILIKE $1 OR u.email ILIKE $1)`,
          [pattern, activeOnly]
        );
        return result.rows.map((row) => row.id);
      }

      // Re-archive customer A so we have one active (B) and one archived (A)
      // customer with distinct, known attributes to search across.
      await client.query('UPDATE public.customers SET active = false WHERE id = $1', [
        customerA.customerId,
      ]);

      // Item 10: partial name, case-insensitive ("mega..." vs "Mega...").
      // Both rows share this substring; only the active one (B) should
      // show up once A is archived.
      const byName = await search(`mega${stamp}`, true);
      assert.deepEqual(byName, [customerB.customerId]);

      // Item 11: partial phone. Only B's phone contains this suffix.
      const byPhone = await search(`${stamp}2`, true);
      assert.deepEqual(byPhone, [customerB.customerId]);

      // Item 12: partial email. Only B's email starts with "beta.".
      const byEmail = await search(`beta.${stamp}`, true);
      assert.deepEqual(byEmail, [customerB.customerId]);

      // Item 13: Active + search only returns the active match.
      const activeSearch = await search(`mega${stamp}`, true);
      assert.deepEqual(activeSearch, [customerB.customerId]);

      // Item 14: Archived + search only returns the archived match.
      const archivedSearch = await search(`mega${stamp}`, false);
      assert.deepEqual(archivedSearch, [customerA.customerId]);
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }

    // After rollback, nothing from this test should be visible: the
    // triggers this migration creates, and every temporary row inserted
    // above, must be gone.
    const trigger = await pool.query(
      `SELECT count(*)::int AS n FROM pg_trigger
       WHERE tgname IN ('trg_transactions_block_archived_customer', 'trg_payments_block_archived_customer')
         AND NOT tgisinternal`
    );
    const leftoverProducts = await pool.query(
      `SELECT count(*)::int AS n FROM public.products WHERE name LIKE $1`,
      [`Archive Test Product ${stamp}`]
    );
    const leftoverUsers = await pool.query(
      `SELECT count(*)::int AS n FROM public.users WHERE name LIKE $1`,
      [`Mega${stamp}%`]
    );

    assert.equal(trigger.rows[0].n, 0, 'trigger from this test run must not persist');
    assert.equal(leftoverProducts.rows[0].n, 0, 'test product must not persist');
    assert.equal(leftoverUsers.rows[0].n, 0, 'test customers must not persist');

    await pool.end();
  });
});
