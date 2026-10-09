-- ============================================================================
-- Migration: 008_customer_archive.sql
-- Purpose:   Soft-delete (archive/restore) for customers, plus a guard that
--            stops a NEW sale from being created for an archived customer.
--
-- Business rule: an archived customer can still receive a NEW payment
-- toward their existing/outstanding balance. Only NEW transactions (sales)
-- are blocked for an archived customer. Nothing here changes historical
-- transactions/payments or balance calculations.
--
-- This file is not executed automatically.
-- Run it manually in the Supabase SQL Editor after review.
-- It does not delete any row. It does not touch products, users, or any
-- authentication table.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. customers.active
-- Every existing customer becomes active. New customers default to active.
-- ----------------------------------------------------------------------------
ALTER TABLE public.customers
    ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;


-- ----------------------------------------------------------------------------
-- 2. RLS / grants
-- Reuses the existing customers_update_admin policy (private.is_admin()).
-- No new policy is created. Only the minimum column grants are added so an
-- admin can read and change `active`.
-- ----------------------------------------------------------------------------
GRANT SELECT (active) ON public.customers TO authenticated;
GRANT UPDATE (active) ON public.customers TO authenticated;


-- ----------------------------------------------------------------------------
-- 3. Database-level guard
-- Blocks a NEW sale (transaction) row from being inserted for an archived
-- customer, independent of the caller (the create_transaction RPC below,
-- or the Express fallback, which both write through this same table).
-- This only fires BEFORE INSERT on transactions. There is deliberately no
-- equivalent trigger on payments: an archived customer may still receive
-- a new payment toward their existing balance. Existing rows and existing
-- UPDATEs to transactions/payments are unaffected; customer_id is never
-- changed after a row exists.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.check_customer_active_for_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_active boolean;
BEGIN
  SELECT active INTO v_active
  FROM public.customers
  WHERE id = NEW.customer_id;

  IF v_active IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_active THEN
    RAISE EXCEPTION 'This customer is archived and cannot be used for a new record' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.check_customer_active_for_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_transactions_block_archived_customer ON public.transactions;
CREATE TRIGGER trg_transactions_block_archived_customer
  BEFORE INSERT ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION private.check_customer_active_for_insert();

-- No trg_payments_block_archived_customer: payments are intentionally not
-- guarded. An archived customer can still make a payment.
DROP TRIGGER IF EXISTS trg_payments_block_archived_customer ON public.payments;


-- ----------------------------------------------------------------------------
-- 4. RPC guards
-- create_transaction rejects an archived customer with a specific message
-- before attempting the insert (the trigger above is a backstop, not the
-- primary error the app sees). create_payment is also redefined here, but
-- only to keep it identical to 004_supabase_rpc.sql: it checks that the
-- customer exists and nothing more. An archived customer may still make a
-- payment toward their existing balance.
--
-- Signatures are unchanged from 004_supabase_rpc.sql, so existing grants
-- keep applying; they are re-issued below only for clarity.
--
-- update_transaction and update_payment are NOT touched: editing an
-- existing sale or payment for a customer who is later archived must keep
-- working, and neither function can change customer_id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_transaction(
  customer_id integer,
  product_id integer,
  quantity integer,
  unit_price numeric DEFAULT NULL,
  notes text DEFAULT NULL
)
RETURNS public.transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_role text;
  v_customer_active boolean;
  v_unit_price numeric(10, 2);
  v_total numeric(10, 2);
  v_row public.transactions;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  SELECT id, role
  INTO v_caller_id, v_role
  FROM public.users
  WHERE auth_user_id = v_uid;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  SELECT active INTO v_customer_active
  FROM public.customers
  WHERE id = customer_id;

  IF v_customer_active IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_customer_active THEN
    RAISE EXCEPTION 'This customer is archived and cannot be used for a new sale' USING ERRCODE = '22023';
  END IF;

  IF quantity IS NULL OR quantity <= 0 THEN
    RAISE EXCEPTION 'invalid quantity' USING ERRCODE = '22023';
  END IF;

  IF unit_price IS NULL THEN
    SELECT current_price
    INTO v_unit_price
    FROM public.products
    WHERE id = product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002';
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = product_id) THEN
      RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002';
    END IF;

    IF unit_price <= 0 THEN
      RAISE EXCEPTION 'unit_price must be positive' USING ERRCODE = '22023';
    END IF;

    v_unit_price := unit_price;
  END IF;

  IF v_unit_price IS NULL OR v_unit_price <= 0 THEN
    RAISE EXCEPTION 'unit_price must be positive' USING ERRCODE = '22023';
  END IF;

  v_total := quantity * v_unit_price;

  INSERT INTO public.transactions (
    customer_id,
    product_id,
    quantity,
    unit_price,
    total_amount,
    created_by,
    notes
  )
  VALUES (
    customer_id,
    product_id,
    quantity,
    v_unit_price,
    v_total,
    v_caller_id,
    notes
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_payment(
  customer_id integer,
  transaction_id integer DEFAULT NULL,
  amount numeric DEFAULT NULL,
  payment_method text DEFAULT NULL,
  notes text DEFAULT NULL
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_role text;
  v_amount numeric(10, 2);
  v_row public.payments;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  SELECT id, role
  INTO v_caller_id, v_role
  FROM public.users
  WHERE auth_user_id = v_uid;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  -- An archived customer may still receive a new payment toward their
  -- existing balance, so this only checks that the customer exists.
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id) THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF amount IS NULL OR amount <= 0 THEN
    RAISE EXCEPTION 'invalid amount' USING ERRCODE = '22023';
  END IF;

  v_amount := amount;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'invalid amount' USING ERRCODE = '22023';
  END IF;

  IF payment_method IS NULL OR payment_method = '' OR char_length(payment_method) > 50 THEN
    RAISE EXCEPTION 'payment_method must not be empty' USING ERRCODE = '22023';
  END IF;

  IF transaction_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.transactions
    WHERE id = transaction_id
      AND transactions.customer_id = create_payment.customer_id
  ) THEN
    RAISE EXCEPTION 'transaction_id does not belong to this customer' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.payments (
    customer_id,
    transaction_id,
    amount,
    payment_method,
    notes,
    created_by
  )
  VALUES (
    customer_id,
    transaction_id,
    v_amount,
    payment_method,
    notes,
    v_caller_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


REVOKE ALL ON FUNCTION public.create_transaction(integer, integer, integer, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_payment(integer, integer, numeric, text, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_transaction(integer, integer, integer, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_payment(integer, integer, numeric, text, text) TO authenticated;
