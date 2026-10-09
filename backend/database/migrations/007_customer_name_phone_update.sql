-- ============================================================================
-- Migration: 007_customer_name_phone_update.sql
-- Purpose:   Let an admin update a customer's name and phone from the client.
--
-- This file is not executed automatically.
-- Run it manually in the Supabase SQL editor after review.
-- It does not change existing rows.
-- It does not grant email, role, password_hash, or auth_user_id updates.
-- It does not grant updates to customer accounts.
-- Express PUT /customers/:id is unchanged.
-- ============================================================================

GRANT UPDATE (name, phone) ON public.users TO authenticated;

CREATE POLICY users_update_customer_profile
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (private.is_admin() AND role = 'customer')
  WITH CHECK (private.is_admin() AND role = 'customer');
