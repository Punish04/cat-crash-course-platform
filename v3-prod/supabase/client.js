// =============================================
// SUPABASE CLIENT
// Replace with your actual Supabase credentials
// =============================================

const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

// Initialize Supabase client
// Loaded via CDN in HTML — window.supabase is available globally
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export default supabaseClient;
