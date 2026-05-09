import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { kycApi } from '../services/api';
import { useTheme } from '../theme/ThemeContext';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

type KycOtpScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'KycOtp'>;

export default function KycOtpScreen() {
  const navigation = useNavigation<KycOtpScreenNavigationProp>();
  const { colors } = useTheme();
  const [otp, setOtp] = useState('');
  const [loading, setLoading] = useState(false);

  const handleVerify = async () => {
    if (otp.length !== 6) {
      Alert.alert('Error', 'Please enter a valid 6-digit OTP');
      return;
    }

    setLoading(true);
    try {
      const response = await kycApi.verifyOtp(otp);
      if (response.data.success) {
        navigation.navigate('KycPrompt'); // Navigate back to prompt to show next tier or continue
      }
    } catch (error: any) {
      // Toast handles error display
    } finally {
      setLoading(false);
    }
  };

  const styles = createStyles(colors);

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Verify OTP</Text>
      </View>
      
      <Text style={styles.subtitle}>
        Enter the 6-digit code sent to your registered phone number or email address.
      </Text>
      
      <View style={styles.otpContainer}>
        <TextInput
          style={styles.input}
          placeholder="000000"
          value={otp}
          onChangeText={setOtp}
          keyboardType="numeric"
          maxLength={6}
          placeholderTextColor={colors.textSecondary}
          autoFocus
        />
      </View>
      
      <TouchableOpacity 
        style={[styles.buttonContainer, (otp.length !== 6 || loading) && styles.buttonDisabled]} 
        onPress={handleVerify}
        disabled={otp.length !== 6 || loading}
      >
        <LinearGradient
          colors={['#2563eb', '#3b82f6']}
          style={styles.button}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 0 }}
        >
          {loading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Verify & Continue</Text>
          )}
        </LinearGradient>
      </TouchableOpacity>
      
      <TouchableOpacity style={styles.resendButton}>
        <Text style={styles.resendText}>Didn't receive code? <Text style={styles.resendTextBold}>Resend OTP</Text></Text>
      </TouchableOpacity>
    </View>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 32,
    marginTop: 20,
  },
  backButton: {
    marginRight: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
    marginBottom: 40,
    lineHeight: 24,
  },
  otpContainer: {
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    padding: 24,
    marginBottom: 40,
    alignItems: 'center',
  },
  input: {
    fontSize: 36,
    fontWeight: 'bold',
    color: colors.text,
    letterSpacing: 12,
    width: '100%',
    textAlign: 'center',
  },
  buttonContainer: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#2563eb',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
    marginBottom: 24,
  },
  button: {
    padding: 18,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  resendButton: {
    padding: 16,
  },
  resendText: {
    color: colors.textSecondary,
    textAlign: 'center',
    fontSize: 14,
  },
  resendTextBold: {
    color: colors.primary,
    fontWeight: 'bold',
  },
});
