import pool from '../db/pool.js';
import { AppError } from '../middleware/errorHandler.js';

const PAYMENT_COLUMNS =
  'id, customer_id, transaction_id, amount, payment_method, notes, created_by, created_at';

function mapPayment(row) {
  return {
    ...row,
    amount: Number(row.amount),
  };
}

export async function createPayment(
  { customer_id, transaction_id, amount, payment_method, notes },
  createdBy
) {
  const customerResult = await pool.query('SELECT id FROM customers WHERE id = $1', [customer_id]);

  if (customerResult.rows.length === 0) {
    throw new AppError('Customer not found', 404);
  }

  if (transaction_id !== undefined && transaction_id !== null) {
    const transactionResult = await pool.query(
      'SELECT id, customer_id FROM transactions WHERE id = $1',
      [transaction_id]
    );

    if (transactionResult.rows.length === 0 || transactionResult.rows[0].customer_id !== customer_id) {
      throw new AppError('transaction_id does not belong to this customer', 400);
    }
  }

  const { rows } = await pool.query(
    `INSERT INTO payments (customer_id, transaction_id, amount, payment_method, notes, created_by)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING ${PAYMENT_COLUMNS}`,
    [customer_id, transaction_id ?? null, amount, payment_method, notes ?? null, createdBy]
  );

  return mapPayment(rows[0]);
}

export async function listPayments({ customerId }) {
  const query =
    customerId === undefined
      ? `SELECT ${PAYMENT_COLUMNS} FROM payments ORDER BY created_at DESC`
      : `SELECT ${PAYMENT_COLUMNS} FROM payments WHERE customer_id = $1 ORDER BY created_at DESC`;

  const params = customerId === undefined ? [] : [customerId];
  const { rows } = await pool.query(query, params);

  return rows.map(mapPayment);
}

export async function getPaymentById(id) {
  const { rows } = await pool.query(`SELECT ${PAYMENT_COLUMNS} FROM payments WHERE id = $1`, [id]);

  if (rows.length === 0) {
    throw new AppError('Payment not found', 404);
  }

  return mapPayment(rows[0]);
}

export async function updatePayment(id, { amount, payment_method, transaction_id, notes }) {
  const existing = await getPaymentById(id);

  const newTransactionId = transaction_id !== undefined ? transaction_id : existing.transaction_id;

  if (newTransactionId !== null) {
    const transactionResult = await pool.query(
      'SELECT id, customer_id FROM transactions WHERE id = $1',
      [newTransactionId]
    );

    if (
      transactionResult.rows.length === 0 ||
      transactionResult.rows[0].customer_id !== existing.customer_id
    ) {
      throw new AppError('transaction_id does not belong to this customer', 400);
    }
  }

  const newAmount = amount ?? existing.amount;
  const newMethod = payment_method ?? existing.payment_method;
  const newNotes = notes !== undefined ? notes : existing.notes;

  const { rows } = await pool.query(
    `UPDATE payments
     SET amount = $1,
         payment_method = $2,
         transaction_id = $3,
         notes = $4
     WHERE id = $5
     RETURNING ${PAYMENT_COLUMNS}`,
    [newAmount, newMethod, newTransactionId, newNotes, id]
  );

  return mapPayment(rows[0]);
}

export async function deletePayment(id) {
  await getPaymentById(id);
  await pool.query('DELETE FROM payments WHERE id = $1', [id]);
}
