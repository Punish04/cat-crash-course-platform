// =============================================
// AUTH SERVICE
// All authentication logic lives here.
// Components never call Supabase directly.
// =============================================

import supabaseClient from '../supabase/client.js';

const AuthService = {

  // Login with email + password
  async login(email, password) {
    const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  },

  // Logout
  async logout() {
    const { error } = await supabaseClient.auth.signOut();
    if (error) throw error;
  },

  // Send password reset / set-password email
  async sendPasswordResetEmail(email) {
    const { error } = await supabaseClient.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/pages/set-password.html`,
    });
    if (error) throw error;
  },

  // Get current logged-in user
  async getCurrentUser() {
    const { data: { user } } = await supabaseClient.auth.getUser();
    return user;
  },

  // Get current session
  async getSession() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    return session;
  },

  // Fetch user profile from users table
  async getUserProfile(userId) {
    const { data, error } = await supabaseClient
      .from('users')
      .select('*')
      .eq('id', userId)
      .single();
    if (error) throw error;
    return data;
  },

  // Check if user has course access
  async hasCourseAccess(userId) {
    const profile = await AuthService.getUserProfile(userId);
    return profile?.course_access === true;
  },

  // Auth state change listener
  onAuthStateChange(callback) {
    return supabaseClient.auth.onAuthStateChange(callback);
  },

  // Check if current user is admin
  async isAdmin(userId) {
    const { data, error } = await supabaseClient
      .from('admins')
      .select('id')
      .eq('user_id', userId)
      .single();
    return !error && !!data;
  },

  // Route guard — redirect if not logged in
  async requireAuth(redirectTo = '/pages/login.html') {
    const user = await AuthService.getCurrentUser();
    if (!user) {
      window.location.href = redirectTo;
      return null;
    }
    return user;
  },

  // Route guard — redirect if no course access
  async requireCourseAccess(userId) {
    const access = await AuthService.hasCourseAccess(userId);
    if (!access) {
      window.location.href = '/pages/access-pending.html';
      return false;
    }
    return true;
  },
};

export default AuthService;
