import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';
import { createCustomerAccount } from './create-customer.js';
import { createCustomerGateway } from './gateway.js';

const jsonHeaders = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function serverSecret(): string | null {
  const named = Deno.env.get('SUPABASE_SECRET_KEY');
  const injected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const secret = named && named.length > 0 ? named : injected;
  if (!secret || secret.startsWith('sb_publishable_')) {
    return null;
  }
  return secret;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: jsonHeaders });
  }

  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const secret = serverSecret();
  if (!url || !secret) {
    return json({ success: false, message: 'The customer could not be created.' }, 500);
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return json({ success: false, message: 'Name, phone, email, and address are required.' }, 400);
  }

  const admin = createClient(url, secret, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const result = await createCustomerAccount({
    authorization: req.headers.get('Authorization'),
    payload,
    gateway: createCustomerGateway(admin),
  });

  return json(result.body, result.status);
});
