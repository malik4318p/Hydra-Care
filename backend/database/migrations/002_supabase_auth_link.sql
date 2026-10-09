-- ============================================================================
-- Migration: 002_supabase_auth_link.sql
-- Purpose:   Link an existing public.users row to a future Supabase Auth user.
--
-- This file is not executed automatically.
-- It does not create Auth users, change existing rows, or enable RLS.
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN auth_user_id UUID NULL,
    ADD CONSTRAINT uq_users_auth_user_id UNIQUE (auth_user_id),
    ADD CONSTRAINT fk_users_auth_user
        FOREIGN KEY (auth_user_id) REFERENCES auth.users (id)
        ON DELETE SET NULL;
