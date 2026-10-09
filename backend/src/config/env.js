import 'dotenv/config';

function required(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is required. Set it in your .env file.`);
  }

  return value;
}

const supabaseSecretKey = required('SUPABASE_SECRET_KEY');

if (supabaseSecretKey.startsWith('sb_publishable_')) {
  throw new Error('SUPABASE_SECRET_KEY must be the server secret key.');
}

const env = {
  databaseUrl: required('DATABASE_URL'),
  jwtSecret: required('JWT_SECRET'),
  supabaseUrl: required('SUPABASE_URL'),
  supabaseSecretKey,
  port: process.env.PORT || 5000,
};

export default env;
