import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator, TextInput, Modal, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { useTheme } from '../theme/ThemeContext';
import { payrollApi, transfersApi, walletApi, epicsApi } from '../services/api';
import { Employee, Wallet, Epic } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';

type TransferType = 'salary' | 'epic';
type TransferMode = 'single' | 'bulk';

interface Recipient {
  id: string;
  recipient_account: string;
  recipient_bank: string;
  recipient_name: string;
  amount: string;
  remark: string;
  source_type: string;
  source_id: string;
}

export default function BulkTransferScreen() {
  const navigation = useNavigation();
  const { colors } = useTheme();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [epics, setEpics] = useState<Epic[]>([]);
  const [wallets, setWallets] = useState<{ user_wallet?: Wallet; business_wallet?: Wallet }>({});
  const [selectedWallet, setSelectedWallet] = useState<'business' | 'user'>('business');
  const [transferType, setTransferType] = useState<TransferType>('salary');
  const [transferMode, setTransferMode] = useState<TransferMode>('bulk');
  const [selectedEpic, setSelectedEpic] = useState<Epic | null>(null);
  const [showEpicPicker, setShowEpicPicker] = useState(false);
  const [showBankPicker, setShowBankPicker] = useState(false);
  const [banks, setBanks] = useState<{ code: string; name: string }[]>([]);
  const [recipients, setRecipients] = useState<Recipient[]>([]);
  const [otp, setOtp] = useState('');
  const [loading, setLoading] = useState(true);
  const [showOtpModal, setShowOtpModal] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const styles = createStyles(colors);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [payrollRes, walletRes, epicsRes, banksRes] = await Promise.all([
        payrollApi.getSummary(),
        walletApi.getInfo(),
        epicsApi.getEpics(),
        transfersApi.getBanks(),
      ]);
      
      if (payrollRes.data.success) {
        setEmployees(payrollRes.data.payroll || []);
      }
      setWallets(walletRes.data);
      setEpics(epicsRes.data || []);
      if (banksRes.data.success) {
        setBanks(banksRes.data.data || []);
      }
    } catch (error) {
      console.error('Failed to fetch data:', error);
    } finally {
      setLoading(false);
    }
  };

  const addRecipient = () => {
    const newRecipient: Recipient = {
      id: Date.now().toString(),
      recipient_account: '',
      recipient_bank: '',
      recipient_name: '',
      amount: '',
      remark: selectedEpic ? (selectedEpic.name.length > 30 ? selectedEpic.name.substring(0, 27) + '...' : selectedEpic.name) : '',
      source_type: transferType === 'epic' ? 'epic' : '',
      source_id: selectedEpic?.id || '',
    };
    setRecipients([...recipients, newRecipient]);
  };

  const removeRecipient = (id: string) => {
    setRecipients(recipients.filter(r => r.id !== id));
  };

  const updateRecipient = (id: string, field: keyof Recipient, value: string) => {
    setRecipients(recipients.map(r => 
      r.id === id ? { ...r, [field]: value } : r
    ));
  };

  const resolveAccountName = async (recipientId: string) => {
    const recipient = recipients.find(r => r.id === recipientId);
    if (!recipient || !recipient.recipient_bank || !recipient.recipient_account) {
      Alert.alert('Error', 'Please select a bank and enter account number first');
      return;
    }

    try {
      const response = await transfersApi.resolveAccount(recipient.recipient_bank, recipient.recipient_account);
      if (response.data.success) {
        updateRecipient(recipientId, 'recipient_name', response.data.data.account_name);
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to resolve account');
    }
  };

  const handleRequestOtp = async () => {
    const wallet = selectedWallet === 'business' ? wallets.business_wallet : wallets.user_wallet;
    if (!wallet) {
      Alert.alert('Error', 'Wallet not found');
      return;
    }

    if (transferType === 'epic' && !selectedEpic) {
      Alert.alert('Error', 'Please select an Epic');
      return;
    }

    if (transferType === 'epic') {
      const hasEmptyFields = recipients.some(r => 
        !r.recipient_account || !r.recipient_bank || !r.amount
      );
      if (hasEmptyFields) {
        Alert.alert('Error', 'Please fill in all recipient details');
        return;
      }
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
      if (transferType === 'salary') {
        const salaryTransfers = employees.map(emp => ({
          recipient_account: emp.bank_account_number || '',
          recipient_bank: emp.bank_code || '',
          recipient_name: emp.name || '',
          amount: typeof emp.netSalary === 'number' ? emp.netSalary : 0,
          remark: 'Salary Payment',
          source_type: 'salary',
          source_id: '',
        }));

        await transfersApi.bulkTransfer({ transfers: salaryTransfers });
      } else {
        const epicTransfers = recipients.map(r => ({
          ...r,
          amount: parseFloat(r.amount),
          source_type: 'epic',
          source_id: selectedEpic?.id || '',
        }));

        await transfersApi.bulkTransfer({ transfers: epicTransfers });
      }

      Alert.alert(
        'Success',
        'Transfer initiated successfully',
        [{ text: 'OK', onPress: () => navigation.goBack() }]
      );
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Transfer failed');
    } finally {
      setSubmitting(false);
      setShowOtpModal(false);
    }
  };

  const totalAmount = transferType === 'salary' 
    ? employees.reduce((sum, emp) => sum + (typeof emp.netSalary === 'number' ? emp.netSalary : 0), 0)
    : recipients.reduce((sum, r) => sum + (parseFloat(r.amount) || 0), 0);

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
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        
        <Text style={styles.title}>Initiate Transfer</Text>
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Transfer Type</Text>
          <View style={styles.typeOptions}>
            {(['salary', 'epic'] as TransferType[]).map((type) => (
              <TouchableOpacity 
                key={type}
                style={[styles.typeOption, transferType === type && styles.selectedType]}
                onPress={() => {
                  setTransferType(type);
                  setTransferMode('bulk');
                  setRecipients([]);
                  setSelectedEpic(null);
                }}
              >
                <Ionicons 
                  name={type === 'salary' ? 'cash-outline' : 'folder-outline'} 
                  size={20} 
                  color={transferType === type ? '#fff' : colors.primary} 
                />
                <Text style={[styles.typeOptionText, transferType === type && styles.selectedTypeText]}>
                  {type.charAt(0).toUpperCase() + type.slice(1)}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {transferType === 'epic' && (
          <>
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Transfer Mode</Text>
              <View style={styles.typeOptions}>
                {(['single', 'bulk'] as TransferMode[]).map((mode) => (
                  <TouchableOpacity 
                    key={mode}
                    style={[styles.typeOption, transferMode === mode && styles.selectedType]}
                    onPress={() => {
                      setTransferMode(mode);
                      setRecipients([]);
                      if (mode === 'single') {
                        addRecipient();
                      }
                    }}
                  >
                    <Ionicons 
                      name={mode === 'single' ? 'person-outline' : 'people-outline'} 
                      size={20} 
                      color={transferMode === mode ? '#fff' : colors.primary} 
                    />
                    <Text style={[styles.typeOptionText, transferMode === mode && styles.selectedTypeText]}>
                      {mode.charAt(0).toUpperCase() + mode.slice(1)}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Select Epic</Text>
              <TouchableOpacity 
                style={styles.epicSelectButton}
                onPress={() => setShowEpicPicker(true)}
              >
                <Text style={[
                  styles.epicSelectText,
                  !selectedEpic && styles.epicSelectPlaceholder
                ]}>
                  {selectedEpic ? selectedEpic.name : 'Select an Epic'}
                </Text>
                <Ionicons name="chevron-down" size={20} color={colors.textSecondary} />
              </TouchableOpacity>
            </View>
          </>
        )}
        
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Source Wallet</Text>
          <View style={styles.walletOptions}>
            {wallets.business_wallet && (
              <TouchableOpacity 
                style={[styles.walletOption, selectedWallet === 'business' && styles.selectedWallet]}
                onPress={() => setSelectedWallet('business')}
              >
                <Text style={[styles.walletOptionText, selectedWallet === 'business' && styles.selectedWalletText]}>
                  Business Wallet ({wallets.business_wallet.currency} {parseFloat(wallets.business_wallet.balance).toLocaleString()})
                </Text>
              </TouchableOpacity>
            )}
            {wallets.user_wallet && (
              <TouchableOpacity 
                style={[styles.walletOption, selectedWallet === 'user' && styles.selectedWallet]}
                onPress={() => setSelectedWallet('user')}
              >
                <Text style={[styles.walletOptionText, selectedWallet === 'user' && styles.selectedWalletText]}>
                  Personal Wallet ({wallets.user_wallet.currency} {parseFloat(wallets.user_wallet.balance).toLocaleString()})
                </Text>
              </TouchableOpacity>
            )}
          </View>
        </View>

        {transferType === 'salary' && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Employees ({employees.length})</Text>
            {employees.map((employee, index) => (
              <View key={employee.id} style={styles.employeeItem}>
                <View style={styles.employeeInfo}>
                  <Text style={styles.employeeName}>{employee.name}</Text>
                  <Text style={styles.employeeEmail}>{employee.email}</Text>
                </View>
                <Text style={styles.employeeAmount}>
                  ₦{(typeof employee.netSalary === 'number' ? employee.netSalary : 0).toLocaleString()}
                </Text>
              </View>
            ))}
          </View>
        )}

        {transferType === 'epic' && (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>
                Recipients {transferMode === 'bulk' ? `(${recipients.length})` : ''}
              </Text>
              {transferMode === 'bulk' && (
                <TouchableOpacity style={styles.addButton} onPress={addRecipient}>
                  <Ionicons name="add" size={20} color={colors.primary} />
                </TouchableOpacity>
              )}
            </View>
            
            {recipients.map((recipient, index) => (
              <View key={recipient.id} style={styles.recipientCard}>
                <View style={styles.recipientHeader}>
                  <Text style={styles.recipientNumber}>Recipient {index + 1}</Text>
                  {transferMode === 'bulk' && (
                    <TouchableOpacity onPress={() => removeRecipient(recipient.id)}>
                      <Ionicons name="trash-outline" size={20} color={colors.error} />
                    </TouchableOpacity>
                  )}
                </View>

                <View style={styles.field}>
                  <Text style={styles.label}>Bank</Text>
                  <TouchableOpacity 
                    style={styles.bankSelectButton}
                    onPress={() => setShowBankPicker(true)}
                  >
                    <Text style={[
                      styles.bankSelectText,
                      !recipient.recipient_bank && styles.bankSelectPlaceholder
                    ]}>
                      {banks.find(b => b.code === recipient.recipient_bank)?.name || 'Select a bank'}
                    </Text>
                    <Ionicons name="chevron-down" size={20} color={colors.textSecondary} />
                  </TouchableOpacity>
                </View>

                <View style={styles.field}>
                  <Text style={styles.label}>Account Number</Text>
                  <View style={styles.accountInputContainer}>
                    <TextInput
                      style={styles.input}
                      placeholder="Enter account number"
                      placeholderTextColor={colors.textSecondary}
                      value={recipient.recipient_account}
                      onChangeText={(text) => updateRecipient(recipient.id, 'recipient_account', text)}
                      keyboardType="numeric"
                    />
                    <TouchableOpacity 
                      style={styles.verifyButton}
                      onPress={() => resolveAccountName(recipient.id)}
                    >
                      <Text style={styles.verifyButtonText}>Verify</Text>
                    </TouchableOpacity>
                  </View>
                </View>

                {recipient.recipient_name ? (
                  <View style={styles.accountNameContainer}>
                    <Ionicons name="checkmark-circle" size={20} color="#4CAF50" />
                    <Text style={styles.accountName}>{recipient.recipient_name}</Text>
                  </View>
                ) : null}

                <View style={styles.field}>
                  <Text style={styles.label}>Amount</Text>
                  <TextInput
                    style={styles.input}
                    placeholder="Enter amount"
                    placeholderTextColor={colors.textSecondary}
                    value={recipient.amount}
                    onChangeText={(text) => updateRecipient(recipient.id, 'amount', text)}
                    keyboardType="numeric"
                  />
                </View>
              </View>
            ))}
          </View>
        )}
        
        <View style={styles.summaryCard}>
          <Text style={styles.summaryTitle}>Transfer Summary</Text>
          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>
              {transferType === 'salary' ? 'Number of Employees' : 'Number of Recipients'}
            </Text>
            <Text style={styles.summaryValue}>
              {transferType === 'salary' ? employees.length : recipients.length}
            </Text>
          </View>
          <View style={[styles.summaryRow, styles.totalRow]}>
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

      {/* Epic Picker Modal */}
      <Modal visible={showEpicPicker} transparent animationType="slide">
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, { maxHeight: '70%' }]}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Epic</Text>
              <TouchableOpacity onPress={() => setShowEpicPicker(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>
            <FlatList
              data={epics}
              keyExtractor={(item) => item.id}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={styles.epicItem}
                  onPress={() => {
                    setSelectedEpic(item);
                    setRecipients(recipients.map(r => ({
                      ...r,
                      remark: item.name.length > 30 ? item.name.substring(0, 27) + '...' : item.name,
                      source_id: item.id,
                    })));
                    setShowEpicPicker(false);
                  }}
                >
                  <Text style={styles.epicItemText}>{item.name}</Text>
                  {selectedEpic?.id === item.id && (
                    <Ionicons name="checkmark-circle" size={20} color={colors.primary} />
                  )}
                </TouchableOpacity>
              )}
            />
          </View>
        </View>
      </Modal>

      {/* Bank Picker Modal */}
      <Modal visible={showBankPicker} transparent animationType="slide">
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, { maxHeight: '70%' }]}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Bank</Text>
              <TouchableOpacity onPress={() => setShowBankPicker(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>
            <FlatList
              data={banks}
              keyExtractor={(item) => item.code}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={styles.epicItem}
                  onPress={() => {
                    setRecipients(recipients.map(r => ({
                      ...r,
                      recipient_bank: item.code,
                    })));
                    setShowBankPicker(false);
                  }}
                >
                  <Text style={styles.epicItemText}>{item.name}</Text>
                </TouchableOpacity>
              )}
            />
          </View>
        </View>
      </Modal>

      {/* OTP Modal */}
      <Modal visible={showOtpModal} transparent animationType="slide">
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Enter OTP</Text>
              <TouchableOpacity onPress={() => setShowOtpModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
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
      </Modal>
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
    marginBottom: 16,
    width: 40,
    height: 40,
    justifyContent: 'center',
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
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textSecondary,
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  typeOptions: {
    flexDirection: 'row',
    gap: 12,
  },
  typeOption: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    borderWidth: 2,
    borderColor: colors.border,
    borderRadius: 12,
    backgroundColor: colors.surface,
    gap: 8,
  },
  selectedType: {
    borderColor: colors.primary,
    backgroundColor: colors.primary,
  },
  typeOptionText: {
    fontSize: 14,
    color: colors.text,
    fontWeight: '600',
  },
  selectedTypeText: {
    color: '#fff',
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
  employeeItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    backgroundColor: colors.surface,
    borderRadius: 12,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
  employeeInfo: {
    flex: 1,
  },
  employeeName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  employeeEmail: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 4,
  },
  employeeAmount: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.primary,
  },
  epicSelectButton: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 16,
  },
  epicSelectText: {
    fontSize: 16,
    color: colors.text,
  },
  epicSelectPlaceholder: {
    color: colors.textSecondary,
  },
  addButton: {
    backgroundColor: colors.primary + '15',
    padding: 8,
    borderRadius: 8,
  },
  recipientCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  recipientHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  recipientNumber: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  field: {
    marginBottom: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.text,
    marginBottom: 8,
  },
  input: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 14,
    fontSize: 16,
    color: colors.text,
  },
  bankSelectButton: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 14,
  },
  bankSelectText: {
    fontSize: 16,
    color: colors.text,
  },
  bankSelectPlaceholder: {
    color: colors.textSecondary,
  },
  accountInputContainer: {
    flexDirection: 'row',
    gap: 8,
  },
  verifyButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: 16,
    justifyContent: 'center',
    borderRadius: 12,
  },
  verifyButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  accountNameContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.success + '15',
    padding: 12,
    borderRadius: 8,
    marginBottom: 16,
    gap: 8,
  },
  accountName: {
    color: colors.success,
    fontWeight: '600',
    fontSize: 14,
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
  totalRow: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: colors.border,
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
    marginBottom: 24,
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
    justifyContent: 'flex-end',
    padding: 0,
  },
  modalContent: {
    width: '100%',
    backgroundColor: colors.background,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    maxHeight: '85%',
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
  epicItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  epicItemText: {
    fontSize: 16,
    color: colors.text,
  },
  otpInput: {
    backgroundColor: colors.surface,
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
