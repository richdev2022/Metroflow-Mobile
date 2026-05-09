import * as LocalAuthentication from 'expo-local-authentication';
import { storage } from './api';

export interface BiometricResult {
  success: boolean;
  error?: string;
}

export class BiometricService {
  static async hasHardware(): Promise<boolean> {
    try {
      return await LocalAuthentication.hasHardwareAsync();
    } catch (error) {
      console.error('Failed to check biometric hardware:', error);
      return false;
    }
  }

  static async isEnrolled(): Promise<boolean> {
    try {
      return await LocalAuthentication.isEnrolledAsync();
    } catch (error) {
      console.error('Failed to check biometric enrollment:', error);
      return false;
    }
  }

  static async isAvailable(): Promise<boolean> {
    try {
      const hasHardware = await this.hasHardware();
      if (!hasHardware) return false;
      
      const isEnrolled = await this.isEnrolled();
      return isEnrolled;
    } catch (error) {
      return false;
    }
  }

  static async getAvailableTypes(): Promise<LocalAuthentication.AuthenticationType[]> {
    try {
      return await LocalAuthentication.supportedAuthenticationTypesAsync();
    } catch (error) {
      console.error('Failed to get biometric types:', error);
      return [];
    }
  }

  static async authenticate(promptMessage: string = 'Authenticate to continue'): Promise<BiometricResult> {
    try {
      const isAvailable = await this.isAvailable();
      if (!isAvailable) {
        return {
          success: false,
          error: 'Biometric authentication is not available on this device',
        };
      }

      console.log('Starting biometric authentication...');
      
      const result = await LocalAuthentication.authenticateAsync({
        promptMessage,
        fallbackLabel: 'Use Passcode',
        cancelLabel: 'Cancel',
        disableDeviceFallback: false,
      });

      console.log('Biometric result:', result);

      if (result.success) {
        return { success: true };
      } else {
        return {
          success: false,
          error: result.error || 'Authentication failed',
        };
      }
    } catch (error) {
      console.error('Biometric authentication failed:', error);
      return {
        success: false,
        error: 'An error occurred during authentication',
      };
    }
  }

  static async isEnabled(): Promise<boolean> {
    try {
      const enabled = await storage.getBiometricsEnabled();
      console.log('Biometrics enabled:', enabled);
      return enabled;
    } catch (error) {
      console.error('Failed to check biometrics enabled status:', error);
      return false;
    }
  }

  static async enableBiometrics(): Promise<boolean> {
    try {
      console.log('Attempting to enable biometrics...');
      const authResult = await this.authenticate('Enable biometric login');
      
      if (authResult.success) {
        await storage.setBiometricsEnabled(true);
        console.log('Biometrics enabled successfully');
        return true;
      }
      
      console.log('Biometric authentication failed during enable');
      return false;
    } catch (error) {
      console.error('Failed to enable biometrics:', error);
      return false;
    }
  }

  static async disableBiometrics(): Promise<void> {
    try {
      await storage.setBiometricsEnabled(false);
      console.log('Biometrics disabled');
    } catch (error) {
      console.error('Failed to disable biometrics:', error);
    }
  }

  static async hasPromptBeenShown(): Promise<boolean> {
    try {
      return await storage.getBiometricsPromptShown();
    } catch (error) {
      console.error('Failed to check prompt status:', error);
      return false;
    }
  }

  static async markPromptAsShown(): Promise<void> {
    try {
      await storage.setBiometricsPromptShown(true);
    } catch (error) {
      console.error('Failed to mark prompt as shown:', error);
    }
  }

  static async resetPromptStatus(): Promise<void> {
    try {
      await storage.removeBiometricsPromptShown();
    } catch (error) {
      console.error('Failed to reset prompt status:', error);
    }
  }
}

export default BiometricService;
