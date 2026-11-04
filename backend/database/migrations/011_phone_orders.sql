-- ============================================================================
-- Migration: 011_phone_orders.sql
-- Purpose:   Phone orders and delivery management.
--
-- Workflow: phone call -> create_phone_order (status 'pending', no financial
-- effect) -> admin marks delivered -> deliver_phone_order generates one
-- `transactions` row per order item, atomically, exactly once.
--
-- This file is not executed automatically. Run it manually in the Supabase
-- SQL editor after review. It does not modify or delete any existing row,
-- and it does not change the behavior of 001-010.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. orders / order_items
--
-- `order_items.product_name` and `order_items.unit_price` are snapshots
-- taken at order-creation time (same idea as `transactions.unit_price`
-- being independent of `products.current_price`). A later catalogue price
-- or name change must never change an existing order's values.
-- ----------------------------------------------------------------------------
CREATE TABLE public.orders (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  INTEGER       NOT NULL,
    status       VARCHAR(20)   NOT NULL DEFAULT 'pending',
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    notes        TEXT,
    created_by   INTEGER       NOT NULL,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    delivered_at TIMESTAMPTZ,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_orders_created_by
        FOREIGN KEY (created_by) REFERENCES public.users (id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_orders_status
        CHECK (status IN ('pending', 'delivered')),
    CONSTRAINT chk_orders_total_amount_nonnegative
        CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_delivered_at_consistency
        CHECK (
            (status = 'pending' AND delivered_at IS NULL)
            OR (status = 'delivered' AND delivered_at IS NOT NULL)
        )
);

CREATE INDEX idx_orders_customer_id ON public.orders (customer_id);
CREATE INDEX idx_orders_created_at ON public.orders (created_at);
CREATE INDEX idx_orders_status_created_at ON public.orders (status, created_at);
-- Delivered Orders filters on delivered_at and only ever looks at delivered
-- rows, so a partial index keeps that scan small as pending orders grow.
CREATE INDEX idx_orders_delivered_at ON public.orders (delivered_at)
    WHERE status = 'delivered';


CREATE TABLE public.order_items (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     INTEGER       NOT NULL,
    product_id   INTEGER       NOT NULL,
    product_name VARCHAR(255)  NOT NULL,
    quantity     INTEGER       NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES public.orders (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id) REFERENCES public.products (id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_order_items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_order_items_unit_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_order_items_total_amount_positive CHECK (total_amount > 0),
    CONSTRAINT chk_order_items_total_matches_quantity_times_price
        CHECK (total_amount = quantity * unit_price)
);

CREATE INDEX idx_order_items_order_id ON public.order_items (order_id);
CREATE INDEX idx_order_items_product_id ON public.order_items (product_id);


-- ----------------------------------------------------------------------------
-- 2. Link transactions to the order item that generated them.
--
-- Nullable: ordinary sales recorded directly through the Transactions screen
-- keep order_item_id NULL, unaffected. The UNIQUE constraint is the hard
-- duplicate-generation guard: at most one transaction row can ever reference
-- a given order item, independent of application-level checks, so a repeated
-- or racing delivery call cannot produce a second sale for the same line.
-- ----------------------------------------------------------------------------
ALTER TABLE public.transactions
    ADD COLUMN order_item_id INTEGER,
    ADD CONSTRAINT fk_transactions_order_item
        FOREIGN KEY (order_item_id) REFERENCES public.order_items (id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT uq_transactions_order_item_id UNIQUE (order_item_id);


-- ----------------------------------------------------------------------------
-- 3. RLS / grants
--
-- Same shape as every other table: RLS on, REVOKE ALL, SELECT granted to
-- authenticated with an admin-only policy. There are no client INSERT /
-- UPDATE / DELETE grants or policies on orders or order_items — all writes
-- go through the SECURITY DEFINER RPCs below, which run as the table owner
-- and therefore bypass RLS, exactly like create_transaction already does.
-- Phone orders are an admin tool; there is no customer-facing "own orders"
-- policy.
-- ----------------------------------------------------------------------------
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.orders, public.order_items
FROM PUBLIC, anon, authenticated;

GRANT SELECT (
    id,
    customer_id,
    status,
    total_amount,
    notes,
    created_by,
    created_at,
    updated_at,
    delivered_at
) ON public.orders TO authenticated;

GRANT SELECT (
    id,
    order_id,
    product_id,
    product_name,
    quantity,
    unit_price,
    total_amount,
    created_at
) ON public.order_items TO authenticated;

CREATE POLICY orders_select_admin
    ON public.orders
    FOR SELECT
    TO authenticated
    USING (private.is_admin());

CREATE POLICY order_items_select_admin
    ON public.order_items
    FOR SELECT
    TO authenticated
    USING (private.is_admin());


-- ----------------------------------------------------------------------------
-- create_phone_order
--
-- Admin only. Customer must exist and be active (same rule create_transaction
-- already enforces for a brand-new sale). `items` is a JSON array of
-- {"product_id": int, "quantity": int}; at least one item is required. Each
-- product's current name and current_price are copied into order_items as
-- permanent snapshots. Creates the order and its items only — no
-- transactions row, no balance effect, matching the "Pending" step of the
-- workflow.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_phone_order(
  customer_id integer,
  items jsonb,
  notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_role text;
  v_customer_active boolean;
  v_order_id integer;
  v_order public.orders;
  v_total numeric(10,2) := 0;
  v_item jsonb;
  v_product_id integer;
  v_quantity integer;
  v_unit_price numeric(10,2);
  v_product_name varchar(255);
  v_item_total numeric(10,2);
  v_items jsonb;
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

  SELECT active
  INTO v_customer_active
  FROM public.customers
  WHERE id = customer_id;

  IF v_customer_active IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_customer_active THEN
    RAISE EXCEPTION 'This customer is archived and cannot be used for a new order' USING ERRCODE = '22023';
  END IF;

  IF items IS NULL OR jsonb_typeof(items) IS DISTINCT FROM 'array' OR jsonb_array_length(items) = 0 THEN
    RAISE EXCEPTION 'At least one order item is required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.orders (customer_id, status, total_amount, notes, created_by)
  VALUES (customer_id, 'pending', 0, notes, v_caller_id)
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(items)
  LOOP
    IF NOT (v_item ? 'product_id') OR NOT (v_item ? 'quantity') THEN
      RAISE EXCEPTION 'Each item requires product_id and quantity' USING ERRCODE = '22023';
    END IF;

    v_product_id := (v_item->>'product_id')::integer;
    v_quantity := (v_item->>'quantity')::integer;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'invalid quantity' USING ERRCODE = '22023';
    END IF;

    SELECT name, current_price
    INTO v_product_name, v_unit_price
    FROM public.products
    WHERE id = v_product_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not found' USING ERRCODE = 'P0002';
    END IF;

    v_item_total := v_quantity * v_unit_price;
    v_total := v_total + v_item_total;

    INSERT INTO public.order_items (
      order_id, product_id, product_name, quantity, unit_price, total_amount
    )
    VALUES (
      v_order_id, v_product_id, v_product_name, v_quantity, v_unit_price, v_item_total
    );
  END LOOP;

  UPDATE public.orders
  SET total_amount = v_total,
      updated_at = now()
  WHERE id = v_order_id
  RETURNING * INTO v_order;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.id), '[]'::jsonb)
  INTO v_items
  FROM public.order_items AS i
  WHERE i.order_id = v_order_id;

  RETURN jsonb_build_object(
    'order', to_jsonb(v_order),
    'items', v_items
  );
END;
$$;


-- ----------------------------------------------------------------------------
-- deliver_phone_order
--
-- Admin only. Atomic: the whole function is one Postgres transaction, so a
-- failure partway through (for example an archived customer now blocked by
-- trg_transactions_block_archived_customer) rolls back every insert and the
-- status change together — the order is never left Delivered without its
-- transactions, and never left with orphaned transactions either.
--
-- Duplicate prevention has two layers:
--   1. `SELECT ... FOR UPDATE` locks the order row, so a second concurrent
--      call for the same order blocks until the first commits, then sees
--      status = 'delivered' and raises before inserting anything.
--   2. `uq_transactions_order_item_id` is a database-level backstop: even if
--      the above were somehow bypassed, a second insert for the same order
--      item violates the unique constraint and the whole call fails,
--      guaranteeing one order item never produces two transactions.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deliver_phone_order(
  target_order_id integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_id integer;
  v_role text;
  v_order public.orders;
  v_item public.order_items;
  v_txn public.transactions;
  v_transactions jsonb := '[]'::jsonb;
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
  INTO v_order
  FROM public.orders
  WHERE id = target_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_order.status <> 'pending' THEN
    RAISE EXCEPTION 'Order has already been delivered' USING ERRCODE = '22023';
  END IF;

  -- Explicitly qualified: `order_id` alone would be ambiguous here between
  -- the order_items column and (before this rename) the function parameter.
  FOR v_item IN
    SELECT * FROM public.order_items WHERE order_items.order_id = v_order.id ORDER BY id
  LOOP
    INSERT INTO public.transactions (
      customer_id, product_id, quantity, unit_price, total_amount,
      created_by, notes, order_item_id
    )
    VALUES (
      v_order.customer_id,
      v_item.product_id,
      v_item.quantity,
      v_item.unit_price,
      v_item.total_amount,
      v_caller_id,
      'Phone order #' || v_order.id,
      v_item.id
    )
    RETURNING * INTO v_txn;

    v_transactions := v_transactions || jsonb_build_array(to_jsonb(v_txn));
  END LOOP;

  UPDATE public.orders
  SET status = 'delivered',
      delivered_at = now(),
      updated_at = now()
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  RETURN jsonb_build_object(
    'order', to_jsonb(v_order),
    'transactions', v_transactions
  );
END;
$$;


REVOKE ALL ON FUNCTION public.create_phone_order(integer, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.deliver_phone_order(integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_phone_order(integer, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_phone_order(integer) TO authenticated;
