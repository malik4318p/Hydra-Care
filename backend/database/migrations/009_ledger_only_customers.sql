-- ============================================================================
-- Migration: 009_ledger_only_customers.sql
-- Purpose:   Allow customer ledger records without login credentials.
--
-- This file is not executed automatically.
-- It does not modify or delete existing rows or Auth identities.
-- ============================================================================

ALTER TABLE public.users
    ALTER COLUMN email DROP NOT NULL;

ALTER TABLE public.customers
    ALTER COLUMN address DROP NOT NULL;
