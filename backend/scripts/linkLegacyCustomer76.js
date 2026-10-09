import { createClient } from '@supabase/supabase-js';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const LEGACY_USER_ID = 76;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BCRYPT_PATTERN = /^\$2[aby]\$/;

export function legacyAuthCreateAttributes(email, passwordHash) {
  return {
    email,
    password_hash: passwordHash,
    email_confirm: true,
  };
}

export function redact(value) {
  return String(value).replace(/\$2[aby]\$\S+/gi, '[redacted]');
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required. Set it in the backend environment.`);
  }
  return value;
}

function failure(message) {
  return { ok: false, message: redact(message) };
}

function assertLegacyUser(user) {
  if (!user) {
    return 'public.users.id=76 was not found. Nothing was created or changed.';
  }
  if (user.role !== 'customer') {
    return 'public.users.id=76 is not a customer. Nothing was created or changed.';
  }
  if (user.auth_user_id) {
    return 'public.users.id=76 is already linked. Nothing was created or changed.';
  }
  if (!user.password_hash) {
    return 'public.users.id=76 has no password hash. Nothing was created or changed.';
  }
  if (!BCRYPT_PATTERN.test(user.password_hash)) {
    return 'public.users.id=76 does not have a bcrypt password hash. Nothing was created or changed.';
  }
  if (typeof user.email !== 'string' || user.email.trim().length === 0) {
    return 'public.users.id=76 has no email. Nothing was created or changed.';
  }
  return null;
}

export async function linkLegacyCustomer76({ db, authAdmin }) {
  const user = await db.getLegacyUser(LEGACY_USER_ID);
  const rejected = assertLegacyUser(user);
  if (rejected) {
    return failure(rejected);
  }

  const existing = await authAdmin.findByEmail(user.email);
  if (!Array.isArray(existing) || existing.length !== 0) {
    return failure(
      `An Auth user already exists for ${user.email}. No Auth user was created and public.users was not changed.`
    );
  }

  let created;
  try {
    created = await authAdmin.createWithPasswordHash(
      legacyAuthCreateAttributes(user.email, user.password_hash)
    );
  } catch (error) {
    return failure(
      `Auth creation failed for public.users.id=76 email=${user.email}. public.users was not changed. ${error?.message ?? 'unknown error'}`
    );
  }

  if (!created?.id || !UUID_PATTERN.test(created.id)) {
    return failure(
      `Auth creation for public.users.id=76 did not return a user id. public.users was not changed.`
    );
  }

  try {
    const linked = await db.linkAuthUser({
      id: LEGACY_USER_ID,
      email: user.email,
      authUserId: created.id,
    });
    if (!linked) {
      throw new Error('The link update did not change public.users.id=76.');
    }
  } catch (error) {
    let cleanup = 'The new Auth user was deleted.';
    try {
      await authAdmin.deleteUser(created.id);
    } catch (cleanupError) {
      cleanup = `The new Auth user ${created.id} could not be deleted. Remove that Auth user before retrying. ${cleanupError?.message ?? 'unknown error'}`;
    }
    return failure(
      `Link failed for public.users.id=76 email=${user.email}. password_hash was not changed. ${error?.message ?? 'unknown error'} ${cleanup}`
    );
  }

  return {
    ok: true,
    message: `Linked public.users.id=76 email=${user.email} to Auth user ${created.id}. password_hash was not changed.`,
    userId: LEGACY_USER_ID,
    email: user.email,
    authUserId: created.id,
  };
}

export function createLegacyCustomerDb(queryable) {
  return {
    async getLegacyUser(id) {
      const { rows } = await queryable.query(
        `SELECT id, email, role, auth_user_id, password_hash
         FROM public.users
         WHERE id = $1`,
        [id]
      );
      return rows[0] ?? null;
    },

    async linkAuthUser({ id, email, authUserId }) {
      const client = await queryable.connect();
      try {
        await client.query('BEGIN');
        const result = await client.query(
          `UPDATE public.users
           SET auth_user_id = $1
           WHERE id = $2
             AND email = $3
             AND role = 'customer'
             AND auth_user_id IS NULL
             AND password_hash IS NOT NULL`,
          [authUserId, id, email]
        );
        if (result.rowCount !== 1) {
          await client.query('ROLLBACK');
          return false;
        }
        await client.query('COMMIT');
        return true;
      } catch (error) {
        try {
          await client.query('ROLLBACK');
        } catch {
          // The transaction may already be closed.
        }
        throw error;
      } finally {
        client.release();
      }
    },
  };
}

export function createLegacyAuthAdmin(admin, query) {
  return {
    async findByEmail(email) {
      const { rows } = await query(
        `SELECT id
         FROM auth.users
         WHERE lower(email) = lower($1)`,
        [email]
      );
      return rows.map((row) => row.id);
    },

    async createWithPasswordHash(attributes) {
      const { data, error } = await admin.auth.admin.createUser(attributes);
      if (error) {
        throw error;
      }
      return { id: data?.user?.id ?? null };
    },

    async deleteUser(authUserId) {
      const { error } = await admin.auth.admin.deleteUser(authUserId);
      if (error) {
        throw error;
      }
    },
  };
}

function authClient() {
  const supabaseUrl = requiredEnv('SUPABASE_URL');
  const secretKey = requiredEnv('SUPABASE_SECRET_KEY');
  if (secretKey.startsWith('sb_publishable_')) {
    throw new Error('SUPABASE_SECRET_KEY is a publishable key. Use the server secret key.');
  }
  return createClient(supabaseUrl, secretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function main() {
  const { default: pool } = await import('../src/db/pool.js');
  try {
    const result = await linkLegacyCustomer76({
      db: createLegacyCustomerDb(pool),
      authAdmin: createLegacyAuthAdmin(authClient(), (text, values) => pool.query(text, values)),
    });
    if (!result.ok) {
      console.error(result.message);
      process.exitCode = 1;
      return;
    }
    console.log(result.message);
  } finally {
    await pool.end();
  }
}

if (import.meta.url === pathToFileURL(path.resolve(process.argv[1] ?? '')).href) {
  try {
    await main();
  } catch (error) {
    console.error(redact(error.message ?? 'Migration failed'));
    process.exitCode = 1;
  }
}
