import { Alert } from 'react-native';

class Logger {
  static log(...args: any[]) {
    if (__DEV__) {
      console.log('[LOG]', ...args);
    }
  }

  static warn(...args: any[]) {
    if (__DEV__) {
      console.warn('[WARN]', ...args);
    }
  }

  static error(message: string, error?: any, showAlert: boolean = false) {
    console.error('[ERROR]', message, error);
    
    // In production, we might want to send this to a service like Sentry or LogRocket
    // For now, we'll just alert if requested
    if (showAlert) {
      Alert.alert('System Error', `${message}\n\nPlease contact support if this persists.`);
    }
  }

  static critical(message: string, error?: any) {
    this.error(message, error, true);
  }
}

export default Logger;
