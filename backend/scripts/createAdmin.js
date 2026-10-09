import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import bcrypt from 'bcrypt';
import pool from '../src/db/pool.js';

const SALT_ROUNDS = 10;

const rl = readline.createInterface({ input, output });

async function ask(label) {
  const value = (await rl.question(`${label}: `)).trim();

  if (!value) {
    throw new Error(`${label} is required`);
  }

  return value;
}

try {
  const name = await ask('Name');
  const phone = await ask('Phone');
  const email = await ask('Email');
  const password = await ask('Password');

  const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);

  if (existing.rows.length > 0) {
    console.log('A user with this email already exists. No user was created.');
  } else {
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const { rows } = await pool.query(
      `INSERT INTO users (name, phone, email, password_hash, role)
       VALUES ($1, $2, $3, $4, 'admin')
       RETURNING id, name, email, role`,
      [name, phone, email, passwordHash]
    );

    const admin = rows[0];
    console.log(`Admin created: id=${admin.id}, name=${admin.name}, email=${admin.email}, role=${admin.role}`);
  }
} catch (error) {
  if (error.code === '23505') {
    console.log('A user with this email already exists. No user was created.');
  } else {
    console.error(error.message);
    process.exitCode = 1;
  }
} finally {
  rl.close();
  await pool.end();
}
