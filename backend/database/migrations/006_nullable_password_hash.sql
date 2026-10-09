-- ============================================================================
-- Migration: 006_nullable_password_hash.sql
-- Purpose:   Allow a Supabase Auth user to exist without a bcrypt hash in
--            public.users.password_hash.
--
-- This file is not executed automatically.
-- Run it manually in the Supabase SQL editor after review.
-- Express POST /api/customers still writes a bcrypt hash.
-- New Auth-created customers leave password_hash null.
-- It does not change existing rows.
-- ============================================================================

ALTER TABLE public.users
    ALTER COLUMN password_hash DROP NOT NULL;
