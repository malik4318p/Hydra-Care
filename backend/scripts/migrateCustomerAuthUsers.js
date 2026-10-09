import { createClient } from '@supabase/supabase-js';
import pool from '../src/db/pool.js';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function requiredEnv(name) {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`${name} is required. Set it in the backend environment.`);
  }

  return value;
}

function redact(value) {
  return String(value).replace(/\$2[aby]\$\S+/gi, '[redacted]');
}

function authClient() {
  const supabaseUrl = requiredEnv('SUPABASE_URL');
  const secretKey = requiredEnv('SUPABASE_SECRET_KEY');

  if (secretKey.startsWith('sb_publishable_')) {
    throw new Error(
      'SUPABASE_SECRET_KEY is a publishable key. Use the server secret key.'
    );
  }

  return createClient(supabaseUrl, secretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function findAuthUserId(email) {
  const { rows } = await pool.query(
    `SELECT id
     FROM auth.users
     WHERE lower(email) = lower($1)`,
    [email]
  );

  if (rows.length > 1) {
    throw new Error(
      `More than one Auth user exists for ${email}. No Auth user was created or changed.`
    );
  }

  return rows[0]?.id ?? null;
}

async function linkCustomer(userId, authUserId) {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const result = await client.query(
      `UPDATE public.users
       SET auth_user_id = $1
       WHERE id = $2
         AND role = 'customer'
         AND auth_user_id IS NULL`,
      [authUserId, userId]
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
}

async function createAuthUser(supabase, customer) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: customer.email,
    password_hash: customer.password_hash,
    email_confirm: true,
  });

  if (error) {
    return { id: null, error };
  }

  const authUserId = data?.user?.id ?? null;

  if (!authUserId || !UUID_PATTERN.test(authUserId)) {
    return {
      id: null,
      error: new Error(`Auth creation for ${customer.email} did not return a user id.`),
    };
  }

  return { id: authUserId, error: null };
}

async function migrateCustomer(supabase, customer) {
  let authUserId = await findAuthUserId(customer.email);
  let source = 'existing';

  if (!authUserId) {
    const created = await createAuthUser(supabase, customer);

    if (created.id) {
      authUserId = created.id;
      source = 'created';
    } else {
      authUserId = await findAuthUserId(customer.email);
      source = 'existing';

      if (!authUserId) {
        throw new Error(
          `Auth creation failed for ${customer.email}: ${redact(created.error?.message ?? 'unknown error')}`
        );
      }
    }
  }

  let linked = false;

  try {
    linked = await linkCustomer(customer.id, authUserId);
  } catch (error) {
    throw new Error(
      `Link failed for public.users.id=${customer.id} email=${customer.email}. Auth user ${authUserId} was not changed. ${redact(error.message ?? 'unknown error')} Rerun this script to link it.`
    );
  }

  if (!linked) {
    throw new Error(
      `Link failed for public.users.id=${customer.id} email=${customer.email}. Auth user ${authUserId} was not changed. Rerun this script to link it.`
    );
  }

  console.log(
    `Linked public.users.id=${customer.id} email=${customer.email} to Auth user ${authUserId} (${source}).`
  );
}

async function main() {
  const supabase = authClient();
  const { rows } = await pool.query(
    `SELECT id, email, password_hash
     FROM public.users
     WHERE role = 'customer'
       AND auth_user_id IS NULL
     ORDER BY id`
  );

  if (rows.length === 0) {
    console.log('No unlinked customer users. Nothing to migrate.');
    return;
  }

  console.log(`Found ${rows.length} unlinked customer user(s).`);

  const failures = [];

  for (const customer of rows) {
    try {
      if (!customer.email || !customer.password_hash) {
        throw new Error(
          `public.users.id=${customer.id} is missing an email or password hash. It was not sent to Auth.`
        );
      }

      await migrateCustomer(supabase, customer);
    } catch (error) {
      const message = redact(error.message ?? 'unknown error');
      failures.push(message);
      console.error(message);
    }
  }

  if (failures.length > 0) {
    throw new Error(
      `${failures.length} customer user(s) were not linked. Rerun this script after fixing the reported failures.`
    );
  }
}

try {
  await main();
} catch (error) {
  console.error(redact(error.message ?? 'Migration failed'));
  process.exitCode = 1;
} finally {
  await pool.end();
}
