-- ============================================================================
-- Migration: 004_supabase_rpc.sql
-- Purpose:   Security-definer functions for sales, payments, balance, and summary.
--
-- Identity is auth.uid() = public.users.auth_user_id.
-- Role is public.users.role.
-- This file is not executed automatically.
-- It does not change tables, columns, or existing rows.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- create_transaction
-- NULL unit_price uses products.current_price. Inactive products are allowed.
-- created_by is the caller's public.users.id.
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

  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = customer_id) THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
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


-- ----------------------------------------------------------------------------
-- update_transaction
-- NULL unit_price keeps the stored sale price. It does not read current_price.
-- NULL notes keeps the stored notes. customer_id and created_by are not updated.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_transaction(
  transaction_id integer,
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
  v_existing public.transactions;
  v_unit_price numeric(10, 2);
  v_notes text;
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

  SELECT *
  INTO v_existing
  FROM public.transactions
  WHERE id = transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction not found' USING ERRCODE = 'P0002';
  END IF;

  IF product_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.products WHERE id = product_id
  ) THEN
    RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002';
  END IF;

  IF quantity IS NULL OR quantity <= 0 THEN
    RAISE EXCEPTION 'invalid quantity' USING ERRCODE = '22023';
  END IF;

  IF unit_price IS NULL THEN
    v_unit_price := v_existing.unit_price;
  ELSE
    IF unit_price <= 0 THEN
      RAISE EXCEPTION 'unit_price must be positive' USING ERRCODE = '22023';
    END IF;
    v_unit_price := unit_price;
  END IF;

  v_notes := CASE
    WHEN notes IS NULL THEN v_existing.notes
    ELSE notes
  END;

  v_total := quantity * v_unit_price;

  UPDATE public.transactions
  SET product_id = update_transaction.product_id,
      quantity = update_transaction.quantity,
      unit_price = v_unit_price,
      total_amount = v_total,
      notes = v_notes,
      updated_at = now()
  WHERE id = transaction_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ----------------------------------------------------------------------------
-- create_payment
-- NULL transaction_id is a general payment. A sale must belong to this customer.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- update_payment
-- NULL transaction_id clears the link. customer_id and created_by stay as stored.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_payment(
  payment_id integer,
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
  v_existing public.payments;
  v_amount numeric(10, 2);
  v_method text;
  v_notes text;
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

  SELECT *
  INTO v_existing
  FROM public.payments
  WHERE id = payment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found' USING ERRCODE = 'P0002';
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

  v_method := payment_method;

  v_notes := CASE
    WHEN notes IS NULL THEN v_existing.notes
    ELSE notes
  END;

  IF transaction_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.transactions
    WHERE id = transaction_id
      AND transactions.customer_id = v_existing.customer_id
  ) THEN
    RAISE EXCEPTION 'transaction_id does not belong to this customer' USING ERRCODE = '22023';
  END IF;

  UPDATE public.payments
  SET amount = v_amount,
      payment_method = v_method,
      transaction_id = update_payment.transaction_id,
      notes = v_notes
  WHERE id = payment_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ----------------------------------------------------------------------------
-- get_customer_balance
-- Sums every sale and payment. An empty sum is 0.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_balance(target_customer_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_own_customer_id integer;
  v_charges numeric(10, 2);
  v_payments numeric(10, 2);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  SELECT role
  INTO v_role
  FROM public.users
  WHERE auth_user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role = 'admin' THEN
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = target_customer_id) THEN
      RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
    END IF;
  ELSIF v_role = 'customer' THEN
    SELECT c.id
    INTO v_own_customer_id
    FROM public.customers AS c
    JOIN public.users AS u ON u.id = c.user_id
    WHERE u.auth_user_id = v_uid;

    IF v_own_customer_id IS NULL OR v_own_customer_id IS DISTINCT FROM target_customer_id THEN
      RAISE EXCEPTION 'You do not have permission to perform this action' USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'You do not have permission to perform this action' USING ERRCODE = '42501';
  END IF;

  SELECT ROUND(COALESCE(SUM(total_amount), 0), 2)
  INTO v_charges
  FROM public.transactions
  WHERE customer_id = target_customer_id;

  SELECT ROUND(COALESCE(SUM(amount), 0), 2)
  INTO v_payments
  FROM public.payments
  WHERE customer_id = target_customer_id;

  RETURN jsonb_build_object(
    'customer_id', target_customer_id,
    'total_charges', v_charges,
    'total_payments', v_payments,
    'outstanding_balance', ROUND(v_charges - v_payments, 2)
  );
END;
$$;


-- ----------------------------------------------------------------------------
-- get_customer_summary
-- Authorization runs before any summary read.
-- Balance uses every row. Lists are the latest 10 only.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_customer_summary(target_customer_id integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_own_customer_id integer;
  v_balance jsonb;
  v_customer jsonb;
  v_transactions jsonb;
  v_payments jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  SELECT role
  INTO v_role
  FROM public.users
  WHERE auth_user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
  END IF;

  IF v_role = 'admin' THEN
    IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = target_customer_id) THEN
      RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
    END IF;
  ELSIF v_role = 'customer' THEN
    SELECT c.id
    INTO v_own_customer_id
    FROM public.customers AS c
    JOIN public.users AS u ON u.id = c.user_id
    WHERE u.auth_user_id = v_uid;

    IF v_own_customer_id IS NULL OR v_own_customer_id IS DISTINCT FROM target_customer_id THEN
      RAISE EXCEPTION 'You do not have permission to perform this action' USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'You do not have permission to perform this action' USING ERRCODE = '42501';
  END IF;

  v_balance := public.get_customer_balance(target_customer_id);

  SELECT jsonb_build_object(
    'id', c.id,
    'user_id', c.user_id,
    'name', u.name,
    'phone', u.phone,
    'email', u.email,
    'role', u.role,
    'address', c.address,
    'created_at', c.created_at,
    'updated_at', c.updated_at
  )
  INTO v_customer
  FROM public.customers AS c
  JOIN public.users AS u ON u.id = c.user_id
  WHERE c.id = target_customer_id;

  IF v_customer IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_transactions
  FROM (
    SELECT
      t.id,
      t.product_id,
      p.name AS product_name,
      t.quantity,
      t.unit_price,
      t.total_amount,
      t.notes,
      t.created_at
    FROM public.transactions AS t
    JOIN public.products AS p ON p.id = t.product_id
    WHERE t.customer_id = target_customer_id
    ORDER BY t.created_at DESC
    LIMIT 10
  ) AS s;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_payments
  FROM (
    SELECT
      p.id,
      p.transaction_id,
      p.amount,
      p.payment_method,
      p.notes,
      p.created_at
    FROM public.payments AS p
    WHERE p.customer_id = target_customer_id
    ORDER BY p.created_at DESC
    LIMIT 10
  ) AS s;

  RETURN jsonb_build_object(
    'customer', v_customer,
    'balance', v_balance,
    'recent_transactions', v_transactions,
    'recent_payments', v_payments
  );
END;
$$;


REVOKE ALL ON FUNCTION public.create_transaction(integer, integer, integer, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_transaction(integer, integer, integer, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_payment(integer, integer, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_payment(integer, integer, numeric, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_customer_balance(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_customer_summary(integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_transaction(integer, integer, integer, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_transaction(integer, integer, integer, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_payment(integer, integer, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_payment(integer, integer, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_balance(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_summary(integer) TO authenticated;
