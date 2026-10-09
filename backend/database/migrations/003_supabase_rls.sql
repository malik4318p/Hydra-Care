-- ============================================================================
-- Migration: 003_supabase_rls.sql
-- Purpose:   Row Level Security for the Supabase Data API.
--
-- Identity is auth.uid() = public.users.auth_user_id.
-- Role is public.users.role ('admin' or 'customer').
--
-- This file is not executed automatically.
-- It does not insert, update, or delete existing rows.
-- It does not create business RPC functions or Edge Functions.
-- The table owner and the Supabase service role bypass these policies,
-- so the current Express connection is unchanged.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Helper
-- Lives outside public so PostgREST does not expose it as an RPC.
-- SECURITY DEFINER reads public.users without re-entering users policies.
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE auth_user_id = auth.uid()
      AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;


-- ----------------------------------------------------------------------------
-- Enable RLS. No policies for anon. No DELETE policies for clients.
-- ----------------------------------------------------------------------------
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.users,
  public.customers,
  public.products,
  public.transactions,
  public.payments
FROM PUBLIC, anon, authenticated;


-- ----------------------------------------------------------------------------
-- users
-- Clients may read profile columns, never password_hash.
-- No client UPDATE. Email changes must stay aligned with auth.users.email
-- through a later secure flow.
-- ----------------------------------------------------------------------------
GRANT SELECT (
  id,
  name,
  phone,
  email,
  role,
  auth_user_id,
  created_at,
  updated_at
) ON public.users TO authenticated;

CREATE POLICY users_select_own
  ON public.users
  FOR SELECT
  TO authenticated
  USING (auth_user_id = (SELECT auth.uid()));

CREATE POLICY users_select_admin
  ON public.users
  FOR SELECT
  TO authenticated
  USING (private.is_admin());


-- ----------------------------------------------------------------------------
-- customers
-- No client INSERT or DELETE. Account creation stays with the future
-- Edge Function, which uses the service role and bypasses RLS.
-- ----------------------------------------------------------------------------
GRANT SELECT (
  id,
  user_id,
  address,
  created_at,
  updated_at
) ON public.customers TO authenticated;

GRANT UPDATE (address) ON public.customers TO authenticated;

CREATE POLICY customers_select_own
  ON public.customers
  FOR SELECT
  TO authenticated
  USING (
    user_id = (
      SELECT u.id
      FROM public.users AS u
      WHERE u.auth_user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY customers_select_admin
  ON public.customers
  FOR SELECT
  TO authenticated
  USING (private.is_admin());

CREATE POLICY customers_update_admin
  ON public.customers
  FOR UPDATE
  TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());


-- ----------------------------------------------------------------------------
-- products
-- ----------------------------------------------------------------------------
GRANT SELECT (
  id,
  name,
  type,
  current_price,
  active,
  created_at,
  updated_at
) ON public.products TO authenticated;

GRANT INSERT (
  name,
  type,
  current_price
) ON public.products TO authenticated;

GRANT UPDATE (
  name,
  type,
  current_price,
  active
) ON public.products TO authenticated;

CREATE POLICY products_select_authenticated
  ON public.products
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY products_insert_admin
  ON public.products
  FOR INSERT
  TO authenticated
  WITH CHECK (private.is_admin());

CREATE POLICY products_update_admin
  ON public.products
  FOR UPDATE
  TO authenticated
  USING (private.is_admin())
  WITH CHECK (private.is_admin());


-- ----------------------------------------------------------------------------
-- transactions
-- SELECT only. Inserts and updates wait for SECURITY DEFINER RPC functions.
-- ----------------------------------------------------------------------------
GRANT SELECT (
  id,
  customer_id,
  product_id,
  quantity,
  unit_price,
  total_amount,
  created_by,
  notes,
  created_at,
  updated_at
) ON public.transactions TO authenticated;

CREATE POLICY transactions_select_own
  ON public.transactions
  FOR SELECT
  TO authenticated
  USING (
    customer_id = (
      SELECT c.id
      FROM public.customers AS c
      WHERE c.user_id = (
        SELECT u.id
        FROM public.users AS u
        WHERE u.auth_user_id = (SELECT auth.uid())
      )
    )
  );

CREATE POLICY transactions_select_admin
  ON public.transactions
  FOR SELECT
  TO authenticated
  USING (private.is_admin());


-- ----------------------------------------------------------------------------
-- payments
-- SELECT only. Inserts and updates wait for SECURITY DEFINER RPC functions.
-- ----------------------------------------------------------------------------
GRANT SELECT (
  id,
  customer_id,
  transaction_id,
  amount,
  payment_method,
  notes,
  created_by,
  created_at
) ON public.payments TO authenticated;

CREATE POLICY payments_select_own
  ON public.payments
  FOR SELECT
  TO authenticated
  USING (
    customer_id = (
      SELECT c.id
      FROM public.customers AS c
      WHERE c.user_id = (
        SELECT u.id
        FROM public.users AS u
        WHERE u.auth_user_id = (SELECT auth.uid())
      )
    )
  );

CREATE POLICY payments_select_admin
  ON public.payments
  FOR SELECT
  TO authenticated
  USING (private.is_admin());
