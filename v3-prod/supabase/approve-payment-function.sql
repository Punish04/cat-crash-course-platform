-- Drop and recreate the function with all fixes applied
CREATE OR REPLACE FUNCTION public.fn_approve_payment(
  p_payment_id  UUID,
  p_email       TEXT,
  p_full_name   TEXT,
  p_site_url    TEXT DEFAULT 'https://cat-crash-course-platform.careerchoice360.in'
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

  -- Build the redirect URL for the invite email
  v_invite_url := 'https://cat-crash-course-platform.careerchoice360.in/pages/set-password.html';

  -- Check if a Supabase Auth user already exists for this email
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;

  -- If no auth user yet, create one via invite
  IF v_user_id IS NULL THEN
    SELECT id INTO v_user_id
    FROM auth.invite_user_by_email(
      p_email,
      jsonb_build_object('full_name', p_full_name),
      v_invite_url
    );
  END IF;

  -- Upsert student profile with course_access = true
  INSERT INTO public.users (id, full_name, email, course_access)
  VALUES (v_user_id, p_full_name, p_email, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    full_name     = EXCLUDED.full_name,
    course_access = TRUE,
    updated_at    = NOW();

  -- Init student progress row
  INSERT INTO public.student_progress (user_id)
  VALUES (v_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Mark payment as approved
  UPDATE public.payments
  SET
    status      = 'approved',
    reviewed_by = NULL,
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

-- Grant execute to both anon and authenticated
GRANT EXECUTE ON FUNCTION public.fn_approve_payment(UUID, TEXT, TEXT, TEXT)
  TO anon, authenticated;
