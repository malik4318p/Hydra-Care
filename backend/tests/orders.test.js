import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import pool from '../src/db/pool.js';

const migration = readFileSync(
  new URL('../database/migrations/011_phone_orders.sql', import.meta.url),
  'utf8'
);

function stamp() {
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

async function adminAuthId(client) {
  const admin = await client.query(
    `SELECT auth_user_id
     FROM public.users
     WHERE role = 'admin' AND auth_user_id IS NOT NULL
     LIMIT 1`
  );
  assert.equal(admin.rowCount, 1, 'expected a linked admin');
  return admin.rows[0].auth_user_id;
}

async function makeCustomer(client, label, { active = true } = {}) {
  const tag = stamp();
  const user = await client.query(
    `INSERT INTO public.users (name, phone, email, password_hash, role)
     VALUES ($1, $2, NULL, NULL, 'customer')
     RETURNING id`,
    [`${label} ${tag}`, `9${tag}`]
  );
  const customer = await client.query(
    `INSERT INTO public.customers (user_id, address, active)
     VALUES ($1, NULL, $2)
     RETURNING id`,
    [user.rows[0].id, active]
  );
  return customer.rows[0].id;
}

async function makeProduct(client, label, price, { type = 'bottle' } = {}) {
  const tag = stamp();
  const product = await client.query(
    `INSERT INTO public.products (name, type, current_price, active)
     VALUES ($1, $2, $3, true)
     RETURNING id`,
    [`${label} ${tag}`, type, price]
  );
  return product.rows[0].id;
}

describe('phone orders and delivery management', () => {
  it('defines orders/order_items, RLS, the transactions link, and admin-only RPCs', () => {
    assert.match(migration, /CREATE TABLE public\.orders/);
    assert.match(migration, /CREATE TABLE public\.order_items/);
    assert.match(migration, /ALTER TABLE public\.orders ENABLE ROW LEVEL SECURITY/);
    assert.match(migration, /ALTER TABLE public\.order_items ENABLE ROW LEVEL SECURITY/);
    assert.match(migration, /ADD COLUMN order_item_id INTEGER/);
    assert.match(migration, /ADD CONSTRAINT uq_transactions_order_item_id UNIQUE \(order_item_id\)/);
    assert.match(migration, /FOR UPDATE/);
    assert.match(migration, /CREATE INDEX idx_orders_created_at/);
    assert.match(migration, /CREATE INDEX idx_orders_status_created_at/);
    assert.match(migration, /CREATE INDEX idx_orders_delivered_at/);
    assert.match(migration, /'admin required' USING ERRCODE = '42501'/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.create_phone_order/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.deliver_phone_order/);
  });

  it(
    'creates a pending multi-product order with price snapshots, then delivers it into ' +
      'one transaction per order item without touching the balance until delivery',
    async () => {
      const client = await pool.connect();

      try {
        await client.query('BEGIN');
        await client.query(migration);

        const adminId = await adminAuthId(client);
        const customerId = await makeCustomer(client, 'Order Test');
        const bottleId = await makeProduct(client, '19L Bottle Test', 100, { type: 'bottle' });
        const refillId = await makeProduct(client, 'Refill Test', 50, { type: 'refill' });

        await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminId]);

        const items = [
          { product_id: bottleId, quantity: 2 },
          { product_id: refillId, quantity: 3 },
        ];
        const created = await client.query(
          `SELECT public.create_phone_order($1, $2::jsonb, $3) AS result`,
          [customerId, JSON.stringify(items), 'phone order test']
        );
        const createResult = created.rows[0].result;
        const orderId = createResult.order.id;

        assert.equal(createResult.order.status, 'pending');
        assert.equal(Number(createResult.order.total_amount), 2 * 100 + 3 * 50);
        assert.equal(createResult.items.length, 2);

        // Pending: no transaction and no balance effect yet.
        const beforeDelivery = await client.query(
          `SELECT count(*)::int AS n FROM public.transactions WHERE customer_id = $1`,
          [customerId]
        );
        assert.equal(beforeDelivery.rows[0].n, 0);
        const balanceBefore = await client.query(
          `SELECT public.get_customer_balance($1) AS balance`,
          [customerId]
        );
        assert.equal(Number(balanceBefore.rows[0].balance.outstanding_balance), 0);

        // A later catalogue price change must not affect the stored snapshot.
        await client.query(`UPDATE public.products SET current_price = 999 WHERE id = $1`, [
          bottleId,
        ]);
        const snapshot = await client.query(
          `SELECT unit_price, product_name FROM public.order_items
           WHERE order_id = $1 AND product_id = $2`,
          [orderId, bottleId]
        );
        assert.equal(Number(snapshot.rows[0].unit_price), 100);

        const delivered = await client.query(`SELECT public.deliver_phone_order($1) AS result`, [
          orderId,
        ]);
        const deliverResult = delivered.rows[0].result;
        assert.equal(deliverResult.order.status, 'delivered');
        assert.ok(deliverResult.order.delivered_at);
        assert.equal(deliverResult.transactions.length, 2);

        const txns = await client.query(
          `SELECT product_id, quantity, unit_price, total_amount, order_item_id
           FROM public.transactions WHERE customer_id = $1`,
          [customerId]
        );
        assert.equal(txns.rowCount, 2, 'one transaction row per order item');
        const bottleTxn = txns.rows.find((row) => row.product_id === bottleId);
        assert.equal(Number(bottleTxn.unit_price), 100, 'uses the snapshot price, not the catalogue change');
        assert.equal(bottleTxn.quantity, 2);
        assert.ok(bottleTxn.order_item_id);

        const balanceAfter = await client.query(
          `SELECT public.get_customer_balance($1) AS balance`,
          [customerId]
        );
        assert.equal(
          Number(balanceAfter.rows[0].balance.total_charges),
          2 * 100 + 3 * 50,
          'existing balance calculation picks up the generated transactions unchanged'
        );
        assert.equal(Number(balanceAfter.rows[0].balance.outstanding_balance), 2 * 100 + 3 * 50);

        // Duplicate delivery is rejected and creates no second batch.
        await client.query('SAVEPOINT redeliver');
        await assert.rejects(
          client.query(`SELECT public.deliver_phone_order($1) AS result`, [orderId]),
          (error) => error.code === '22023'
        );
        await client.query('ROLLBACK TO SAVEPOINT redeliver');

        const afterRedeliverAttempt = await client.query(
          `SELECT count(*)::int AS n FROM public.transactions WHERE customer_id = $1`,
          [customerId]
        );
        assert.equal(afterRedeliverAttempt.rows[0].n, 2);

        // Database-level backstop: a second transaction row referencing the
        // same order item is rejected even if the RPC is bypassed entirely.
        await client.query('SAVEPOINT duplicate_item');
        await assert.rejects(
          client.query(
            `INSERT INTO public.transactions
               (customer_id, product_id, quantity, unit_price, total_amount, created_by, order_item_id)
             SELECT customer_id, product_id, quantity, unit_price, total_amount, created_by, order_item_id
             FROM public.transactions WHERE customer_id = $1 LIMIT 1`,
            [customerId]
          ),
          (error) => error.code === '23505'
        );
        await client.query('ROLLBACK TO SAVEPOINT duplicate_item');
      } finally {
        await client.query('ROLLBACK');
        client.release();
      }
    }
  );

  it('rejects invalid order input: no items, bad quantity, and an unknown product', async () => {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');
      await client.query(migration);

      const adminId = await adminAuthId(client);
      const customerId = await makeCustomer(client, 'Validation Test');
      const productId = await makeProduct(client, 'Validation Product', 10);

      await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminId]);

      await client.query('SAVEPOINT empty_items');
      await assert.rejects(
        client.query(`SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`, [
          customerId,
          JSON.stringify([]),
        ]),
        (error) => error.code === '22023'
      );
      await client.query('ROLLBACK TO SAVEPOINT empty_items');

      await client.query('SAVEPOINT bad_quantity');
      await assert.rejects(
        client.query(`SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`, [
          customerId,
          JSON.stringify([{ product_id: productId, quantity: 0 }]),
        ]),
        (error) => error.code === '22023'
      );
      await client.query('ROLLBACK TO SAVEPOINT bad_quantity');

      await client.query('SAVEPOINT unknown_product');
      await assert.rejects(
        client.query(`SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`, [
          customerId,
          JSON.stringify([{ product_id: 2147483647, quantity: 1 }]),
        ]),
        (error) => error.code === 'P0002'
      );
      await client.query('ROLLBACK TO SAVEPOINT unknown_product');
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }
  });

  it('blocks a new order for an archived customer, matching the existing create_transaction rule', async () => {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');
      await client.query(migration);

      const adminId = await adminAuthId(client);
      const archivedCustomerId = await makeCustomer(client, 'Archived Test', { active: false });
      const productId = await makeProduct(client, 'Archived Product', 20);

      await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminId]);

      await assert.rejects(
        client.query(`SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`, [
          archivedCustomerId,
          JSON.stringify([{ product_id: productId, quantity: 1 }]),
        ]),
        (error) => error.code === '22023'
      );
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }
  });

  it(
    'rolls back the whole delivery atomically if transaction generation fails, leaving the ' +
      'order Pending with no transactions created',
    async () => {
      const client = await pool.connect();

      try {
        await client.query('BEGIN');
        await client.query(migration);

        const adminId = await adminAuthId(client);
        const customerId = await makeCustomer(client, 'Atomic Test');
        const productId = await makeProduct(client, 'Atomic Product', 30);

        await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [adminId]);

        const created = await client.query(
          `SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`,
          [customerId, JSON.stringify([{ product_id: productId, quantity: 2 }])]
        );
        const orderId = created.rows[0].result.order.id;

        // Archive the customer after the order was placed, so delivery now
        // hits trg_transactions_block_archived_customer on the first insert.
        await client.query(`UPDATE public.customers SET active = false WHERE id = $1`, [
          customerId,
        ]);

        await client.query('SAVEPOINT blocked_delivery');
        await assert.rejects(
          client.query(`SELECT public.deliver_phone_order($1) AS result`, [orderId])
        );
        await client.query('ROLLBACK TO SAVEPOINT blocked_delivery');

        const order = await client.query(`SELECT status, delivered_at FROM public.orders WHERE id = $1`, [
          orderId,
        ]);
        assert.equal(order.rows[0].status, 'pending');
        assert.equal(order.rows[0].delivered_at, null);

        const txnCount = await client.query(
          `SELECT count(*)::int AS n FROM public.transactions WHERE customer_id = $1`,
          [customerId]
        );
        assert.equal(txnCount.rows[0].n, 0, 'no transaction was left behind by the failed delivery');
      } finally {
        await client.query('ROLLBACK');
        client.release();
      }
    }
  );

  it('rejects every RPC call without an authenticated caller', async () => {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');
      await client.query(migration);

      const customerId = await makeCustomer(client, 'Unauthenticated Test');
      const productId = await makeProduct(client, 'Unauthenticated Product', 10);

      await client.query(`SELECT set_config('request.jwt.claim.sub', '', true)`);

      await client.query('SAVEPOINT unauthenticated_create');
      await assert.rejects(
        client.query(`SELECT public.create_phone_order($1, $2::jsonb, NULL) AS result`, [
          customerId,
          JSON.stringify([{ product_id: productId, quantity: 1 }]),
        ]),
        (error) => error.code === '28000'
      );
      await client.query('ROLLBACK TO SAVEPOINT unauthenticated_create');

      await client.query('SAVEPOINT unauthenticated_deliver');
      await assert.rejects(
        client.query(`SELECT public.deliver_phone_order($1) AS result`, [1]),
        (error) => error.code === '28000'
      );
      await client.query('ROLLBACK TO SAVEPOINT unauthenticated_deliver');
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }
  });
});
