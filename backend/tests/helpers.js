import pool from '../src/db/pool.js';

const EMAIL_LIKE = '%@integration.hydra-care.test';
const PRODUCT_LIKE = 'itest-%';

let baseUrl;

export function setBaseUrl(url) {
  baseUrl = url;
}

export async function request(method, pathname, { token, body, rawBody, query, headers = {} } = {}) {
  const url = new URL(pathname, baseUrl);

  if (query) {
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.set(key, String(value));
    }
  }

  const requestHeaders = { ...headers };

  if (token) {
    requestHeaders.authorization = token.startsWith('Bearer ') ? token : `Bearer ${token}`;
  }

  let payload;

  if (rawBody !== undefined) {
    payload = rawBody;
    requestHeaders['content-type'] = requestHeaders['content-type'] || 'application/json';
  } else if (body !== undefined) {
    payload = JSON.stringify(body);
    requestHeaders['content-type'] = 'application/json';
  }

  const response = await fetch(url, { method, headers: requestHeaders, body: payload });
  const text = await response.text();
  let parsed = null;

  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }

  return { status: response.status, body: parsed };
}

export async function cleanupTestData() {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    await client.query(
      `DELETE FROM payments
       WHERE customer_id IN (
         SELECT c.id
         FROM customers c
         JOIN users u ON u.id = c.user_id
         WHERE lower(u.email) LIKE $1
       )
       OR created_by IN (SELECT id FROM users WHERE lower(email) LIKE $1)
       OR transaction_id IN (
         SELECT t.id
         FROM transactions t
         JOIN products p ON p.id = t.product_id
         WHERE p.name LIKE $2
       )`,
      [EMAIL_LIKE, PRODUCT_LIKE]
    );

    await client.query(
      `DELETE FROM transactions
       WHERE customer_id IN (
         SELECT c.id
         FROM customers c
         JOIN users u ON u.id = c.user_id
         WHERE lower(u.email) LIKE $1
       )
       OR created_by IN (SELECT id FROM users WHERE lower(email) LIKE $1)
       OR product_id IN (SELECT id FROM products WHERE name LIKE $2)`,
      [EMAIL_LIKE, PRODUCT_LIKE]
    );

    await client.query(
      `DELETE FROM customers
       WHERE user_id IN (SELECT id FROM users WHERE lower(email) LIKE $1)`,
      [EMAIL_LIKE]
    );

    await client.query('DELETE FROM users WHERE lower(email) LIKE $1', [EMAIL_LIKE]);
    await client.query('DELETE FROM products WHERE name LIKE $1', [PRODUCT_LIKE]);

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function snapshotDatabase() {
  const [users, customers, products, transactions, payments] = await Promise.all([
    pool.query('SELECT id, email, role FROM users ORDER BY id'),
    pool.query('SELECT id, user_id, address FROM customers ORDER BY id'),
    pool.query(
      'SELECT id, name, type, current_price::text AS current_price, active FROM products ORDER BY id'
    ),
    pool.query('SELECT id FROM transactions ORDER BY id'),
    pool.query('SELECT id FROM payments ORDER BY id'),
  ]);

  return {
    users: users.rows,
    customers: customers.rows,
    products: products.rows,
    transactions: transactions.rows,
    payments: payments.rows,
  };
}

export function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}
