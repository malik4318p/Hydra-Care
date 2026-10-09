import bcrypt from 'bcrypt';
import pool from '../db/pool.js';
import { AppError } from '../middleware/errorHandler.js';

const SALT_ROUNDS = 10;

const CUSTOMER_SELECT = `
  SELECT
    c.id,
    c.user_id,
    u.name,
    u.phone,
    u.email,
    u.role,
    c.address,
    c.created_at,
    c.updated_at
  FROM customers c
  JOIN users u ON u.id = c.user_id
`;

export async function createCustomer({ name, phone, email, password, address }) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    let userResult;
    try {
      userResult = await client.query(
        `INSERT INTO users (name, phone, email, password_hash, role)
         VALUES ($1, $2, $3, $4, 'customer')
         RETURNING id, name, phone, email, role, created_at, updated_at`,
        [name, phone, email, passwordHash]
      );
    } catch (error) {
      if (error.code === '23505') {
        throw new AppError('A user with this email already exists', 409);
      }
      throw error;
    }

    const user = userResult.rows[0];

    const customerResult = await client.query(
      `INSERT INTO customers (user_id, address)
       VALUES ($1, $2)
       RETURNING id, user_id, address, created_at, updated_at`,
      [user.id, address]
    );

    const customer = customerResult.rows[0];

    await client.query('COMMIT');

    return {
      id: customer.id,
      user_id: customer.user_id,
      name: user.name,
      phone: user.phone,
      email: user.email,
      role: user.role,
      address: customer.address,
      created_at: customer.created_at,
      updated_at: customer.updated_at,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function listCustomers() {
  const { rows } = await pool.query(`${CUSTOMER_SELECT} ORDER BY c.id`);
  return rows;
}

export async function getCustomerById(id) {
  const { rows } = await pool.query(`${CUSTOMER_SELECT} WHERE c.id = $1`, [id]);

  if (rows.length === 0) {
    throw new AppError('Customer not found', 404);
  }

  return rows[0];
}

export async function getCustomerByUserId(userId) {
  const { rows } = await pool.query(`${CUSTOMER_SELECT} WHERE c.user_id = $1`, [userId]);

  if (rows.length === 0) {
    throw new AppError('Customer profile not found', 404);
  }

  return rows[0];
}

export async function updateCustomer(id, { name, phone, email, address }) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const existing = await client.query('SELECT user_id FROM customers WHERE id = $1', [id]);

    if (existing.rows.length === 0) {
      throw new AppError('Customer not found', 404);
    }

    const userId = existing.rows[0].user_id;

    try {
      await client.query(
        `UPDATE users
         SET name = COALESCE($1, name),
             phone = COALESCE($2, phone),
             email = COALESCE($3, email),
             updated_at = now()
         WHERE id = $4`,
        [name, phone, email, userId]
      );
    } catch (error) {
      if (error.code === '23505') {
        throw new AppError('A user with this email already exists', 409);
      }
      throw error;
    }

    await client.query(
      `UPDATE customers
       SET address = COALESCE($1, address),
           updated_at = now()
       WHERE id = $2`,
      [address, id]
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  return getCustomerById(id);
}

export async function deleteCustomer(id) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const existing = await client.query('SELECT user_id FROM customers WHERE id = $1', [id]);

    if (existing.rows.length === 0) {
      throw new AppError('Customer not found', 404);
    }

    const userId = existing.rows[0].user_id;

    const [transactionCheck, paymentCheck] = await Promise.all([
      client.query('SELECT 1 FROM transactions WHERE customer_id = $1 LIMIT 1', [id]),
      client.query('SELECT 1 FROM payments WHERE customer_id = $1 LIMIT 1', [id]),
    ]);

    if (transactionCheck.rows.length > 0 || paymentCheck.rows.length > 0) {
      throw new AppError(
        'This customer has financial records (transactions or payments) and cannot be deleted',
        409
      );
    }

    await client.query('DELETE FROM customers WHERE id = $1', [id]);
    await client.query('DELETE FROM users WHERE id = $1', [userId]);

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function getCustomerBalance(customerId) {
  await getCustomerById(customerId);

  const { rows } = await pool.query(
    `SELECT
       COALESCE((SELECT SUM(total_amount) FROM transactions WHERE customer_id = $1), 0) AS total_charges,
       COALESCE((SELECT SUM(amount) FROM payments WHERE customer_id = $1), 0) AS total_payments`,
    [customerId]
  );

  const totalCharges = Number(rows[0].total_charges);
  const totalPayments = Number(rows[0].total_payments);

  return {
    customer_id: customerId,
    total_charges: totalCharges,
    total_payments: totalPayments,
    outstanding_balance: Math.round((totalCharges - totalPayments) * 100) / 100,
  };
}

export async function getCustomerSummary(customerId) {
  const customer = await getCustomerById(customerId);
  const balance = await getCustomerBalance(customerId);

  const [transactionsResult, paymentsResult] = await Promise.all([
    pool.query(
      `SELECT t.id, t.product_id, p.name AS product_name, t.quantity, t.unit_price,
              t.total_amount, t.notes, t.created_at
       FROM transactions t
       JOIN products p ON p.id = t.product_id
       WHERE t.customer_id = $1
       ORDER BY t.created_at DESC
       LIMIT 10`,
      [customerId]
    ),
    pool.query(
      `SELECT id, transaction_id, amount, payment_method, notes, created_at
       FROM payments
       WHERE customer_id = $1
       ORDER BY created_at DESC
       LIMIT 10`,
      [customerId]
    ),
  ]);

  return {
    customer,
    balance,
    recent_transactions: transactionsResult.rows.map((row) => ({
      ...row,
      unit_price: Number(row.unit_price),
      total_amount: Number(row.total_amount),
    })),
    recent_payments: paymentsResult.rows.map((row) => ({
      ...row,
      amount: Number(row.amount),
    })),
  };
}
