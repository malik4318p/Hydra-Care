import pool from '../db/pool.js';
import { AppError } from '../middleware/errorHandler.js';

const TRANSACTION_COLUMNS =
  'id, customer_id, product_id, quantity, unit_price, total_amount, created_by, notes, created_at, updated_at';

function mapTransaction(row) {
  return {
    ...row,
    unit_price: Number(row.unit_price),
    total_amount: Number(row.total_amount),
  };
}

function calculateTotal(quantity, unitPrice) {
  return Math.round(quantity * unitPrice * 100) / 100;
}

export async function createTransaction({ customer_id, product_id, quantity, unit_price, notes }, createdBy) {
  const customerResult = await pool.query('SELECT id FROM customers WHERE id = $1', [customer_id]);

  if (customerResult.rows.length === 0) {
    throw new AppError('Customer not found', 404);
  }

  const productResult = await pool.query('SELECT id, current_price FROM products WHERE id = $1', [
    product_id,
  ]);

  if (productResult.rows.length === 0) {
    throw new AppError('Product not found', 404);
  }

  const finalUnitPrice =
    unit_price !== undefined ? unit_price : Number(productResult.rows[0].current_price);
  const totalAmount = calculateTotal(quantity, finalUnitPrice);

  const { rows } = await pool.query(
    `INSERT INTO transactions (customer_id, product_id, quantity, unit_price, total_amount, created_by, notes)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING ${TRANSACTION_COLUMNS}`,
    [customer_id, product_id, quantity, finalUnitPrice, totalAmount, createdBy, notes ?? null]
  );

  return mapTransaction(rows[0]);
}

export async function listTransactions({ customerId }) {
  const query =
    customerId === undefined
      ? `SELECT ${TRANSACTION_COLUMNS} FROM transactions ORDER BY created_at DESC`
      : `SELECT ${TRANSACTION_COLUMNS} FROM transactions WHERE customer_id = $1 ORDER BY created_at DESC`;

  const params = customerId === undefined ? [] : [customerId];
  const { rows } = await pool.query(query, params);

  return rows.map(mapTransaction);
}

export async function getTransactionById(id) {
  const { rows } = await pool.query(`SELECT ${TRANSACTION_COLUMNS} FROM transactions WHERE id = $1`, [
    id,
  ]);

  if (rows.length === 0) {
    throw new AppError('Transaction not found', 404);
  }

  return mapTransaction(rows[0]);
}

export async function updateTransaction(id, { product_id, quantity, unit_price, notes }) {
  const existing = await getTransactionById(id);

  if (product_id !== undefined) {
    const productResult = await pool.query('SELECT id FROM products WHERE id = $1', [product_id]);
    if (productResult.rows.length === 0) {
      throw new AppError('Product not found', 404);
    }
  }

  const newProductId = product_id ?? existing.product_id;
  const newQuantity = quantity ?? existing.quantity;
  const newUnitPrice = unit_price ?? existing.unit_price;
  const newTotal = calculateTotal(newQuantity, newUnitPrice);
  const newNotes = notes !== undefined ? notes : existing.notes;

  const { rows } = await pool.query(
    `UPDATE transactions
     SET product_id = $1,
         quantity = $2,
         unit_price = $3,
         total_amount = $4,
         notes = $5,
         updated_at = now()
     WHERE id = $6
     RETURNING ${TRANSACTION_COLUMNS}`,
    [newProductId, newQuantity, newUnitPrice, newTotal, newNotes, id]
  );

  return mapTransaction(rows[0]);
}

export async function deleteTransaction(id) {
  await getTransactionById(id);

  const referenced = await pool.query('SELECT 1 FROM payments WHERE transaction_id = $1 LIMIT 1', [id]);

  if (referenced.rows.length > 0) {
    throw new AppError('This transaction has payments referencing it and cannot be deleted', 409);
  }

  await pool.query('DELETE FROM transactions WHERE id = $1', [id]);
}
