-- ============================================================================
-- Migration: 005_auth_email_sync.sql
-- Purpose:   Copy auth.users.email onto the linked public.users row.
--
-- This file is not executed automatically.
-- Run it manually in the Supabase SQL editor after review.
-- It does not change existing rows by itself.
-- It does not grant the Data API access to auth.users.
-- It does not edit earlier migrations.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Trigger function
-- SECURITY DEFINER so the Auth role that updates auth.users can still write
-- public.users.email. The owner bypasses RLS. search_path is fixed.
-- A missing public.users row updates zero rows and is not an error.
-- A unique violation on public.users.email aborts the auth.users update.
-- The function never writes back to auth.users, so it cannot recurse.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.sync_user_email_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  UPDATE public.users
  SET email = NEW.email
  WHERE auth_user_id = NEW.id
    AND email IS DISTINCT FROM NEW.email;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.sync_user_email_from_auth() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.sync_user_email_from_auth() FROM anon, authenticated;


-- ----------------------------------------------------------------------------
-- Fire only when the Auth email value changes.
-- AFTER UPDATE lets a failed public.users update roll the Auth change back.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_auth_user_email_sync ON auth.users;

CREATE TRIGGER trg_auth_user_email_sync
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  WHEN (OLD.email IS DISTINCT FROM NEW.email)
  EXECUTE FUNCTION private.sync_user_email_from_auth();
