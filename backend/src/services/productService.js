import pool from '../db/pool.js';
import { AppError } from '../middleware/errorHandler.js';

const PRODUCT_COLUMNS = 'id, name, type, current_price, active, created_at, updated_at';

function mapProduct(row) {
  return {
    ...row,
    current_price: Number(row.current_price),
  };
}

export async function createProduct({ name, type, current_price }) {
  try {
    const { rows } = await pool.query(
      `INSERT INTO products (name, type, current_price)
       VALUES ($1, $2, $3)
       RETURNING ${PRODUCT_COLUMNS}`,
      [name, type, current_price]
    );

    return mapProduct(rows[0]);
  } catch (error) {
    if (error.code === '23505') {
      throw new AppError('A product with this name already exists', 409);
    }
    throw error;
  }
}

export async function listProducts(activeFilter) {
  const query =
    activeFilter === undefined
      ? `SELECT ${PRODUCT_COLUMNS} FROM products ORDER BY id`
      : `SELECT ${PRODUCT_COLUMNS} FROM products WHERE active = $1 ORDER BY id`;

  const params = activeFilter === undefined ? [] : [activeFilter];
  const { rows } = await pool.query(query, params);

  return rows.map(mapProduct);
}

export async function getProductById(id) {
  const { rows } = await pool.query(`SELECT ${PRODUCT_COLUMNS} FROM products WHERE id = $1`, [id]);

  if (rows.length === 0) {
    throw new AppError('Product not found', 404);
  }

  return mapProduct(rows[0]);
}

export async function updateProduct(id, { name, type, current_price, active }) {
  try {
    const { rows } = await pool.query(
      `UPDATE products
       SET name = COALESCE($1, name),
           type = COALESCE($2, type),
           current_price = COALESCE($3, current_price),
           active = COALESCE($4, active),
           updated_at = now()
       WHERE id = $5
       RETURNING ${PRODUCT_COLUMNS}`,
      [name, type, current_price, active, id]
    );

    if (rows.length === 0) {
      throw new AppError('Product not found', 404);
    }

    return mapProduct(rows[0]);
  } catch (error) {
    if (error.code === '23505') {
      throw new AppError('A product with this name already exists', 409);
    }
    throw error;
  }
}

export async function deleteProduct(id) {
  const existing = await pool.query('SELECT id FROM products WHERE id = $1', [id]);

  if (existing.rows.length === 0) {
    throw new AppError('Product not found', 404);
  }

  const referenced = await pool.query('SELECT 1 FROM transactions WHERE product_id = $1 LIMIT 1', [id]);

  if (referenced.rows.length > 0) {
    throw new AppError(
      'This product has transaction history and cannot be deleted. Set active to false instead.',
      409
    );
  }

  await pool.query('DELETE FROM products WHERE id = $1', [id]);
}
