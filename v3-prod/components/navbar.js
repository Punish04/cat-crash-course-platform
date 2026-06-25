// =============================================
// NAVBAR COMPONENT
// Injected into every public page
// =============================================

export function renderNavbar(activePage = '') {
  const navbar = document.getElementById('navbar');
  if (!navbar) return;

  navbar.innerHTML = `
    <nav class="site-nav">
      <div class="container nav-inner">

        <!-- Logo -->
        <a href="/index.html" class="nav-logo">
          <div class="logo-mark">
            <span>CAT</span>
          </div>
          <div class="logo-text">
            <span class="logo-title">CrashCourse</span>
            <span class="logo-sub">by CareerChoice360</span>
          </div>
        </a>

        <!-- Desktop links -->
        <ul class="nav-links">
          <li><a href="#course"    class="nav-link ${activePage === 'course'    ? 'active' : ''}">Course</a></li>
          <li><a href="#faculty"   class="nav-link ${activePage === 'faculty'   ? 'active' : ''}">Faculty</a></li>
          <li><a href="#features"  class="nav-link ${activePage === 'features'  ? 'active' : ''}">Features</a></li>
          <li><a href="#faq"       class="nav-link ${activePage === 'faq'       ? 'active' : ''}">FAQs</a></li>
        </ul>

        <!-- CTA -->
        <div class="nav-cta">
          <a href="/pages/login.html" class="btn btn-outline nav-login-btn">Login</a>
          <a href="#enroll" class="btn btn-primary nav-enroll-btn">Enroll Now</a>
        </div>

        <!-- Hamburger -->
        <button class="hamburger" id="hamburgerBtn" aria-label="Open menu">
          <span></span><span></span><span></span>
        </button>
      </div>

      <!-- Mobile Drawer -->
      <div class="mobile-drawer" id="mobileDrawer">
        <div class="drawer-overlay" id="drawerOverlay"></div>
        <div class="drawer-panel">
          <button class="drawer-close" id="drawerClose">
            <i data-feather="x"></i>
          </button>
          <ul class="drawer-links">
            <li><a href="#course"   class="drawer-link">Course</a></li>
            <li><a href="#faculty"  class="drawer-link">Faculty</a></li>
            <li><a href="#features" class="drawer-link">Features</a></li>
            <li><a href="#faq"      class="drawer-link">FAQs</a></li>
          </ul>
          <div class="drawer-actions">
            <a href="/pages/login.html" class="btn btn-outline" style="width:100%;justify-content:center;">Login</a>
            <a href="#enroll" class="btn btn-primary" style="width:100%;justify-content:center;">Enroll Now</a>
          </div>
        </div>
      </div>
    </nav>
  `;

  // Sticky on scroll
  window.addEventListener('scroll', () => {
    navbar.classList.toggle('scrolled', window.scrollY > 20);
  });

  // Mobile drawer
  const hamburgerBtn  = document.getElementById('hamburgerBtn');
  const mobileDrawer  = document.getElementById('mobileDrawer');
  const drawerOverlay = document.getElementById('drawerOverlay');
  const drawerClose   = document.getElementById('drawerClose');

  const openDrawer  = () => mobileDrawer.classList.add('open');
  const closeDrawer = () => mobileDrawer.classList.remove('open');

  hamburgerBtn?.addEventListener('click',  openDrawer);
  drawerClose?.addEventListener('click',   closeDrawer);
  drawerOverlay?.addEventListener('click', closeDrawer);

  // Close on drawer link click
  document.querySelectorAll('.drawer-link').forEach(link => {
    link.addEventListener('click', closeDrawer);
  });

  // Init feather icons
  if (window.feather) feather.replace();
}
