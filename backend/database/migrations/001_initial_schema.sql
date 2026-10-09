-- ============================================================================
-- Migration: 001_initial_schema.sql
-- Purpose:   Initial database schema for the bottled-water business
--            record-keeping system (Sprint 1).
--
-- Tables:
--   1. users         - people who can log into the system (staff/admins,
--                       and a customer's own login account if they have one)
--   2. customers     - customer profile, 1-to-1 with a user for Sprint 1
--   3. products      - things the business sells (bottles / refills)
--   4. transactions  - a sale of a product to a customer
--   5. payments      - money received from a customer
--
-- Design notes:
--   - Outstanding balance is NOT stored anywhere. It is always calculated as:
--         SUM(transactions.total_amount) - SUM(payments.amount)
--   - All money columns use NUMERIC, never floating point.
--   - Primary keys use PostgreSQL identity columns (modern replacement
--     for the old SERIAL type).
--   - This file only defines the schema. It intentionally contains no
--     seed data and is not executed automatically.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. users
-- Anyone who can access the system. The "role" column distinguishes staff
-- from customer-only accounts; a customer's extra profile fields live in
-- the "customers" table below.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(255)  NOT NULL,
    phone         VARCHAR(20)   NOT NULL,
    email         VARCHAR(255)  NOT NULL,
    password_hash VARCHAR(255)  NOT NULL,
    role          VARCHAR(50)   NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_role
        CHECK (role IN ('admin', 'customer'))
);


-- ----------------------------------------------------------------------------
-- 2. customers
-- A customer's profile. Sprint 1 treats users <-> customers as 1-to-1,
-- enforced with a UNIQUE constraint on user_id.
-- ----------------------------------------------------------------------------
CREATE TABLE customers (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    INTEGER      NOT NULL,
    address    VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_customers_user_id UNIQUE (user_id),
    CONSTRAINT fk_customers_user
        FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE RESTRICT
);


-- ----------------------------------------------------------------------------
-- 3. products
-- Things the business sells. current_price is ONLY today's price. The
-- price actually charged on a past sale is stored on transactions.unit_price
-- and must never be looked up from here for historical records.
-- ----------------------------------------------------------------------------
CREATE TABLE products (
    id            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(255)  NOT NULL,
    type          VARCHAR(20)   NOT NULL,
    current_price NUMERIC(10,2) NOT NULL,
    active        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT uq_products_name UNIQUE (name),
    CONSTRAINT chk_products_type CHECK (type IN ('bottle', 'refill')),
    CONSTRAINT chk_products_current_price_positive CHECK (current_price > 0)
);


-- ----------------------------------------------------------------------------
-- 4. transactions
-- A sale of one product to one customer. unit_price is the price actually
-- charged at the time of sale (independent of products.current_price), and
-- total_amount is always quantity x unit_price, enforced below.
-- ----------------------------------------------------------------------------
CREATE TABLE transactions (
    id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  INTEGER       NOT NULL,
    product_id   INTEGER       NOT NULL,
    quantity     INTEGER       NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    created_by   INTEGER       NOT NULL,
    notes        TEXT,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_transactions_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_transactions_product
        FOREIGN KEY (product_id) REFERENCES products (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_transactions_created_by
        FOREIGN KEY (created_by) REFERENCES users (id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_transactions_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_transactions_unit_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_transactions_total_amount_positive CHECK (total_amount > 0),
    CONSTRAINT chk_transactions_total_matches_quantity_times_price
        CHECK (total_amount = quantity * unit_price)
);

CREATE INDEX idx_transactions_customer_id ON transactions (customer_id);
CREATE INDEX idx_transactions_product_id ON transactions (product_id);
CREATE INDEX idx_transactions_created_by ON transactions (created_by);
CREATE INDEX idx_transactions_customer_id_created_at ON transactions (customer_id, created_at);


-- ----------------------------------------------------------------------------
-- 5. payments
-- Money received from a customer. transaction_id is nullable because a
-- customer may pay toward their general outstanding balance rather than
-- one specific transaction.
-- ----------------------------------------------------------------------------
CREATE TABLE payments (
    id             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    INTEGER       NOT NULL,
    transaction_id INTEGER,
    amount         NUMERIC(10,2) NOT NULL,
    payment_method VARCHAR(50)   NOT NULL,
    notes          TEXT,
    created_by     INTEGER       NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT fk_payments_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_payments_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_payments_created_by
        FOREIGN KEY (created_by) REFERENCES users (id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_payments_amount_positive CHECK (amount > 0)
);

CREATE INDEX idx_payments_customer_id ON payments (customer_id);
CREATE INDEX idx_payments_transaction_id ON payments (transaction_id);
CREATE INDEX idx_payments_created_by ON payments (created_by);
CREATE INDEX idx_payments_customer_id_created_at ON payments (customer_id, created_at);
