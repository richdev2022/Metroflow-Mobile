import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { storage, authApi } from '../services/api';
import BiometricService from '../services/biometrics';

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

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const [storedToken, storedUserId, storedBusinessId, storedUserName, storedBiometricsEnabled] = await Promise.all([
        storage.getToken(),
        storage.getUserId(),
        storage.getBusinessId(),
        storage.getUserName(),
        BiometricService.isEnabled(),
      ]);

      setBiometricsEnabled(storedBiometricsEnabled);

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
      const { token: responseToken, userId: responseUserId, businessId: responseBusinessId, requiresOtp } = response.data;

      if (requiresOtp) {
        throw new Error('OTP required');
      }

      if (responseToken) {
        await Promise.all([
          storage.setToken(responseToken),
          storage.setUserId(responseUserId),
          storage.setBusinessId(responseBusinessId),
          storage.setUserName(email),
        ]);

        setToken(responseToken);
        setUserId(responseUserId);
        setBusinessId(responseBusinessId);
        setUserName(email);
        setIsAuthenticated(true);
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
      }

      return { requiresOtp: false };
    } catch (error) {
      throw error;
    }
  };

  const verifyOtp = async (email: string, otpCode: string) => {
    try {
      const response = await authApi.verifyOtp(email, otpCode);
      const { token: responseToken, userId: responseUserId, businessId: responseBusinessId } = response.data;

      if (responseToken) {
        await Promise.all([
          storage.setToken(responseToken),
          storage.setUserId(responseUserId),
          storage.setBusinessId(responseBusinessId),
          storage.setUserName(email),
        ]);

        setToken(responseToken);
        setUserId(responseUserId);
        setBusinessId(responseBusinessId);
        setUserName(email);
        setIsAuthenticated(true);
      }
    } catch (error) {
      throw error;
    }
  };

  const logout = async () => {
    try {
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
