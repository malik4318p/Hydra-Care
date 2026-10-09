import pool, { testDatabaseConnection } from './pool.js';

try {
  await testDatabaseConnection();
  console.log('Database connected successfully');
} catch (error) {
  console.error('Database connection failed:', error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
