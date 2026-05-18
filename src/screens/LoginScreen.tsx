import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator, Modal, ScrollView, KeyboardAvoidingView, Platform } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { useAuth } from '../contexts/AuthContext';
import { useTheme } from '../theme/ThemeContext';
import Ionicons from '@expo/vector-icons/Ionicons';
import BiometricService from '../services/biometrics';
import { LinearGradient } from 'expo-linear-gradient';
import { kycApi } from '../services/api';
import Logger from '../utils/logger';

type LoginScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Login'>;

export default function LoginScreen() {
  const navigation = useNavigation<LoginScreenNavigationProp>();
  const { login, biometricsEnabled, loginWithBiometrics, enableBiometrics, userName } = useAuth();
  const { colors } = useTheme();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [biometricLoading, setBiometricLoading] = useState(false);
  const [showBiometricSetupModal, setShowBiometricSetupModal] = useState(false);
  const [biometricsAvailable, setBiometricsAvailable] = useState(false);

  useEffect(() => {
    checkBiometricAvailability();
    if (userName) {
      setEmail(userName);
    }
  }, [userName]);

  const checkBiometricAvailability = async () => {
    const available = await BiometricService.isAvailable();
    setBiometricsAvailable(available);
  };

  const checkKycAndNavigate = async () => {
    try {
      Logger.log('Checking KYC status...');
      const kycRes = await kycApi.getStatus();
      
      if (!kycRes || !kycRes.data || !kycRes.data.user) {
        Logger.warn('Invalid KYC response structure', kycRes);
        // Navigate to Main if response is invalid to avoid crash
        navigation.reset({
          index: 0,
          routes: [{ name: 'Main' }],
        });
        return;
      }

      const { user } = kycRes.data;
      
      // Tier 1 is verified if either BVN or NIN is verified
      const isTier1Verified = user.bvnStatus === 'verified' || user.ninStatus === 'verified';
      
      if (!isTier1Verified) {
        Logger.log('User not Tier 1 verified, navigating to KycPrompt');
        navigation.reset({
          index: 0,
          routes: [{ name: 'KycPrompt' }],
        });
      } else {
        Logger.log('User verified, checking biometrics...');
        const promptShown = await BiometricService.hasPromptBeenShown();
        const isEnabled = await BiometricService.isEnabled();
        const hasBiometrics = await BiometricService.isAvailable();
        
        if (hasBiometrics && !promptShown && !isEnabled) {
          setShowBiometricSetupModal(true);
        } else {
          navigation.reset({
            index: 0,
            routes: [{ name: 'Main' }],
          });
        }
      }
    } catch (error) {
      Logger.error('Failed to check KYC status:', error);
      // If KYC check fails, default to main to avoid locking user out
      navigation.reset({
        index: 0,
        routes: [{ name: 'Main' }],
      });
    }
  };

  const handleLogin = async () => {
    if (!email || !password) {
      Alert.alert('Error', 'Please enter email and password');
      return;
    }

    setLoading(true);
    try {
      Logger.log('Attempting login for:', email);
      await login(email, password);
      Logger.log('Login successful, proceeding to KYC check');
      await checkKycAndNavigate();
    } catch (error: any) {
      Logger.error('Login handle error:', error);
      if (error.message === 'OTP required') {
        navigation.navigate('VerifyOtp', { email });
      } else {
        const errorMsg = error.response?.data?.message || error.message || 'Login failed';
        Alert.alert('Login Error', errorMsg);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleBiometricLogin = async () => {
    setBiometricLoading(true);
    try {
      const success = await loginWithBiometrics();
      if (success) {
        await checkKycAndNavigate();
      } else {
        Alert.alert('Error', 'Biometric authentication failed');
      }
    } catch (error) {
      Alert.alert('Error', 'An error occurred during biometric authentication');
    } finally {
      setBiometricLoading(false);
    }
  };

  const handleSetupBiometrics = async () => {
    setBiometricLoading(true);
    try {
      const success = await enableBiometrics();
      if (success) {
        await BiometricService.markPromptAsShown();
        setShowBiometricSetupModal(false);
        Alert.alert('Success', 'Biometric login enabled successfully!');
        navigation.reset({
          index: 0,
          routes: [{ name: 'Main' }],
        });
      } else {
        Alert.alert('Error', 'Failed to enable biometric login');
      }
    } catch (error) {
      Alert.alert('Error', 'An error occurred');
    } finally {
      setBiometricLoading(false);
    }
  };

  const handleSkipBiometrics = async () => {
    await BiometricService.markPromptAsShown();
    setShowBiometricSetupModal(false);
    navigation.reset({
      index: 0,
      routes: [{ name: 'Main' }],
    });
  };

  const styles = createStyles(colors);

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <ScrollView style={styles.scrollContainer} showsVerticalScrollIndicator={false}>
        <View style={styles.header}>
          <View style={styles.authIconContainer}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.authIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="log-in-outline" size={48} color="#fff" />
            </LinearGradient>
          </View>
          <Text style={styles.title}>Metroflow</Text>
          <Text style={styles.subtitle}>Welcome back! Please sign in to continue</Text>
        </View>
        
        <View style={styles.formContainer}>
          <View style={styles.inputContainer}>
            <Ionicons name="mail-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
            <TextInput
              style={styles.input}
              placeholder="Email"
              value={email}
              onChangeText={setEmail}
              keyboardType="email-address"
              autoCapitalize="none"
              placeholderTextColor={colors.textSecondary}
            />
          </View>
          
          <View style={styles.inputContainer}>
            <Ionicons name="lock-closed-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
            <TextInput
              style={styles.input}
              placeholder="Password"
              value={password}
              onChangeText={setPassword}
              secureTextEntry={!showPassword}
              placeholderTextColor={colors.textSecondary}
            />
            <TouchableOpacity
              style={styles.eyeIcon}
              onPress={() => setShowPassword(!showPassword)}
            >
              <Ionicons
                name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                size={20}
                color={colors.textSecondary}
              />
            </TouchableOpacity>
          </View>
          
          <TouchableOpacity style={styles.forgotButton} onPress={() => navigation.navigate('ForgotPassword')}>
            <Text style={styles.forgotText}>Forgot Password?</Text>
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={styles.buttonContainer}
            onPress={handleLogin}
            disabled={loading}
            activeOpacity={0.9}
          >
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.button}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              {loading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.buttonText}>Sign In</Text>
              )}
            </LinearGradient>
          </TouchableOpacity>

          {biometricsAvailable && (
            <TouchableOpacity 
              style={[
                styles.biometricButton,
                !biometricsEnabled && { borderColor: colors.border, opacity: 0.8 }
              ]} 
              onPress={biometricsEnabled ? handleBiometricLogin : () => Alert.alert('Enable Biometrics', 'Please sign in with your password first, then enable biometric login in Settings.')}
              disabled={biometricLoading}
              activeOpacity={0.7}
            >
              {biometricLoading ? (
                <ActivityIndicator color={colors.primary} />
              ) : (
                <>
                  <Ionicons 
                    name="finger-print-outline" 
                    size={24} 
                    color={biometricsEnabled ? colors.primary : colors.textSecondary} 
                    style={{ marginRight: 8 }} 
                  />
                  <Text style={[
                    styles.biometricButtonText,
                    !biometricsEnabled && { color: colors.textSecondary }
                  ]}>
                    {biometricsEnabled ? 'Sign in with Biometrics' : 'Biometrics not enabled'}
                  </Text>
                </>
              )}
            </TouchableOpacity>
          )}
          
          <View style={styles.signupContainer}>
            <Text style={styles.signupText}>Don't have an account? </Text>
            <TouchableOpacity onPress={() => navigation.navigate('Register')}>
              <Text style={styles.signupLink}>Sign Up</Text>
            </TouchableOpacity>
          </View>
        </View>
      </ScrollView>
      </KeyboardAvoidingView>

      <Modal
        visible={showBiometricSetupModal}
        transparent
        animationType="fade"
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Ionicons name="finger-print" size={56} color={colors.primary} />
              <Text style={styles.modalTitle}>Enable Biometric Login</Text>
              <Text style={styles.modalSubtitle}>
                Would you like to enable biometric login for faster access to your account?
              </Text>
            </View>

            <TouchableOpacity 
              style={styles.modalButtonContainer}
              onPress={handleSetupBiometrics}
              disabled={biometricLoading}
              activeOpacity={0.9}
            >
              <LinearGradient
                colors={[colors.primary, colors.primaryLight]}
                style={styles.modalButtonPrimary}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 1 }}
              >
                {biometricLoading ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.modalButtonPrimaryText}>Enable Biometrics</Text>
                )}
              </LinearGradient>
            </TouchableOpacity>

            <TouchableOpacity style={styles.modalButtonSecondary} onPress={handleSkipBiometrics}>
              <Text style={styles.modalButtonSecondaryText}>Skip for Now</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContainer: {
    flex: 1,
  },
  header: {
    alignItems: 'center',
    paddingTop: 40,
    paddingBottom: 32,
  },
  authIconContainer: {
    width: 100,
    height: 100,
    borderRadius: 28,
    marginBottom: 24,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 12,
    overflow: 'hidden',
  },
  authIconGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    marginBottom: 8,
    color: colors.primary,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
    textAlign: 'center',
    paddingHorizontal: 40,
    lineHeight: 22,
  },
  formContainer: {
    paddingHorizontal: 24,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    paddingHorizontal: 16,
    marginBottom: 16,
  },
  inputIcon: {
    marginRight: 12,
  },
  input: {
    flex: 1,
    paddingVertical: 16,
    fontSize: 16,
    color: colors.text,
  },
  eyeIcon: {
    padding: 4,
    marginLeft: 8,
  },
  forgotButton: {
    alignSelf: 'flex-end',
    marginBottom: 24,
  },
  forgotText: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '500',
  },
  buttonContainer: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.25,
    shadowRadius: 16,
    elevation: 8,
    marginBottom: 24,
  },
  button: {
    padding: 18,
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  biometricButton: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderWidth: 2,
    borderColor: colors.primary,
    padding: 16,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 24,
  },
  biometricButtonText: {
    color: colors.primary,
    fontSize: 16,
    fontWeight: '600',
  },
  signupContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 8,
  },
  signupText: {
    color: colors.textSecondary,
    fontSize: 15,
  },
  signupLink: {
    color: colors.primary,
    fontSize: 15,
    fontWeight: '600',
  },
  modalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    width: '100%',
    maxWidth: 360,
    backgroundColor: colors.surface,
    borderRadius: 24,
    padding: 32,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.25,
    shadowRadius: 20,
    elevation: 16,
  },
  modalHeader: {
    alignItems: 'center',
    marginBottom: 32,
  },
  modalTitle: {
    fontSize: 22,
    fontWeight: 'bold',
    color: colors.text,
    marginTop: 20,
    marginBottom: 8,
  },
  modalSubtitle: {
    fontSize: 15,
    color: colors.textSecondary,
    textAlign: 'center',
    lineHeight: 22,
  },
  modalButtonContainer: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 12,
    elevation: 8,
    marginBottom: 12,
  },
  modalButtonPrimary: {
    width: '100%',
    padding: 16,
    alignItems: 'center',
  },
  modalButtonPrimaryText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  modalButtonSecondary: {
    width: '100%',
    padding: 16,
    borderRadius: 16,
    alignItems: 'center',
  },
  modalButtonSecondaryText: {
    color: colors.textSecondary,
    fontSize: 16,
    fontWeight: '500',
  },
});
