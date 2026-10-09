import { createClient } from '@supabase/supabase-js';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import pool from '../db/pool.js';
import env from '../config/env.js';
import { AppError } from '../middleware/errorHandler.js';

const TOKEN_EXPIRY = '7d';
const ALLOWED_ROLES = new Set(['admin', 'customer']);
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const supabaseAdmin = createClient(env.supabaseUrl, env.supabaseSecretKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

function issueSession(user) {
  const token = jwt.sign({ userId: user.id, role: user.role }, env.jwtSecret, {
    expiresIn: TOKEN_EXPIRY,
  });

  return {
    token,
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
    },
  };
}

export async function login(email, password) {
  const { rows } = await pool.query(
    'SELECT id, name, email, password_hash, role FROM users WHERE email = $1',
    [email]
  );

  const user = rows[0];

  if (!user) {
    throw new AppError('Invalid email or password', 401);
  }

  const passwordMatches = await bcrypt.compare(password, user.password_hash);

  if (!passwordMatches) {
    throw new AppError('Invalid email or password', 401);
  }

  return issueSession(user);
}

export async function supabaseLogin(accessToken) {
  const authUserId = await verifiedAuthUserId(accessToken);

  const { rows } = await pool.query(
    `SELECT id, name, email, role
     FROM public.users
     WHERE auth_user_id = $1`,
    [authUserId]
  );

  const user = rows[0];

  if (!user) {
    throw new AppError('No application user is linked to this account', 401);
  }

  if (!ALLOWED_ROLES.has(user.role)) {
    throw new AppError('You do not have permission to perform this action', 403);
  }

  return issueSession(user);
}

async function verifiedAuthUserId(accessToken) {
  let userId;

  try {
    const { data, error } = await supabaseAdmin.auth.getUser(accessToken);

    if (!error && data?.user?.id) {
      userId = data.user.id;
    }
  } catch {
    userId = null;
  }

  if (!userId || !UUID_PATTERN.test(userId)) {
    throw new AppError('Invalid or expired token', 401);
  }

  return userId;
}
