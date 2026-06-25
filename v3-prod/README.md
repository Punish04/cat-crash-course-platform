# CAT CrashCourse Platform
### by CareerChoice360

A complete, production-ready educational platform for CAT 2025 aspirants.
Built with vanilla HTML/CSS/JS + Tailwind CDN + Supabase.

> **For AI agents / LLMs reading this file:** This README is structured to be machine-extractable. Every setup step is sequential, every env variable is named exactly as it must appear in code, and every "must verify" item is flagged. Follow sections in order — do not skip the **Security Hardening** or **Pre-Launch Checklist** sections even if the app "looks done" after Quick Setup.

---

## Project Structure

```
cat-platform/
│
├── index.html                  ← Public homepage (hero, course, faculty, enroll)
│
├── pages/
│   ├── set-password.html       ← Linked from Supabase invite email (FIRST-TIME students land here)
│   ├── login.html              ← Returning student login + forgot password
│   ├── access-pending.html     ← Shown when logged in but not yet approved
│   ├── dashboard.html          ← Main student dashboard
│   ├── lecture.html            ← Protected lecture player (?slug=...)
│   └── profile.html            ← Student profile + settings
│
├── admin/
│   └── index.html              ← Admin dashboard (payments, students, lectures)
│
├── sections/home/              ← Homepage section fragments (for reference)
│   ├── hero.html
│   ├── course.html
│   ├── faculty.html
│   ├── enroll.html
│   └── footer.html
│
├── components/
│   └── navbar.js               ← Navbar render function (reusable)
│
├── services/
│   └── auth.js                 ← Auth service (all Supabase auth methods)
│
├── supabase/
│   ├── client.js                          ← Supabase client initialisation
│   ├── schema.sql                         ← ⭐ Full DB schema — run this first
│   └── functions/
│       ├── approve-payment/index.ts       ← Approves payment + invites student
│       └── get-signed-video-url/index.ts  ← Issues short-lived signed URL for protected video
│
├── scripts/
│   └── toast.js                ← Toast notification utility
│
└── styles/
    └── global.css              ← Design tokens + shared styles
```

---

## Environment Variables

Never hardcode secrets into HTML/JS files that ship to the browser. Use the table below to know what's public vs private.

| Variable | Where it lives | Exposed to browser? | Purpose |
|---|---|---|---|
| `SUPABASE_URL` | Frontend (`supabase/client.js`) | ✅ Yes — safe | Project endpoint |
| `SUPABASE_ANON_KEY` | Frontend (`supabase/client.js`) | ✅ Yes — safe (protected by RLS) | Public client key |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function env only | ❌ NEVER | Bypasses RLS — full DB access |
| `SITE_URL` | Edge Function env | ❌ No | Used to build redirect URLs |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` | Supabase Dashboard → Auth → SMTP settings | ❌ No | Custom email sending (see Step 6) |
| `RAZORPAY_KEY_ID` | Frontend (checkout widget) | ✅ Yes — safe | Public payment key |
| `RAZORPAY_KEY_SECRET` | Edge Function env only | ❌ NEVER | Payment verification |

**Rule of thumb the AI agent should enforce:** if a key can revoke RLS, send emails as the project, or move money — it goes in an Edge Function's environment, never in a `.html` or `.js` file that is served to the browser.

---

## Quick Setup (Step by Step)

### Step 1 — Create Supabase Project
1. Go to [supabase.com](https://supabase.com) → New Project
2. Choose a name, set a strong database password, pick a region close to India
3. **Create two projects, not one** — `cat-platform-staging` and `cat-platform-production`. Run every step below on staging first, verify it works, then repeat on production. Never test against production data.

### Step 2 — Run the Schema
1. Supabase Dashboard → **SQL Editor** → **New Query**
2. Open `supabase/schema.sql`, paste the entire file, click **Run**
3. All 11 tables, RLS policies, and indexes will be created
4. **Verify RLS is actually enforced** — see Security Hardening § RLS Verification before going further.

### Step 3 — Create Storage Buckets

| Bucket name | Public? | Purpose |
|---|---|---|
| `thumbnails` | ✅ Yes | Lecture thumbnails |
| `videos` | ❌ No | Lecture video files (served only via signed URLs, see Step 7) |
| `notes` | ❌ No | PDF notes for students |
| `payment-proofs` | ❌ No | UPI payment screenshots |
| `downloads` | ❌ No | Extra downloadable resources |

For every **non-public** bucket, also add a Storage RLS policy restricting access to `authenticated` users with `course_access = true` (see schema.sql comments for the exact policy).

### Step 4 — Connect Supabase to the App
In `supabase/client.js` (and nowhere else — don't duplicate keys across files):
```js
const SUPABASE_URL = "https://xxxxxxxxxxxx.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGci...your anon key here...";
```
Both values are in: Supabase Dashboard → **Settings** → **API**.

### Step 5 — Create Your First Admin
1. Supabase Dashboard → **Authentication** → **Users** → **Invite user**
2. Enter your email → Send invite → Set password via the email link
3. Go to **SQL Editor** and run:
```sql
INSERT INTO admins (user_id)
VALUES ('<paste-your-user-id-here>');
```
Your user ID is shown in Authentication → Users table.

### Step 6 — Configure Custom SMTP (do not skip this)
Supabase's built-in email sender has a very low rate limit (a handful of emails/hour) and frequently lands in spam. For any real student volume:

1. Sign up for a transactional email provider (Resend, Postmark, or SendGrid all work)
2. Supabase Dashboard → **Authentication** → **Settings** → **SMTP Settings** → enable custom SMTP
3. Enter your provider's SMTP host, port, username, and password
4. Send a test invite and confirm it lands in inbox, not spam (set up SPF/DKIM records with your provider for this)
5. Customize the invite + password-reset email templates under **Authentication → Email Templates** to match your brand

### Step 7 — Protected Video Delivery
`videos` is a private bucket — `lecture.html` cannot just link to a file path. It must request a short-lived signed URL.

**supabase/functions/get-signed-video-url/index.ts**
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const authHeader = req.headers.get('Authorization')!
  const { videoPath } = await req.json()

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  // Confirm the requester is logged in AND has course_access
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new Response('Unauthorized', { status: 401 })

  const { data: profile } = await supabase
    .from('users')
    .select('course_access')
    .eq('id', user.id)
    .single()

  if (!profile?.course_access) return new Response('Forbidden', { status: 403 })

  // Issue a signed URL valid for 2 hours
  const { data, error } = await supabase
    .storage
    .from('videos')
    .createSignedUrl(videoPath, 60 * 60 * 2)

  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 })

  return new Response(JSON.stringify({ url: data.signedUrl }), { status: 200 })
})
```
Deploy: `supabase functions deploy get-signed-video-url`

In `lecture.html`, call this function (passing the logged-in user's auth token) before rendering the `<video>` tag, instead of using a static file path.

---

## Auth Flow (How It Works)

```
Student visits homepage
        ↓
Clicks "Start your CAT Preparation Journey with us"
        ↓
Google Form opens (Name, Email, Phone, State + Payment Screenshot)
        ↓
Student pays via UPI QR / Razorpay on the form
        ↓
Admin logs into /admin → Pending Payments tab
        ↓
Admin clicks "Approve" on the payment
        ↓
Supabase sends a Set Password email to the student
        ↓
Student clicks the link → /pages/set-password.html
        ↓
Student sets their password
        ↓
Redirected to /pages/dashboard.html ✓
```

**Two separate paths — don't confuse them:**
- **First-time students** (just approved) never see `login.html`. They click the invite-email link and land directly on `set-password.html` → then `dashboard.html`.
- **Returning students** use `login.html` on every subsequent visit.

**Note:** The "Approve" button uses `supabase.auth.admin.inviteUserByEmail()`, which requires the **service_role** key. This must be called from a Supabase Edge Function, never the frontend.

---

## Edge Function: Approve Payment

**supabase/functions/approve-payment/index.ts**
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const { paymentId, email, fullName } = await req.json()

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // 1. Invite user (sends set-password email)
  const { data: user, error: inviteErr } = await supabase.auth.admin.inviteUserByEmail(email, {
    redirectTo: `${Deno.env.get('SITE_URL')}/pages/set-password.html`,
    data: { full_name: fullName }
  })

  if (inviteErr) return new Response(JSON.stringify({ error: inviteErr.message }), { status: 400 })

  // 2. Create user profile with course access
  await supabase.from('users').upsert({
    id: user.user.id,
    full_name: fullName,
    email,
    course_access: true,
  })

  // 3. Init student progress row
  await supabase.from('student_progress').upsert({ user_id: user.user.id })

  // 4. Mark payment approved
  await supabase.from('payments').update({ status: 'approved' }).eq('id', paymentId)

  return new Response(JSON.stringify({ success: true }), { status: 200 })
})
```

Deploy: `supabase functions deploy approve-payment`

In `admin/index.html`, the `approvePayment()` function must call this Edge Function (with the admin's auth token) rather than touching Supabase tables directly.

---

## Access Control Summary

| URL | Not logged in | Logged in, no access | Logged in + access |
|---|---|---|---|
| `/index.html` | ✅ Public | ✅ Public | ✅ Public |
| `/pages/login.html` | ✅ Show | ↩ Redirect to dashboard | ↩ Redirect to dashboard |
| `/pages/dashboard.html` | ↩ Login | ↩ Access Pending | ✅ Show |
| `/pages/lecture.html` | ↩ Login | ↩ Access Pending | ✅ Show |
| `/pages/profile.html` | ↩ Login | ↩ Access Pending | ✅ Show |
| `/admin/index.html` | ↩ Login | ❌ Blocked | ✅ Admin only |

**Critical:** this table describes intended *UI* behavior. It is not security. The actual security boundary is Supabase RLS — every row in every table must be protected at the database level, because anyone can call the Supabase API directly with devtools open, bypassing the HTML entirely. See Security Hardening below.

---

## Supabase Tables Reference

| Table | Purpose |
|---|---|
| `admins` | Maps auth users to admin role |
| `users` | Student profiles + `course_access` flag |
| `payments` | Payment submissions from enrollment form |
| `lectures` | Both live and recorded lectures |
| `lecture_progress` | Per-student per-lecture completion |
| `student_progress` | Aggregated stats per student |
| `mock_tests` | Mock test definitions |
| `mock_attempts` | Student mock attempts + scores |
| `notes` | PDF notes uploaded by admin |
| `announcements` | Admin announcements shown on dashboard |
| `notifications` | Per-user notification records |

---

## Security Hardening (required before launch)

### RLS Verification
For **every table above**, manually test with two different non-admin student accounts:
1. Student A cannot `SELECT`, `UPDATE`, or `DELETE` Student B's rows in `mock_attempts`, `lecture_progress`, `student_progress`, `notifications`, or `payments`.
2. Neither student can write to `admins`, `lectures`, `announcements`, or `mock_tests` (admin-only tables).
3. Confirm via the Supabase JS client directly in browser devtools — not just through the UI — since RLS is the real boundary, not the HTML.

### Storage Bucket Verification
1. Confirm `videos`, `notes`, `payment-proofs`, and `downloads` reject anonymous/unauthenticated requests (test with a logged-out fetch).
2. Confirm a student without `course_access = true` cannot fetch from `videos` or `notes`.

### Admin Authorization
Confirm that calling Edge Functions (`approve-payment`, etc.) with a non-admin's auth token returns `403`, not success. Don't rely on the admin UI being the only path in.

### Secrets Audit
Search the entire frontend codebase for the string `service_role` and `SECRET` before deploying — it must return zero matches outside Edge Function source.

---

## Payment Gateway (optional upgrade from manual UPI)

Manual UPI-screenshot approval works for low volume but doesn't scale and is a fraud vector (reused/faked screenshots). For production-scale enrollment, integrate Razorpay or Cashfree:
1. Student pays via embedded checkout widget on the enrollment form
2. Gateway webhook hits a new Edge Function (`verify-payment`) that confirms payment server-side
3. On verified webhook, automatically trigger the same invite flow as `approve-payment` — no manual admin click needed
4. Keep the manual approval flow as a fallback for edge cases (refunds, disputes)

---

## Deployment

This is a static HTML project. Deploy to any static host.

**Netlify (recommended)**
1. Drag-and-drop the `cat-platform/` folder to netlify.com/drop, or connect the Git repo for CI deploys
2. Done — live in 30 seconds

**Vercel**
```bash
npx vercel --prod
```

**Custom domain**
Add your domain in Netlify/Vercel settings and update Supabase:
- Authentication → URL Configuration → Site URL → your domain
- Authentication → URL Configuration → Redirect URLs → add your domain

**Staging vs Production**
Deploy staging and production as separate sites pointing at their respective Supabase projects (see Step 1). Never point a staging deploy at the production database.

---

## Monitoring & Backups

1. Supabase Dashboard → **Database → Backups** — confirm Point-in-Time Recovery or daily backups are enabled (paid plans only; free tier has no backups).
2. Supabase Dashboard → **Edge Functions → Logs** — check after every deploy that `approve-payment` and `get-signed-video-url` are returning 200s, not silently failing.
3. Set up an uptime check (e.g., UptimeRobot, free tier) pinging `index.html` and `pages/login.html`.
4. Enable Supabase's built-in **Auth → Rate Limits** to prevent invite/login abuse.

---

## Legal / Compliance

Before collecting real student payment screenshots, phone numbers, and emails:
1. Add a **Privacy Policy** page describing what data is collected and why
2. Add **Terms of Service** covering refunds, course access duration, and liability
3. Add a cookie/consent notice if using any analytics
4. Link both from the homepage footer

---

## Pre-Launch Checklist

- [ ] Schema run on production Supabase project
- [ ] All RLS policies manually tested with 2+ non-admin accounts (see Security Hardening)
- [ ] Storage buckets tested for unauthenticated/unauthorized access
- [ ] Custom SMTP configured and test email confirmed out of spam
- [ ] Signed-URL video delivery tested end-to-end
- [ ] `service_role` key confirmed absent from all frontend files
- [ ] Admin account created and confirmed working
- [ ] Custom domain connected + Supabase redirect URLs updated
- [ ] Privacy Policy + Terms of Service pages live
- [ ] Backups enabled on production Supabase project
- [ ] Staging environment fully separate from production

---

## Updating the Google Form Link

In `index.html`, find the enroll section and update:
```html
href="https://docs.google.com/forms/d/e/1FAIpQLSfk8ifpCZnmdp6JjYkG7W3EpAYPYLWWdxQcqx9T6PGZG4NVbA/viewform"
```
Replace with your actual Google Form URL.

---

## Adding Real Faculty Photos

In `index.html`, the faculty section uses initials avatars.
To add real photos, replace the `.faculty-avatar` div with:
```html
<img src="path/to/photo.jpg" alt="Faculty name" class="faculty-photo" />
```
And add CSS: `.faculty-photo { width:72px; height:72px; border-radius:var(--radius-lg); object-fit:cover; }`

---

## Support

For technical issues: info.careerchoice360@gmail.com

