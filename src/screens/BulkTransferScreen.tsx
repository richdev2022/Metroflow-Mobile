import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator, TextInput } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { useTheme } from '../theme/ThemeContext';
import { payrollApi, transfersApi, walletApi } from '../services/api';
import { Employee, Wallet } from '../types';

export default function BulkTransferScreen() {
  const navigation = useNavigation();
  const { colors } = useTheme();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [wallets, setWallets] = useState<{ user_wallet?: Wallet; business_wallet?: Wallet }>({});
  const [selectedWallet, setSelectedWallet] = useState<'business' | 'user'>('business');
  const [transferType, setTransferType] = useState<'salary' | 'sprint' | 'task' | 'manual'>('salary');
  const [otp, setOtp] = useState('');
  const [loading, setLoading] = useState(true);
  const [showOtpModal, setShowOtpModal] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [payrollRes, walletRes] = await Promise.all([
        payrollApi.getSummary(),
        walletApi.getInfo(),
      ]);
      if (payrollRes.data.success) {
        setEmployees(payrollRes.data.payroll || []);
      }
      setWallets(walletRes.data);
    } catch (error) {
      console.error('Failed to fetch data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRequestOtp = async () => {
    const wallet = selectedWallet === 'business' ? wallets.business_wallet : wallets.user_wallet;
    if (!wallet) {
      Alert.alert('Error', 'Wallet not found');
      return;
    }
    setSubmitting(true);
    try {
      await transfersApi.requestTransferOtp(wallet.id);
      Alert.alert('Success', 'OTP sent to your email/phone');
      setShowOtpModal(true);
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to send OTP');
    } finally {
      setSubmitting(false);
    }
  };

  const handleInitiateTransfer = async () => {
    const wallet = selectedWallet === 'business' ? wallets.business_wallet : wallets.user_wallet;
    if (!wallet) {
      Alert.alert('Error', 'Wallet not found');
      return;
    }
    if (otp.length !== 6) {
      Alert.alert('Error', 'Please enter a valid 6-digit OTP');
      return;
    }
    setSubmitting(true);
    try {
      const items = employees.map(emp => ({
        amount: typeof emp.net_salary === 'string' ? parseFloat(emp.net_salary) : emp.net_salary,
        bankCode: emp.bank_code || '',
        accountNumber: emp.bank_account_number || '',
      }));

      await transfersApi.bulkTransfer({
        type: transferType,
        source_wallet_id: wallet.id,
        otp,
        data: { items },
      });

      Alert.alert(
        'Success',
        'Bulk transfer initiated successfully',
        [{ text: 'OK', onPress: () => navigation.goBack() }]
      );
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Transfer failed');
    } finally {
      setSubmitting(false);
      setShowOtpModal(false);
    }
  };

  const totalAmount = employees.reduce((sum, emp) => {
    const salary = typeof emp.net_salary === 'string' ? parseFloat(emp.net_salary) : emp.net_salary;
    return sum + (typeof salary === 'number' ? salary : 0);
  }, 0);

  const styles = createStyles(colors);

  if (loading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  const selectedWalletData = selectedWallet === 'business' ? wallets.business_wallet : wallets.user_wallet;

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView}>
        <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
          <Text style={styles.backButtonText}>← Back</Text>
        </TouchableOpacity>
        
        <Text style={styles.title}>Initiate Bulk Transfer</Text>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Select Source Wallet</Text>
          <View style={styles.walletOptions}>
            {wallets.business_wallet && (
              <TouchableOpacity 
                style={[styles.walletOption, selectedWallet === 'business' && styles.selectedWallet]}
                onPress={() => setSelectedWallet('business')}
              >
                <Text style={[styles.walletOptionText, selectedWallet === 'business' && styles.selectedWalletText]}>
                  Business Wallet ({wallets.business_wallet.currency} {wallets.business_wallet.balance.toLocaleString()})
                </Text>
              </TouchableOpacity>
            )}
            {wallets.user_wallet && (
              <TouchableOpacity 
                style={[styles.walletOption, selectedWallet === 'user' && styles.selectedWallet]}
                onPress={() => setSelectedWallet('user')}
              >
                <Text style={[styles.walletOptionText, selectedWallet === 'user' && styles.selectedWalletText]}>
                  Personal Wallet ({wallets.user_wallet.currency} {wallets.user_wallet.balance.toLocaleString()})
                </Text>
              </TouchableOpacity>
            )}
          </View>
        </View>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Transfer Type</Text>
          <View style={styles.typeOptions}>
            {(['salary', 'sprint', 'task', 'manual'] as const).map((type) => (
              <TouchableOpacity 
                key={type}
                style={[styles.typeOption, transferType === type && styles.selectedType]}
                onPress={() => setTransferType(type)}
              >
                <Text style={[styles.typeOptionText, transferType === type && styles.selectedTypeText]}>
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>
        
        <View style={styles.summaryCard}>
          <Text style={styles.summaryTitle}>Transfer Summary</Text>
          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>Number of Employees</Text>
            <Text style={styles.summaryValue}>{employees.length}</Text>
          </View>
          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>Total Amount</Text>
            <Text style={styles.summaryAmount}>₦{totalAmount.toLocaleString()}</Text>
          </View>
        </View>
        
        <TouchableOpacity 
          style={[styles.button, !selectedWalletData && styles.buttonDisabled]} 
          disabled={!selectedWalletData || submitting}
          onPress={handleRequestOtp}
        >
          {submitting ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Request OTP</Text>
          )}
        </TouchableOpacity>
      </ScrollView>

      {showOtpModal && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Enter OTP</Text>
              <TouchableOpacity onPress={() => setShowOtpModal(false)}>
                <Text style={styles.closeButton}>✕</Text>
              </TouchableOpacity>
            </View>
            <TextInput
              style={styles.otpInput}
              placeholder="Enter OTP"
              placeholderTextColor={colors.textSecondary}
              value={otp}
              onChangeText={setOtp}
              keyboardType="numeric"
              maxLength={6}
            />
            <TouchableOpacity 
              style={[styles.submitButton, submitting && styles.buttonDisabled]} 
              disabled={submitting}
              onPress={handleInitiateTransfer}
            >
              {submitting ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.submitButtonText}>Confirm Transfer</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  scrollView: {
    padding: 24,
  },
  backButton: {
    marginBottom: 24,
  },
  backButtonText: {
    color: colors.primary,
    fontSize: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 24,
    color: colors.text,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textSecondary,
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  walletOptions: {
    gap: 12,
  },
  walletOption: {
    borderWidth: 2,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 16,
    backgroundColor: colors.surface,
  },
  selectedWallet: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  walletOptionText: {
    fontSize: 16,
    color: colors.text,
  },
  selectedWalletText: {
    color: colors.primary,
    fontWeight: '600',
  },
  typeOptions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  typeOption: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderWidth: 2,
    borderColor: colors.border,
    borderRadius: 20,
    backgroundColor: colors.surface,
  },
  selectedType: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  typeOptionText: {
    fontSize: 14,
    color: colors.text,
  },
  selectedTypeText: {
    color: colors.primary,
    fontWeight: '600',
  },
  summaryCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 24,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: colors.border,
  },
  summaryTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 16,
  },
  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  summaryLabel: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  summaryValue: {
    fontSize: 16,
    color: colors.text,
    fontWeight: '600',
  },
  summaryAmount: {
    fontSize: 24,
    color: colors.primary,
    fontWeight: 'bold',
  },
  button: {
    backgroundColor: colors.primary,
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  modalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    width: '100%',
    maxWidth: 400,
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 24,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.text,
  },
  closeButton: {
    fontSize: 24,
    color: colors.text,
  },
  otpInput: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 16,
    fontSize: 24,
    textAlign: 'center',
    color: colors.text,
    marginBottom: 24,
  },
  submitButton: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
