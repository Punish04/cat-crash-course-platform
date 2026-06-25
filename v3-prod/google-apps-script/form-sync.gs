// ================================================================
// GOOGLE APPS SCRIPT — Form → Supabase Auto-Sync
// by CareerChoice360 / CAT CrashCourse Platform
//
// WHAT THIS DOES:
//   Every time a student submits the Google Form, this script
//   automatically inserts a row into your Supabase `payments` table.
//   The admin sees it instantly in the admin panel — no manual entry.
//
// ── HOW TO SET THIS UP (step by step) ────────────────────────────
//
//  STEP 1: Open your Google Form
//  STEP 2: Click the 3-dot menu (top right) → "Script editor"
//          OR go to: Extensions → Apps Script
//  STEP 3: Delete everything in the editor and paste this entire file
//  STEP 4: Fill in YOUR values in the CONFIG section below
//  STEP 5: Click "Save" (floppy disk icon)
//  STEP 6: Set up the trigger:
//            → Click "Triggers" (clock icon, left sidebar)
//            → "+ Add Trigger" (bottom right)
//            → Choose function: onFormSubmit
//            → Event source: From form
//            → Event type: On form submit
//            → Click Save
//  STEP 7: Google will ask for permissions — click "Allow"
//  STEP 8: Test by submitting your form once — check Supabase
//          Dashboard → Table Editor → payments table for the new row
//
// ── GOOGLE FORM FIELD NAMES ──────────────────────────────────────
//   The field names below MUST match your Google Form question titles
//   EXACTLY (case-sensitive). Update them in CONFIG if yours differ.
// ================================================================


// ── CONFIG — FILL THESE IN ──────────────────────────────────────
const CONFIG = {

  // Your Supabase project URL
  // Found at: Supabase Dashboard → Settings → API → Project URL
  SUPABASE_URL: 'YOUR_SUPABASE_URL',

  // Your Supabase anon/public key (safe to use here — server-side script)
  // Found at: Supabase Dashboard → Settings → API → anon public
  SUPABASE_ANON_KEY: 'YOUR_SUPABASE_ANON_KEY',

  // ── Google Form field names ──────────────────────────────────
  // These must match your Google Form question titles EXACTLY.
  // To find them: open your form → click each question → copy the title text.

  FIELD_FULL_NAME:  'Full Name',          // e.g. "Full Name" or "Your Name"
  FIELD_EMAIL:      'Email Address',      // e.g. "Email Address" or "Email"
  FIELD_PHONE:      'Phone Number',       // e.g. "Phone Number" or "Mobile"
  FIELD_STATE:      'State',              // e.g. "State" or "Which state are you from?"

  // The payment screenshot upload field title in your form
  // If you're not collecting screenshot via form, set this to null
  FIELD_SCREENSHOT: 'Payment Screenshot', // or null if not in form

};
// ────────────────────────────────────────────────────────────────


/**
 * This function runs automatically every time a student submits the form.
 * Google triggers it via the "On form submit" trigger you set up.
 */
function onFormSubmit(e) {
  try {
    // Extract form responses
    const responses  = e.response.getItemResponses();
    const formData   = {};

    responses.forEach(function(itemResponse) {
      const question = itemResponse.getItem().getTitle();
      const answer   = itemResponse.getResponse();
      formData[question] = answer;
    });

    // Map form fields to payment record
    const fullName      = formData[CONFIG.FIELD_FULL_NAME]  || '';
    const email         = formData[CONFIG.FIELD_EMAIL]       || '';
    const phone         = formData[CONFIG.FIELD_PHONE]       || '';
    const state         = formData[CONFIG.FIELD_STATE]       || '';
    const screenshotUrl = CONFIG.FIELD_SCREENSHOT
                          ? (formData[CONFIG.FIELD_SCREENSHOT] || null)
                          : null;

    // Validate required fields
    if (!email || !fullName) {
      Logger.log('ERROR: Missing required fields. Email: ' + email + ', Name: ' + fullName);
      return;
    }

    // Build the payment record to insert into Supabase
    const paymentRecord = {
      full_name:      fullName,
      email:          email.toLowerCase().trim(),
      phone:          phone || null,
      state:          state || null,
      screenshot_url: screenshotUrl,
      status:         'pending'
      // created_at is auto-set by Supabase (DEFAULT NOW())
    };

    // Insert into Supabase payments table
    const result = insertToSupabase('payments', paymentRecord);

    if (result.success) {
      Logger.log('SUCCESS: Payment record created for ' + email);
      // Optional: send yourself a notification email
      sendAdminNotification(fullName, email, phone);
    } else {
      Logger.log('ERROR inserting to Supabase: ' + JSON.stringify(result.error));
    }

  } catch (err) {
    Logger.log('EXCEPTION in onFormSubmit: ' + err.toString());
  }
}


/**
 * Inserts a record into a Supabase table via the REST API.
 */
function insertToSupabase(table, record) {
  const url = CONFIG.SUPABASE_URL + '/rest/v1/' + table;

  const options = {
    method:      'POST',
    contentType: 'application/json',
    headers: {
      'apikey':        CONFIG.SUPABASE_ANON_KEY,
      'Authorization': 'Bearer ' + CONFIG.SUPABASE_ANON_KEY,
      'Content-Type':  'application/json',
      'Prefer':        'return=minimal'
    },
    payload:          JSON.stringify(record),
    muteHttpExceptions: true
  };

  try {
    const response    = UrlFetchApp.fetch(url, options);
    const statusCode  = response.getResponseCode();

    if (statusCode === 201 || statusCode === 200) {
      return { success: true };
    } else {
      return {
        success: false,
        error:   { status: statusCode, body: response.getContentText() }
      };
    }
  } catch (err) {
    return { success: false, error: err.toString() };
  }
}


/**
 * Optional: Sends an email to the admin when a new payment is submitted.
 * Remove this function (and its call above) if you don't want email alerts.
 *
 * To enable: replace ADMIN_EMAIL below with your actual email address.
 */
function sendAdminNotification(fullName, email, phone) {
  const ADMIN_EMAIL = 'info.careerchoice360@gmail.com'; // ← your email

  const subject = '📥 New Enrollment — ' + fullName + ' | CAT CrashCourse';
  const body    = [
    'A new student has submitted the enrollment form.',
    '',
    'Name:  ' + fullName,
    'Email: ' + email,
    'Phone: ' + (phone || 'Not provided'),
    '',
    'Log in to the admin panel to review and approve their payment:',
    'https://yoursite.com/admin/',     // ← update with your actual admin URL
    '',
    '— CAT CrashCourse Platform'
  ].join('\n');

  try {
    MailApp.sendEmail(ADMIN_EMAIL, subject, body);
    Logger.log('Admin notification email sent to ' + ADMIN_EMAIL);
  } catch (err) {
    Logger.log('Failed to send admin email: ' + err.toString());
  }
}


// ================================================================
// TESTING — Run this manually to verify the connection works
// before waiting for a real form submission.
//
// HOW TO TEST:
//   1. In the Apps Script editor, select "testConnection" from the
//      function dropdown at the top
//   2. Click the "Run" button (▶)
//   3. Click "Execution log" to see the result
//   4. If you see "Connection test PASSED" — you're good to go
//   5. Check Supabase → Table Editor → payments for the test row
//      (delete it after confirming it works)
// ================================================================
function testConnection() {
  const testRecord = {
    full_name:      'TEST STUDENT — DELETE ME',
    email:          'test-delete-me@example.com',
    phone:          '9999999999',
    state:          'Delhi',
    screenshot_url: null,
    status:         'pending'
  };

  Logger.log('Testing Supabase connection...');
  const result = insertToSupabase('payments', testRecord);

  if (result.success) {
    Logger.log('✓ Connection test PASSED — test row inserted into payments table.');
    Logger.log('  → Go to Supabase Dashboard → Table Editor → payments and DELETE the test row.');
  } else {
    Logger.log('✗ Connection test FAILED:');
    Logger.log(JSON.stringify(result.error));
    Logger.log('  → Check your SUPABASE_URL and SUPABASE_ANON_KEY in the CONFIG section.');
  }
}
