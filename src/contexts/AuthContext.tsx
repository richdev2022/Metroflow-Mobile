import React, { createContext, useContext, useState, useEffect, ReactNode, useRef, useCallback } from 'react';
import { AppState, AppStateStatus, InteractionManager } from 'react-native';
import { storage, authApi, setLogoutHandler } from '../services/api';
import BiometricService from '../services/biometrics';

const IDLE_TIMEOUT = 5 * 60 * 1000; // 5 minutes in milliseconds

interface AuthContextType {
  isAuthenticated: boolean;
  isLoading: boolean;
  token: string | null;
  userId: string | null;
  businessId: string | null;
  userName: string | null;
  login: (email: string, password: string) => Promise<void>;
  register: (data: any) => Promise<{ requiresOtp: boolean; email?: string }>;
  logout: () => Promise<void>;
  verifyOtp: (email: string, otpCode: string) => Promise<void>;
  biometricsEnabled: boolean;
  enableBiometrics: () => Promise<boolean>;
  disableBiometrics: () => Promise<void>;
  loginWithBiometrics: () => Promise<boolean>;
  checkBiometricsAvailable: () => Promise<boolean>;
  hasSeenOnboarding: boolean;
  completeOnboarding: () => Promise<void>;
  resetIdleTimer: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [token, setToken] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);
  const [businessId, setBusinessId] = useState<string | null>(null);
  const [userName, setUserName] = useState<string | null>(null);
  const [biometricsEnabled, setBiometricsEnabled] = useState(false);
  const [hasSeenOnboarding, setHasSeenOnboarding] = useState(false);
  const idleTimerRef = useRef<NodeJS.Timeout | null>(null);
  const appStateRef = useRef<AppStateStatus>('active');

  const resetIdleTimer = useCallback(() => {
    if (idleTimerRef.current) {
      clearTimeout(idleTimerRef.current);
    }
    if (isAuthenticated) {
      idleTimerRef.current = setTimeout(() => {
        logout();
      }, IDLE_TIMEOUT);
    }
  }, [isAuthenticated]);

  const handleAppStateChange = useCallback((nextAppState: AppStateStatus) => {
    if (appStateRef.current === 'active' && nextAppState.match(/inactive|background/)) {
    }
    if (appStateRef.current.match(/inactive|background/) && nextAppState === 'active') {
      resetIdleTimer();
    }
    appStateRef.current = nextAppState;
  }, [resetIdleTimer]);

  useEffect(() => {
    checkAuth();
    setLogoutHandler(logout);
    
    const subscription = AppState.addEventListener('change', handleAppStateChange);
    
    return () => {
      subscription.remove();
      if (idleTimerRef.current) {
        clearTimeout(idleTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (isAuthenticated) {
      resetIdleTimer();
    } else {
      if (idleTimerRef.current) {
        clearTimeout(idleTimerRef.current);
      }
    }
  }, [isAuthenticated, resetIdleTimer]);

  const checkAuth = async () => {
    try {
      const [storedToken, storedUserId, storedBusinessId, storedUserName, storedBiometricsEnabled, storedHasSeenOnboarding] = await Promise.all([
        storage.getToken(),
        storage.getUserId(),
        storage.getBusinessId(),
        storage.getUserName(),
        BiometricService.isEnabled(),
        storage.getHasSeenOnboarding(),
      ]);

      setBiometricsEnabled(storedBiometricsEnabled);
      setHasSeenOnboarding(storedHasSeenOnboarding);

      if (storedToken) {
        setToken(storedToken);
        setUserId(storedUserId);
        setBusinessId(storedBusinessId);
        setUserName(storedUserName);
        setIsAuthenticated(true);
      }
    } catch (error) {
      console.error('Auth check failed:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const login = async (email: string, password: string) => {
    try {
      const response = await authApi.login(email, password);
      const { token: responseToken, user, business, userId: responseUserIdDirect, businessId: responseBusinessIdDirect, requiresOtp } = response.data;

      if (requiresOtp) {
        throw new Error('OTP required');
      }

      if (responseToken) {
        const responseUserId = responseUserIdDirect || user?.id;
        const responseBusinessId = responseBusinessIdDirect || business?.id;
        const responseUserName = user?.name || email;

        await Promise.all([
          storage.setToken(responseToken),
          storage.setUserId(responseUserId),
          storage.setBusinessId(responseBusinessId),
          storage.setUserName(responseUserName),
        ]);

        setToken(responseToken);
        setUserId(responseUserId);
        setBusinessId(responseBusinessId);
        setUserName(responseUserName);
        setIsAuthenticated(true);
        resetIdleTimer();
      }
    } catch (error) {
      throw error;
    }
  };

  const register = async (data: any) => {
    try {
      const response = await authApi.register(data);
      const { token: responseToken, userId: responseUserId, businessId: responseBusinessId, requiresOtp } = response.data;

      if (requiresOtp) {
        return { requiresOtp: true, email: data.adminEmail };
      }

      // If token is returned immediately (e.g. no OTP required in some flows)
      if (responseToken) {
        await Promise.all([
          storage.setToken(responseToken),
          storage.setUserId(responseUserId),
          storage.setBusinessId(responseBusinessId),
          storage.setUserName(data.adminName),
        ]);

        setToken(responseToken);
        setUserId(responseUserId);
        setBusinessId(responseBusinessId);
        setUserName(data.adminName);
        setIsAuthenticated(true);
        resetIdleTimer();
      }

      return { requiresOtp: false };
    } catch (error) {
      throw error;
    }
  };

  const verifyOtp = async (email: string, otpCode: string) => {
    try {
      const response = await authApi.verifyOtp(email, otpCode);
      const { token: responseToken, userId: responseUserId, businessId: responseBusinessId, user, businessId: bizId } = response.data;

      if (responseToken) {
        const finalUserId = responseUserId || user?.id;
        const finalBusinessId = responseBusinessId || bizId || user?.businessId;
        const finalUserName = user?.name || email;

        await Promise.all([
          storage.setToken(responseToken),
          storage.setUserId(finalUserId),
          storage.setBusinessId(finalBusinessId),
          storage.setUserName(finalUserName),
        ]);

        setToken(responseToken);
        setUserId(finalUserId);
        setBusinessId(finalBusinessId);
        setUserName(finalUserName);
        setIsAuthenticated(true);
        resetIdleTimer();
      }
    } catch (error) {
      throw error;
    }
  };

  const logout = async () => {
    try {
      if (idleTimerRef.current) {
        clearTimeout(idleTimerRef.current);
      }
      await storage.clearAll();
      setToken(null);
      setUserId(null);
      setBusinessId(null);
      setUserName(null);
      setBiometricsEnabled(false);
      setIsAuthenticated(false);
    } catch (error) {
      console.error('Logout failed:', error);
    }
  };

  const enableBiometrics = async (): Promise<boolean> => {
    try {
      const success = await BiometricService.enableBiometrics();
      if (success) {
        setBiometricsEnabled(true);
      }
      resetIdleTimer();
      return success;
    } catch (error) {
      console.error('Enable biometrics failed:', error);
      return false;
    }
  };

  const disableBiometrics = async (): Promise<void> => {
    try {
      await BiometricService.disableBiometrics();
      setBiometricsEnabled(false);
      resetIdleTimer();
    } catch (error) {
      console.error('Disable biometrics failed:', error);
    }
  };

  const loginWithBiometrics = async (): Promise<boolean> => {
    try {
      const authResult = await BiometricService.authenticate('Sign in to your account');
      if (authResult.success) {
        const [storedToken, storedUserId, storedBusinessId, storedUserName] = await Promise.all([
          storage.getToken(),
          storage.getUserId(),
          storage.getBusinessId(),
          storage.getUserName(),
        ]);

        if (storedToken) {
          setToken(storedToken);
          setUserId(storedUserId);
          setBusinessId(storedBusinessId);
          setUserName(storedUserName);
          setIsAuthenticated(true);
          resetIdleTimer();
          return true;
        }
      }
      return false;
    } catch (error) {
      console.error('Biometric login failed:', error);
      return false;
    }
  };

  const checkBiometricsAvailable = async (): Promise<boolean> => {
    return await BiometricService.isAvailable();
  };

  const completeOnboarding = async () => {
    try {
      await storage.setHasSeenOnboarding(true);
      setHasSeenOnboarding(true);
      resetIdleTimer();
    } catch (error) {
      console.error('Failed to complete onboarding:', error);
    }
  };

  return (
    <AuthContext.Provider
      value={{
        isAuthenticated,
        isLoading,
        token,
        userId,
        businessId,
        userName,
        login,
        register,
        logout,
        verifyOtp,
        biometricsEnabled,
        enableBiometrics,
        disableBiometrics,
        loginWithBiometrics,
        checkBiometricsAvailable,
        hasSeenOnboarding,
        completeOnboarding,
        resetIdleTimer,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
