import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, describe, it } from 'node:test';
import { createClient } from '@supabase/supabase-js';
import bcrypt from 'bcrypt';
import env from '../src/config/env.js';
import pool from '../src/db/pool.js';

const PASSWORD = 'secret-12';
const createdAuthUserIds = [];

function supabase() {
  return createClient(env.supabaseUrl, env.supabaseSecretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function createAuthUser(email) {
  const { data, error } = await supabase().auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
  });
  assert.equal(error, null);
  createdAuthUserIds.push(data.user.id);
  return data.user.id;
}

describe('auth email sync trigger', { timeout: 60_000 }, () => {
  after(async () => {
    const leftover = await pool.query(
      "SELECT id FROM auth.users WHERE email LIKE 'sync-%@integration.hydra-care.test'"
    );
    const ids = new Set([
      ...createdAuthUserIds,
      ...leftover.rows.map((row) => row.id),
    ]);
    for (const id of ids) {
      await supabase().auth.admin.deleteUser(id);
    }
    await pool.end();
  });

  it('copies a changed Auth email onto the linked public user and rolls the migration back', async () => {
    const stamp = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const originalEmail = `sync-${stamp}-a@integration.hydra-care.test`;
    const changedEmail = `sync-${stamp}-b@integration.hydra-care.test`;
    const otherEmail = `sync-${stamp}-c@integration.hydra-care.test`;
    const authUserId = await createAuthUser(originalEmail);
    const otherAuthUserId = await createAuthUser(otherEmail);
    const passwordHash = await bcrypt.hash(PASSWORD, 4);
    const sql = readFileSync(
      new URL('../database/migrations/005_auth_email_sync.sql', import.meta.url),
      'utf8'
    );
    const client = await pool.connect();

    try {
      await client.query('BEGIN');
      await client.query(sql);

      await client.query('UPDATE auth.users SET email = $1 WHERE id = $2', [
        `sync-${stamp}-unlinked@integration.hydra-care.test`,
        otherAuthUserId,
      ]);
      await client.query('UPDATE auth.users SET email = $1 WHERE id = $2', [
        otherEmail,
        otherAuthUserId,
      ]);

      const inserted = await client.query(
        `INSERT INTO public.users (name, phone, email, password_hash, role, auth_user_id)
         VALUES ($1, $2, $3, $4, 'customer', $5)
         RETURNING id, name, phone, email, password_hash, role, auth_user_id`,
        ['Sync Customer', '5551112222', originalEmail, passwordHash, authUserId]
      );
      const userId = inserted.rows[0].id;
      await client.query(
        `INSERT INTO public.users (name, phone, email, password_hash, role, auth_user_id)
         VALUES ($1, $2, $3, $4, 'customer', $5)`,
        ['Other Customer', '5553334444', otherEmail, passwordHash, otherAuthUserId]
      );

      const beforeAuth = await client.query(
        'SELECT email, encrypted_password FROM auth.users WHERE id = $1',
        [authUserId]
      );

      await client.query('UPDATE auth.users SET email = email WHERE id = $1', [authUserId]);
      const unchanged = await client.query('SELECT email FROM public.users WHERE id = $1', [userId]);
      assert.equal(unchanged.rows[0].email, originalEmail);

      await client.query('UPDATE auth.users SET email = $1 WHERE id = $2', [changedEmail, authUserId]);
      const synced = await client.query(
        `SELECT name, phone, email, password_hash, role, auth_user_id
         FROM public.users WHERE id = $1`,
        [userId]
      );
      const afterAuth = await client.query(
        'SELECT email, encrypted_password FROM auth.users WHERE id = $1',
        [authUserId]
      );

      assert.equal(afterAuth.rows[0].email, changedEmail);
      assert.equal(synced.rows[0].email, changedEmail);
      assert.equal(synced.rows[0].auth_user_id, authUserId);
      assert.equal(synced.rows[0].name, 'Sync Customer');
      assert.equal(synced.rows[0].phone, '5551112222');
      assert.equal(synced.rows[0].role, 'customer');
      assert.equal(
        synced.rows[0].password_hash === inserted.rows[0].password_hash,
        true,
        'Application password changed'
      );
      assert.equal(
        afterAuth.rows[0].encrypted_password === beforeAuth.rows[0].encrypted_password,
        true,
        'Auth password changed'
      );

      await client.query('SAVEPOINT duplicate_email');
      await assert.rejects(
        client.query('UPDATE auth.users SET email = $1 WHERE id = $2', [otherEmail, authUserId]),
        (error) => error.code === '23505'
      );
      await client.query('ROLLBACK TO SAVEPOINT duplicate_email');

      const rolledBack = await client.query(
        `SELECT a.email AS auth_email, u.email AS public_email
         FROM auth.users AS a
         JOIN public.users AS u ON u.auth_user_id = a.id
         WHERE a.id = $1`,
        [authUserId]
      );
      assert.equal(rolledBack.rows[0].auth_email, changedEmail);
      assert.equal(rolledBack.rows[0].public_email, changedEmail);
    } finally {
      await client.query('ROLLBACK');
      client.release();
    }

    const trigger = await pool.query(
      `SELECT 1
       FROM pg_trigger
       WHERE tgname = 'trg_auth_user_email_sync'
         AND NOT tgisinternal`
    );
    assert.equal(trigger.rowCount, 0);
  });
});
