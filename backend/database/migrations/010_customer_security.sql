-- ============================================================================
-- Migration: 010_customer_security.sql
-- Purpose:   Admin-only security-deposit and reusable 19L bottle ledgers.
--
-- Prerequisite: migrations 001-009 have been reviewed/applied.
-- This file is not executed automatically.
-- It does not modify or delete existing products, customers, users, or Auth
-- identities. Normal transaction/payment balances are unchanged.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Append-only ledgers.
-- A security entry is either a collection or a refund; amount is always
-- positive and the entry type determines its effect on the derived balance.
-- A bottle entry is either an issue or a return and is permanently scoped to
-- product ID 1, the reusable 19L Bottle product.
-- ----------------------------------------------------------------------------
CREATE TABLE public.customer_security_ledger (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    entry_type VARCHAR(20) NOT NULL,
    amount     NUMERIC(10,2) NOT NULL,
    notes      TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_customer_security_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_customer_security_created_by
        FOREIGN KEY (created_by) REFERENCES public.users (id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_customer_security_entry_type
        CHECK (entry_type IN ('collect', 'refund')),
    CONSTRAINT chk_customer_security_amount_positive
        CHECK (amount > 0)
);

CREATE INDEX idx_customer_security_customer_created
    ON public.customer_security_ledger (customer_id, created_at DESC);

CREATE TABLE public.customer_bottle_ledger (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL DEFAULT 1,
    entry_type VARCHAR(20) NOT NULL,
    quantity   INTEGER NOT NULL,
    notes      TEXT,
    created_by INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_customer_bottle_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_customer_bottle_product
        FOREIGN KEY (product_id) REFERENCES public.products (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_customer_bottle_created_by
        FOREIGN KEY (created_by) REFERENCES public.users (id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_customer_bottle_product
        CHECK (product_id = 1),
    CONSTRAINT chk_customer_bottle_entry_type
        CHECK (entry_type IN ('issue', 'return')),
    CONSTRAINT chk_customer_bottle_quantity_positive
        CHECK (quantity > 0)
);

CREATE INDEX idx_customer_bottle_customer_created
    ON public.customer_bottle_ledger (customer_id, created_at DESC);


-- Ledger tables are not directly writable/readable through the Data API.
-- The SECURITY DEFINER RPCs below are the only client-facing access path.
ALTER TABLE public.customer_security_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_bottle_ledger ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.customer_security_ledger,
  public.customer_bottle_ledger
FROM PUBLIC, anon, authenticated;


-- ----------------------------------------------------------------------------
-- collect_customer_security
-- Locks the customer row so a concurrent refund/collection for the same
-- customer serializes before the ledger balance is read or changed.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.collect_customer_security(
  target_customer_id integer,
  amount numeric,
  notes text DEFAULT NULL
)
RETURNS public.customer_security_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_customer_id integer;
  v_row public.customer_security_ledger;
BEGIN
  SELECT id
  INTO v_caller_id
  FROM public.users
  WHERE auth_user_id = v_uid
    AND role = 'admin';

  IF v_caller_id IS NULL THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  SELECT id
  INTO v_customer_id
  FROM public.customers
  WHERE id = target_customer_id
  FOR UPDATE;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF amount IS NULL OR amount <= 0 THEN
    RAISE EXCEPTION 'Security amount must be positive' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.customer_security_ledger (
    customer_id, entry_type, amount, notes, created_by
  )
  VALUES (
    v_customer_id, 'collect', amount, notes, v_caller_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ----------------------------------------------------------------------------
-- refund_customer_security
-- The customer-row lock makes the balance check and refund insert atomic for
-- this customer, preventing two concurrent refunds from exceeding the held
-- security balance.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refund_customer_security(
  target_customer_id integer,
  amount numeric,
  notes text DEFAULT NULL
)
RETURNS public.customer_security_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_customer_id integer;
  v_balance numeric(10,2);
  v_row public.customer_security_ledger;
BEGIN
  SELECT id
  INTO v_caller_id
  FROM public.users
  WHERE auth_user_id = v_uid
    AND role = 'admin';

  IF v_caller_id IS NULL THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  SELECT id
  INTO v_customer_id
  FROM public.customers
  WHERE id = target_customer_id
  FOR UPDATE;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF amount IS NULL OR amount <= 0 THEN
    RAISE EXCEPTION 'Security amount must be positive' USING ERRCODE = '22023';
  END IF;

  SELECT ROUND(COALESCE(SUM(
    CASE
      WHEN l.entry_type = 'collect' THEN l.amount
      WHEN l.entry_type = 'refund' THEN -l.amount
      ELSE 0
    END
  ), 0), 2)
  INTO v_balance
  FROM public.customer_security_ledger AS l
  WHERE l.customer_id = v_customer_id;

  IF amount > v_balance THEN
    RAISE EXCEPTION 'Security refund exceeds current balance' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.customer_security_ledger (
    customer_id, entry_type, amount, notes, created_by
  )
  VALUES (
    v_customer_id, 'refund', amount, notes, v_caller_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ----------------------------------------------------------------------------
-- issue_customer_bottles
-- Only product ID 1 with type 'bottle' is accepted. Refills and all other
-- products continue through the ordinary transaction RPCs and never affect
-- this ledger.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_customer_bottles(
  target_customer_id integer,
  quantity integer,
  notes text DEFAULT NULL
)
RETURNS public.customer_bottle_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_customer_id integer;
  v_row public.customer_bottle_ledger;
BEGIN
  SELECT id
  INTO v_caller_id
  FROM public.users
  WHERE auth_user_id = v_uid
    AND role = 'admin';

  IF v_caller_id IS NULL THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  SELECT id
  INTO v_customer_id
  FROM public.customers
  WHERE id = target_customer_id
  FOR UPDATE;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF quantity IS NULL OR quantity <= 0 THEN
    RAISE EXCEPTION 'Bottle quantity must be positive' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.products WHERE id = 1 AND type = 'bottle'
  ) THEN
    RAISE EXCEPTION 'The reusable 19L Bottle product is unavailable' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.customer_bottle_ledger (
    customer_id, product_id, entry_type, quantity, notes, created_by
  )
  VALUES (
    v_customer_id, 1, 'issue', quantity, notes, v_caller_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ----------------------------------------------------------------------------
-- return_customer_bottles
-- As with security refunds, the customer-row lock serializes the outstanding
-- quantity check and insert so concurrent returns cannot exceed issued bottles.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.return_customer_bottles(
  target_customer_id integer,
  quantity integer,
  notes text DEFAULT NULL
)
RETURNS public.customer_bottle_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_customer_id integer;
  v_issued integer;
  v_returned integer;
  v_outstanding integer;
  v_row public.customer_bottle_ledger;
BEGIN
  SELECT id
  INTO v_caller_id
  FROM public.users
  WHERE auth_user_id = v_uid
    AND role = 'admin';

  IF v_caller_id IS NULL THEN
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;
    RAISE EXCEPTION 'admin required' USING ERRCODE = '42501';
  END IF;

  SELECT id
  INTO v_customer_id
  FROM public.customers
  WHERE id = target_customer_id
  FOR UPDATE;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF quantity IS NULL OR quantity <= 0 THEN
    RAISE EXCEPTION 'Bottle quantity must be positive' USING ERRCODE = '22023';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN l.entry_type = 'issue' THEN l.quantity ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.entry_type = 'return' THEN l.quantity ELSE 0 END), 0)
  INTO v_issued, v_returned
  FROM public.customer_bottle_ledger AS l
  WHERE l.customer_id = v_customer_id
    AND l.product_id = 1;

  v_outstanding := v_issued - v_returned;
  IF quantity > v_outstanding THEN
    RAISE EXCEPTION 'Bottle return exceeds outstanding bottles' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.customer_bottle_ledger (
    customer_id, product_id, entry_type, quantity, notes, created_by
  )
  VALUES (
    v_customer_id, 1, 'return', quantity, notes, v_caller_id
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


REVOKE ALL ON FUNCTION public.collect_customer_security(integer, numeric, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.refund_customer_security(integer, numeric, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.issue_customer_bottles(integer, integer, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.return_customer_bottles(integer, integer, text)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.collect_customer_security(integer, numeric, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.refund_customer_security(integer, numeric, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_customer_bottles(integer, integer, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.return_customer_bottles(integer, integer, text)
  TO authenticated;


-- ----------------------------------------------------------------------------
-- Extend the existing summary without changing its authorization or any
-- existing response field. The normal balance remains sales minus payments;
-- security and bottle balances are separate fields.
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
  v_security_balance numeric(10,2);
  v_bottles_issued integer;
  v_bottles_returned integer;
  v_security_history jsonb;
  v_bottle_history jsonb;
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
    'auth_user_id', u.auth_user_id,
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

  SELECT ROUND(COALESCE(SUM(
    CASE
      WHEN l.entry_type = 'collect' THEN l.amount
      WHEN l.entry_type = 'refund' THEN -l.amount
      ELSE 0
    END
  ), 0), 2)
  INTO v_security_balance
  FROM public.customer_security_ledger AS l
  WHERE l.customer_id = target_customer_id;

  SELECT
    COALESCE(SUM(CASE WHEN l.entry_type = 'issue' THEN l.quantity ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN l.entry_type = 'return' THEN l.quantity ELSE 0 END), 0)
  INTO v_bottles_issued, v_bottles_returned
  FROM public.customer_bottle_ledger AS l
  WHERE l.customer_id = target_customer_id
    AND l.product_id = 1;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_security_history
  FROM (
    SELECT id, entry_type, amount, notes, created_by, created_at
    FROM public.customer_security_ledger
    WHERE customer_id = target_customer_id
    ORDER BY created_at DESC
    LIMIT 20
  ) AS s;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC), '[]'::jsonb)
  INTO v_bottle_history
  FROM (
    SELECT id, product_id, entry_type, quantity, notes, created_by, created_at
    FROM public.customer_bottle_ledger
    WHERE customer_id = target_customer_id
      AND product_id = 1
    ORDER BY created_at DESC
    LIMIT 20
  ) AS s;

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
    'recent_payments', v_payments,
    'security_balance', v_security_balance,
    'bottles', jsonb_build_object(
      'issued', v_bottles_issued,
      'returned', v_bottles_returned,
      'outstanding', v_bottles_issued - v_bottles_returned
    ),
    'security_history', v_security_history,
    'bottle_history', v_bottle_history
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_customer_summary(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_summary(integer) TO authenticated;
