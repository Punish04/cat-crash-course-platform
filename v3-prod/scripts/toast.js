// =============================================
// TOAST NOTIFICATIONS
// Usage: Toast.show('Message', 'success' | 'error' | 'info')
// =============================================

const Toast = {
  init() {
    if (!document.getElementById('toast-container')) {
      const el = document.createElement('div');
      el.id = 'toast-container';
      el.className = 'toast-container';
      document.body.appendChild(el);
    }
  },

  show(message, type = 'info', duration = 3500) {
    Toast.init();
    const container = document.getElementById('toast-container');

    const icons = {
      success: '✓',
      error:   '✕',
      info:    'ℹ',
    };

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
      <span class="toast-icon">${icons[type] || icons.info}</span>
      <span>${message}</span>
    `;

    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(20px)';
      toast.style.transition = '0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, duration);
  },

  success: (msg) => Toast.show(msg, 'success'),
  error:   (msg) => Toast.show(msg, 'error'),
  info:    (msg) => Toast.show(msg, 'info'),
};

export default Toast;
