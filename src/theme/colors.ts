export const Colors = {
  primary: '#2563eb',
  primaryLight: '#3b82f6',
  primaryDark: '#1d4ed8',
  primaryBg: '#eff6ff',
  
  success: '#10b981',
  successBg: '#d1fae5',
  
  warning: '#f59e0b',
  warningBg: '#fef3c7',
  
  error: '#ef4444',
  errorBg: '#fee2e2',
};

export const LightColors = {
  ...Colors,
  background: '#f8fafc',
  surface: '#ffffff',
  surfaceVariant: '#f1f5f9',
  text: '#0f172a',
  textSecondary: '#64748b',
  border: '#e2e8f0',
  borderVariant: '#cbd5e1',
};

export const DarkColors = {
  ...Colors,
  background: '#020617',
  surface: '#0f172a',
  surfaceVariant: '#1e293b',
  text: '#f8fafc',
  textSecondary: '#94a3b8',
  border: '#1e293b',
  borderVariant: '#334155',
};

export type ThemeColors = typeof LightColors;
