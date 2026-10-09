import pg from 'pg';
import env from '../config/env.js';

const { Pool } = pg;

const pool = new Pool({ connectionString: env.databaseUrl });

pool.on('error', (error) => {
  console.error('Unexpected database pool error:', error.message);
});

export async function testDatabaseConnection() {
  const result = await pool.query('SELECT NOW() AS now');
  return result.rows[0];
}

export default pool;
