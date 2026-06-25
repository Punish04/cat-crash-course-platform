-- ================================================================
-- CAT CRASHCOURSE — APPROVE PAYMENT DATABASE FUNCTION
-- Run this in: Supabase Dashboard → SQL Editor → New Query → Run
--
-- WHAT THIS DOES:
--   This function lets the admin approve a payment and send the
--   student a set-password invite email — entirely server-side,
--   without needing the service_role key in the browser or CLI.
--
-- HOW IT WORKS:
--   1. Admin clicks "Approve" in admin/index.html
--   2. Frontend calls: supabase.rpc('fn_approve_payment', { ... })
--   3. This function runs on the DB server with SECURITY DEFINER
--      (meaning it runs as the DB owner, not as the logged-in user)
--   4. It calls Supabase's built-in auth.invite_user_by_email()
--   5. Student receives email → clicks link → set-password.html
--
-- STEP-BY-STEP SETUP:
--   1. Run this entire file in Supabase SQL Editor
--   2. Go to Supabase Dashboard → Authentication → Email Templates
--   3. Edit the "Invite" template — make sure the link points to:
--      {{ .SiteURL }}/pages/set-password.html#access_token={{ .Token }}&type=invite
--   4. That's it. The admin Approve button will now work fully.
-- ================================================================


-- ── GRANT ADMIN EXECUTE PERMISSION ──────────────────────────────
-- Only admin users (those in the admins table) can call this function.
-- The is_admin() function already exists from schema.sql.

CREATE OR REPLACE FUNCTION fn_approve_payment(
  p_payment_id  UUID,
  p_email       TEXT,
  p_full_name   TEXT,
  p_site_url    TEXT DEFAULT 'https://yoursite.com'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id    UUID;
  v_invite_url TEXT;
BEGIN

  -- ── Security check: only admins can call this ──────────────────
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- ── Build the redirect URL for the invite email ────────────────
  v_invite_url := p_site_url || '/pages/set-password.html';

  -- ── Check if a Supabase Auth user already exists for this email ─
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;

  -- ── If no auth user yet, create one via invite ─────────────────
  -- Supabase's auth.invite_user_by_email sends the set-password email
  IF v_user_id IS NULL THEN
    SELECT id INTO v_user_id
    FROM auth.invite_user_by_email(
      p_email,
      jsonb_build_object('full_name', p_full_name),
      v_invite_url
    );
  END IF;

  -- ── Upsert student profile with course_access = true ──────────
  INSERT INTO public.users (id, full_name, email, course_access)
  VALUES (v_user_id, p_full_name, p_email, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    full_name     = EXCLUDED.full_name,
    course_access = TRUE,
    updated_at    = NOW();

  -- ── Init student progress row ──────────────────────────────────
  INSERT INTO public.student_progress (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- ── Mark payment as approved ───────────────────────────────────
  UPDATE public.payments
  SET
    status      = 'approved',
    reviewed_by = auth.uid(),
    reviewed_at = NOW()
  WHERE id = p_payment_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'user_id', v_user_id,
    'email',   p_email
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', FALSE,
    'error',   SQLERRM
  );
END;
$$;


-- ── GRANT EXECUTE TO AUTHENTICATED USERS ────────────────────────
-- The is_admin() check inside the function blocks non-admins anyway,
-- but we still need to grant execute so the RPC call is allowed.
GRANT EXECUTE ON FUNCTION fn_approve_payment(UUID, TEXT, TEXT, TEXT)
  TO authenticated;


-- ================================================================
-- VERIFY IT'S INSTALLED:
-- Run this to confirm the function exists:
--   SELECT proname FROM pg_proc WHERE proname = 'fn_approve_payment';
-- Expected result: one row with "fn_approve_payment"
-- ================================================================
