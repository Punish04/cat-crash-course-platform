// =============================================
// SUPABASE CLIENT
// Replace with your actual Supabase credentials
// =============================================

const SUPABASE_URL = 'https://scswtmwcogqtcdlxdgof.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNjc3d0bXdjb2dxdGNkbHhkZ29mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzNjEyNjUsImV4cCI6MjA5NzkzNzI2NX0.2FUNHO14StPk-xTJ7igiy1CePUZG0wtMBYX7v58jDwA';

// Initialize Supabase client
// Loaded via CDN in HTML — window.supabase is available globally
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export default supabaseClient;
