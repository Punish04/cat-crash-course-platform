-- ================================================================
-- CAT CRASHCOURSE PLATFORM — SUPABASE SCHEMA (CORRECTED / PRODUCTION)
-- Run this entire file in Supabase SQL Editor
-- Dashboard → SQL Editor → New Query → Paste → Run
--
-- CHANGES FROM PREVIOUS VERSION:
--   1. SECURITY FIX: students can no longer self-grant course_access
--   2. SECURITY FIX: students can no longer directly overwrite student_progress
--      (it is now read-only for students; only triggers/service_role can write it)
--   3. NEW: trigger auto-recalculates student_progress when lecture_progress changes
--   4. NEW: trigger auto-recalculates student_progress when a mock_attempts row is added
--   5. NEW: day_streak is now calculated automatically from real activity
--   6. NEW: explicit admin write policies for lectures / mock_tests / notes / announcements
-- ================================================================


-- ── 1. ADMINS ────────────────────────────────────────────────────
-- Stores which auth users have admin access.
-- Checked on every admin dashboard load.

CREATE TABLE IF NOT EXISTS admins (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);


-- ── 2. USERS ─────────────────────────────────────────────────────
-- Student profiles. Linked to auth.users.
-- course_access = true  → full dashboard access
-- course_access = false → access-pending page
-- course_access can ONLY be changed by an admin / service_role (see trigger below)

CREATE TABLE IF NOT EXISTS users (
  id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name      TEXT,
  email          TEXT,
  phone          TEXT,
  state          TEXT,
  course_access  BOOLEAN DEFAULT FALSE,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);


-- ── 3. PAYMENTS ──────────────────────────────────────────────────
-- Stores payment submissions from the Google Form / enrollment flow.
-- Admin reviews and approves/rejects from admin dashboard.
-- Status: pending | approved | rejected

CREATE TABLE IF NOT EXISTS payments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name      TEXT NOT NULL,
  email          TEXT NOT NULL,
  phone          TEXT,
  state          TEXT,
  screenshot_url TEXT,              -- Supabase Storage URL of UPI screenshot
  status         TEXT DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by    UUID REFERENCES auth.users(id),
  reviewed_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);


-- ── 4. LECTURES ──────────────────────────────────────────────────
-- Both live and recorded lectures live in this table.
-- type: 'live' | 'recorded'
-- category: 'QA' | 'VARC' | 'DILR'

CREATE TABLE IF NOT EXISTS lectures (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title         TEXT NOT NULL,
  type          TEXT NOT NULL CHECK (type IN ('live','recorded')),
  category      TEXT CHECK (category IN ('QA','VARC','DILR')),
  faculty       TEXT,
  date          DATE,                  -- For live lectures
  time          TEXT,                  -- e.g. "20:00" — display only
  join_link     TEXT,                  -- Zoom / Google Meet URL for live
  video_url     TEXT,                  -- YouTube / Vimeo / Supabase storage URL
  thumbnail_url TEXT,
  slug          TEXT UNIQUE,           -- URL-friendly ID for /lecture?slug=...
  duration      TEXT,                  -- e.g. "1h 30min"
  resources     JSONB DEFAULT '[]',    -- Array of {name, url, type}
  published     BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);


-- ── 5. LECTURE PROGRESS ──────────────────────────────────────────
-- Tracks per-student per-lecture completion and last viewed time.
-- Used for resume capability and progress bars.
-- Students may write to THIS table directly (it's a raw activity log).
-- student_progress (the aggregated stats) is then derived from this
-- automatically via trigger — students never touch it directly.

CREATE TABLE IF NOT EXISTS lecture_progress (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lecture_id     UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
  completed      BOOLEAN DEFAULT FALSE,
  last_viewed_at TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, lecture_id)
);


-- ── 6. STUDENT PROGRESS ──────────────────────────────────────────
-- Aggregated progress per student. Displayed on dashboard stats cards.
-- READ-ONLY for students. Only written by trigger functions below
-- (which run as SECURITY DEFINER, bypassing RLS) or by service_role.
-- This is what prevents a student from typing course_progress: 100
-- into the browser console.

CREATE TABLE IF NOT EXISTS student_progress (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  course_progress     INTEGER DEFAULT 0,   -- Overall % (0–100)
  lectures_completed  INTEGER DEFAULT 0,
  mock_attempts       INTEGER DEFAULT 0,
  day_streak          INTEGER DEFAULT 0,
  qa_progress         INTEGER DEFAULT 0,   -- QA section % (0–100)
  varc_progress       INTEGER DEFAULT 0,
  dilr_progress       INTEGER DEFAULT 0,
  last_active_date    DATE,                -- Used internally for streak calculation
  last_active_at      TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);


-- ── 7. MOCK TESTS ────────────────────────────────────────────────
-- Holds test definitions. Attempts tracked in mock_attempts table.
-- status: 'available' | 'completed' | 'coming_soon'

CREATE TABLE IF NOT EXISTS mock_tests (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title            TEXT NOT NULL,
  total_questions  INTEGER DEFAULT 66,
  duration         TEXT DEFAULT '3 hrs',
  link             TEXT,                   -- External test link or internal page
  status           TEXT DEFAULT 'coming_soon' CHECK (status IN ('available','completed','coming_soon')),
  created_at       TIMESTAMPTZ DEFAULT NOW()
);


-- ── 8. MOCK ATTEMPTS ─────────────────────────────────────────────
-- Tracks which student attempted which mock test and their score.
-- Students insert their own attempt (score should ideally be verified
-- server-side by an Edge Function for high-stakes tests — see note below).

CREATE TABLE IF NOT EXISTS mock_attempts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mock_id     UUID NOT NULL REFERENCES mock_tests(id) ON DELETE CASCADE,
  score       INTEGER,
  percentile  NUMERIC(5,2),
  attempted_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, mock_id)
);


-- ── 9. NOTES ─────────────────────────────────────────────────────
-- PDF notes uploaded by admin. Students can download.

CREATE TABLE IF NOT EXISTS notes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  category    TEXT CHECK (category IN ('QA','VARC','DILR','General')),
  file_url    TEXT NOT NULL,              -- Supabase Storage URL
  created_at  TIMESTAMPTZ DEFAULT NOW()
);


-- ── 10. ANNOUNCEMENTS ────────────────────────────────────────────
-- Admin posts announcements. Shown on student dashboard.

CREATE TABLE IF NOT EXISTS announcements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message     TEXT NOT NULL,
  created_by  UUID REFERENCES auth.users(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);


-- ── 11. NOTIFICATIONS ────────────────────────────────────────────
-- Per-user notification records. Future use.

CREATE TABLE IF NOT EXISTS notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message    TEXT NOT NULL,
  read       BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ================================================================
-- HELPER FUNCTION — is the current request from an admin?
-- Used across multiple RLS policies below.
-- ================================================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM admins WHERE user_id = auth.uid());
$$;


-- ================================================================
-- ROW LEVEL SECURITY (RLS)
-- Enable RLS on every table.
-- Students can only read/write their own data, and never the
-- aggregated stats or access-control flags directly.
-- Admins can read/write management tables via the admins table check,
-- or bypass entirely via the service_role key (Edge Functions).
-- ================================================================

ALTER TABLE admins              ENABLE ROW LEVEL SECURITY;
ALTER TABLE users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE lectures            ENABLE ROW LEVEL SECURITY;
ALTER TABLE lecture_progress    ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_progress    ENABLE ROW LEVEL SECURITY;
ALTER TABLE mock_tests          ENABLE ROW LEVEL SECURITY;
ALTER TABLE mock_attempts       ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes               ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements       ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications       ENABLE ROW LEVEL SECURITY;


-- ── ADMINS ──
-- Only admins can read the admins table (to check own status)
CREATE POLICY "admin_read_self" ON admins
  FOR SELECT USING (user_id = auth.uid());


-- ── USERS ──
-- Students can read only their own row
CREATE POLICY "users_read_self" ON users
  FOR SELECT USING (id = auth.uid());

-- Students can update their own row (full_name, phone, state etc.)
-- course_access is protected separately by a BEFORE UPDATE trigger below,
-- so even though this policy allows the UPDATE, the privileged column
-- cannot actually change unless the request is from an admin/service_role.
CREATE POLICY "users_update_self" ON users
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- Allow insert (triggered on first login / account creation)
CREATE POLICY "users_insert_self" ON users
  FOR INSERT WITH CHECK (id = auth.uid());

-- Admins can read and update any student row (approvals, support, etc.)
CREATE POLICY "users_admin_all" ON users
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- SECURITY FIX: prevent students from self-granting course_access
-- (or any other privileged field) by directly calling supabase.update().
-- If a non-admin tries to change course_access, this trigger silently
-- reverts it back to the original value before the row is written.
CREATE OR REPLACE FUNCTION protect_privileged_user_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.course_access IS DISTINCT FROM OLD.course_access AND NOT is_admin() THEN
    NEW.course_access := OLD.course_access;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_privileged_user_columns ON users;
CREATE TRIGGER trg_protect_privileged_user_columns
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION protect_privileged_user_columns();


-- ── PAYMENTS ──
-- Anyone can insert a payment submission (public enrollment)
CREATE POLICY "payments_insert_public" ON payments
  FOR INSERT WITH CHECK (TRUE);

-- Students can only read their own payment record
CREATE POLICY "payments_read_self" ON payments
  FOR SELECT USING (email = (SELECT email FROM users WHERE id = auth.uid()));

-- Admins can read and update all payments (approve/reject)
CREATE POLICY "payments_admin_all" ON payments
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── LECTURES ──
-- All authenticated users with course_access can read published lectures
CREATE POLICY "lectures_read_authenticated" ON lectures
  FOR SELECT USING (
    published = TRUE AND
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND course_access = TRUE)
  );

-- Admins can create/update/delete lectures directly from the admin dashboard
CREATE POLICY "lectures_admin_all" ON lectures
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── LECTURE PROGRESS ──
-- Students can read and write only their own progress.
-- This is intentionally writable by students — it's a raw activity log
-- ("I watched lecture X"), not the trusted aggregate. The aggregate
-- (student_progress) is recalculated server-side from this table.
CREATE POLICY "lp_read_self" ON lecture_progress
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "lp_insert_self" ON lecture_progress
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "lp_update_self" ON lecture_progress
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "lp_admin_read" ON lecture_progress
  FOR SELECT USING (is_admin());


-- ── STUDENT PROGRESS ──
-- SECURITY FIX: students get READ-ONLY access. No insert/update policy
-- for students at all — this table can now only be written by:
--   (a) the trigger functions below (SECURITY DEFINER, bypass RLS), or
--   (b) an admin / the service_role key.
CREATE POLICY "sp_read_self" ON student_progress
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "sp_admin_all" ON student_progress
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── MOCK TESTS ──
-- Authenticated students with access can read
CREATE POLICY "mocks_read_authenticated" ON mock_tests
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND course_access = TRUE)
  );

-- Admins can create/update/delete mock test definitions
CREATE POLICY "mocks_admin_all" ON mock_tests
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── MOCK ATTEMPTS ──
CREATE POLICY "ma_read_self" ON mock_attempts
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "ma_insert_self" ON mock_attempts
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "ma_admin_read" ON mock_attempts
  FOR SELECT USING (is_admin());

-- NOTE: for high-stakes scored mocks, consider moving score submission
-- into an Edge Function instead of a direct client insert, so a student
-- can't insert a fake score/percentile from devtools.


-- ── NOTES ──
CREATE POLICY "notes_read_authenticated" ON notes
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND course_access = TRUE)
  );

CREATE POLICY "notes_admin_all" ON notes
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── ANNOUNCEMENTS ──
-- All authenticated users with access can read
CREATE POLICY "ann_read_authenticated" ON announcements
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND course_access = TRUE)
  );

CREATE POLICY "ann_admin_all" ON announcements
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ── NOTIFICATIONS ──
CREATE POLICY "notif_read_self" ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "notif_update_self" ON notifications
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "notif_admin_all" ON notifications
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());


-- ================================================================
-- AUTO-PROGRESS TRIGGERS
-- This is the part that makes the dashboard stats update automatically
-- as a student actually progresses, instead of sitting frozen at 0.
-- ================================================================

-- ── Recalculate student_progress whenever lecture_progress changes ──
CREATE OR REPLACE FUNCTION recalculate_student_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id           UUID := NEW.user_id;
  v_total_lectures     INTEGER;
  v_completed_lectures INTEGER;
  v_total_qa            INTEGER;
  v_completed_qa        INTEGER;
  v_total_varc          INTEGER;
  v_completed_varc      INTEGER;
  v_total_dilr           INTEGER;
  v_completed_dilr       INTEGER;
  v_prev_last_active_date DATE;
  v_new_streak          INTEGER;
BEGIN
  -- Overall counts (recorded lectures only — live classes don't count toward "completion")
  SELECT COUNT(*) INTO v_total_lectures FROM lectures WHERE published = TRUE AND type = 'recorded';
  SELECT COUNT(*) INTO v_completed_lectures
    FROM lecture_progress lp
    JOIN lectures l ON l.id = lp.lecture_id
    WHERE lp.user_id = v_user_id AND lp.completed = TRUE AND l.type = 'recorded';

  -- Per-category counts
  SELECT COUNT(*) INTO v_total_qa FROM lectures WHERE published = TRUE AND type = 'recorded' AND category = 'QA';
  SELECT COUNT(*) INTO v_completed_qa
    FROM lecture_progress lp JOIN lectures l ON l.id = lp.lecture_id
    WHERE lp.user_id = v_user_id AND lp.completed = TRUE AND l.category = 'QA';

  SELECT COUNT(*) INTO v_total_varc FROM lectures WHERE published = TRUE AND type = 'recorded' AND category = 'VARC';
  SELECT COUNT(*) INTO v_completed_varc
    FROM lecture_progress lp JOIN lectures l ON l.id = lp.lecture_id
    WHERE lp.user_id = v_user_id AND lp.completed = TRUE AND l.category = 'VARC';

  SELECT COUNT(*) INTO v_total_dilr FROM lectures WHERE published = TRUE AND type = 'recorded' AND category = 'DILR';
  SELECT COUNT(*) INTO v_completed_dilr
    FROM lecture_progress lp JOIN lectures l ON l.id = lp.lecture_id
    WHERE lp.user_id = v_user_id AND lp.completed = TRUE AND l.category = 'DILR';

  -- Day streak: compare today's date to the last recorded activity date
  SELECT last_active_date, day_streak INTO v_prev_last_active_date, v_new_streak
    FROM student_progress WHERE user_id = v_user_id;

  IF v_prev_last_active_date IS NULL THEN
    v_new_streak := 1;
  ELSIF v_prev_last_active_date = CURRENT_DATE THEN
    v_new_streak := COALESCE(v_new_streak, 1);              -- already counted today, no change
  ELSIF v_prev_last_active_date = CURRENT_DATE - INTERVAL '1 day' THEN
    v_new_streak := COALESCE(v_new_streak, 0) + 1;            -- consecutive day
  ELSE
    v_new_streak := 1;                                        -- streak broken, restart
  END IF;

  -- Upsert the aggregate row
  INSERT INTO student_progress (
    user_id, course_progress, lectures_completed,
    qa_progress, varc_progress, dilr_progress,
    day_streak, last_active_date, last_active_at, updated_at
  )
  VALUES (
    v_user_id,
    CASE WHEN v_total_lectures = 0 THEN 0 ELSE ROUND(100.0 * v_completed_lectures / v_total_lectures) END,
    v_completed_lectures,
    CASE WHEN v_total_qa   = 0 THEN 0 ELSE ROUND(100.0 * v_completed_qa   / v_total_qa)   END,
    CASE WHEN v_total_varc = 0 THEN 0 ELSE ROUND(100.0 * v_completed_varc / v_total_varc) END,
    CASE WHEN v_total_dilr = 0 THEN 0 ELSE ROUND(100.0 * v_completed_dilr / v_total_dilr) END,
    v_new_streak,
    CURRENT_DATE,
    NOW(),
    NOW()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    course_progress  = EXCLUDED.course_progress,
    lectures_completed = EXCLUDED.lectures_completed,
    qa_progress      = EXCLUDED.qa_progress,
    varc_progress    = EXCLUDED.varc_progress,
    dilr_progress    = EXCLUDED.dilr_progress,
    day_streak       = EXCLUDED.day_streak,
    last_active_date = EXCLUDED.last_active_date,
    last_active_at   = EXCLUDED.last_active_at,
    updated_at       = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalculate_student_progress ON lecture_progress;
CREATE TRIGGER trg_recalculate_student_progress
  AFTER INSERT OR UPDATE ON lecture_progress
  FOR EACH ROW EXECUTE FUNCTION recalculate_student_progress();


-- ── Recalculate mock_attempts count whenever a mock attempt is logged ──
CREATE OR REPLACE FUNCTION recalculate_mock_attempts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM mock_attempts WHERE user_id = NEW.user_id;

  INSERT INTO student_progress (user_id, mock_attempts, updated_at)
  VALUES (NEW.user_id, v_count, NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    mock_attempts = EXCLUDED.mock_attempts,
    updated_at    = NOW();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalculate_mock_attempts ON mock_attempts;
CREATE TRIGGER trg_recalculate_mock_attempts
  AFTER INSERT ON mock_attempts
  FOR EACH ROW EXECUTE FUNCTION recalculate_mock_attempts();


-- ── Auto-create a student_progress row whenever a new user row is created ──
-- (Belt-and-suspenders — the approve-payment Edge Function also upserts
-- this row, but this trigger guarantees it always exists.)
CREATE OR REPLACE FUNCTION init_student_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO student_progress (user_id) VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_init_student_progress ON users;
CREATE TRIGGER trg_init_student_progress
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION init_student_progress();


-- ================================================================
-- INDEXES — for performance
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_users_email           ON users(email);
CREATE INDEX IF NOT EXISTS idx_payments_email        ON payments(email);
CREATE INDEX IF NOT EXISTS idx_payments_status       ON payments(status);
CREATE INDEX IF NOT EXISTS idx_lectures_type         ON lectures(type);
CREATE INDEX IF NOT EXISTS idx_lectures_slug         ON lectures(slug);
CREATE INDEX IF NOT EXISTS idx_lectures_category     ON lectures(category);
CREATE INDEX IF NOT EXISTS idx_lp_user               ON lecture_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_lp_lecture            ON lecture_progress(lecture_id);
CREATE INDEX IF NOT EXISTS idx_sp_user               ON student_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_mock_attempts_user    ON mock_attempts(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user    ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_announcements_date    ON announcements(created_at DESC);


-- ================================================================
-- STORAGE BUCKETS
-- Run these in Supabase Dashboard → Storage → New Bucket
-- OR uncomment and run via SQL if storage extension is enabled
-- ================================================================

-- INSERT INTO storage.buckets (id, name, public) VALUES ('videos',          'videos',          false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('notes',           'notes',           false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('thumbnails',      'thumbnails',      true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('payment-proofs',  'payment-proofs',  false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('downloads',       'downloads',       false);


-- ================================================================
-- SEED DATA — optional starter rows
-- Uncomment to add sample data for testing
-- ================================================================

-- Sample announcement
-- INSERT INTO announcements (message) VALUES
--   ('Welcome to CAT CrashCourse 2025! Your first live class starts this Monday at 8 PM IST. Check the schedule on your dashboard.');

-- Sample mock tests
-- INSERT INTO mock_tests (title, status, total_questions, duration) VALUES
--   ('CAT Mock Test 1 — Full Length', 'available',  66, '3 hrs'),
--   ('CAT Mock Test 2 — Full Length', 'coming_soon', 66, '3 hrs'),
--   ('CAT Mock Test 3 — Full Length', 'coming_soon', 66, '3 hrs');

-- Sample live lecture (today's date)
-- INSERT INTO lectures (title, type, category, faculty, date, time, join_link) VALUES
--   ('Quantitative Aptitude — Percentages & Ratios', 'live', 'QA', 'Arjun Rawat', CURRENT_DATE, '20:00', 'https://zoom.us/j/example');


-- ================================================================
-- DONE. Your database is ready.
--
-- WHAT YOU STILL NEED TO DO IN lecture.html:
--   When a video ends (or crosses ~90% watched), call:
--     await supabase.from('lecture_progress').upsert({
--       user_id: session.user.id,
--       lecture_id: currentLectureId,
--       completed: true,
--       last_viewed_at: new Date().toISOString()
--     });
--   That single call is now enough — the trigger above will automatically
--   recalculate course_progress, lectures_completed, qa/varc/dilr %, and
--   day_streak. The student CANNOT fake this by editing student_progress
--   directly, since that table is read-only for them.
--
-- Next steps:
--   1. Copy your Project URL + anon key into all HTML files
--      (search for: YOUR_SUPABASE_URL and YOUR_SUPABASE_ANON_KEY)
--   2. Create your first admin user:
--      a. Sign up via Supabase Auth (Dashboard → Auth → Users → Invite)
--      b. Then run: INSERT INTO admins (user_id) VALUES ('<your-user-id>');
--   3. Create storage buckets listed above
--   4. Deploy your HTML files to any static host (Netlify, Vercel, etc.)
-- ================================================================