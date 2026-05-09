import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, ActivityIndicator, Alert, TextInput, Modal, FlatList, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { MainTabParamList, RootStackParamList, DrawerParamList } from '../navigation';
import { CompositeNavigationProp } from '@react-navigation/native';
import { BottomTabNavigationProp } from '@react-navigation/bottom-tabs';
import { DrawerNavigationProp } from '@react-navigation/drawer';
import { useTheme } from '../theme/ThemeContext';
import { walletApi, transfersApi, kycApi } from '../services/api';
import { Wallet, Bank } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';

type WalletScreenNavigationProp = CompositeNavigationProp<
  BottomTabNavigationProp<MainTabParamList, 'Wallet'>,
  CompositeNavigationProp<
    NativeStackNavigationProp<RootStackParamList>,
    DrawerNavigationProp<DrawerParamList>
  >
>;

export default function WalletScreen() {
  const navigation = useNavigation<WalletScreenNavigationProp>();
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isKycLoading, setIsKycLoading] = useState(true);
  const [kycStatus, setKycStatus] = useState<{ ninVerified: boolean; bvnVerified: boolean }>({
    ninVerified: false,
    bvnVerified: false,
  });
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [selectedWalletType, setSelectedWalletType] = useState<'user' | 'business'>('user');
  const [wallets, setWallets] = useState<{ user_wallet?: Wallet; business_wallet?: Wallet }>({});
  const [banks, setBanks] = useState<Bank[]>([]);
  const [transferData, setTransferData] = useState({
    bankCode: '',
    accountNumber: '',
    accountName: '',
    amount: '',
    remark: '',
    otp: '',
  });
  const [showOtpModal, setShowOtpModal] = useState(false);
  const [showVirtualAccountModal, setShowVirtualAccountModal] = useState(false);
  const [showBankSearchModal, setShowBankSearchModal] = useState(false);
  const [bankSearchQuery, setBankSearchQuery] = useState('');

  const styles = createStyles(colors);

  useEffect(() => {
    checkKycStatus();
    fetchBanks();
  }, []);

  const checkKycStatus = async (showLoader = true) => {
    if (showLoader) setIsKycLoading(true);
    try {
      const response = await kycApi.getStatus();
      const { user } = response.data;
      const ninVerified = user.ninStatus === 'verified';
      const bvnVerified = user.bvnStatus === 'verified';
      
      setKycStatus({ ninVerified, bvnVerified });
      
      if (ninVerified && bvnVerified) {
        fetchWalletData();
      }
    } catch (error) {
      console.error('Failed to fetch KYC status:', error);
    } finally {
      setIsKycLoading(false);
      setIsRefreshing(false);
    }
  };

  const onRefresh = () => {
    setIsRefreshing(true);
    checkKycStatus(false);
  };

  const fetchWalletData = async () => {
    try {
      const response = await walletApi.getInfo();
      if (response.data) {
        setWallets(response.data);
      }
    } catch (error) {
      console.error('Failed to fetch wallet data:', error);
    }
  };

  const fetchBanks = async () => {
    try {
      const response = await transfersApi.getBanks();
      if (response.data.success) {
        setBanks(response.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch banks:', error);
    }
  };

  const handleCreateVirtualAccount = async () => {
    setIsLoading(true);
    try {
      const response = await walletApi.createVirtualAccount();
      if (response.data.success) {
        Alert.alert('Success', response.data.message);
        fetchWalletData();
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to create virtual account');
    } finally {
      setIsLoading(false);
      setShowVirtualAccountModal(false);
    }
  };

  const handleResolveAccount = async () => {
    if (!transferData.bankCode || !transferData.accountNumber) {
      Alert.alert('Error', 'Please select bank and enter account number');
      return;
    }

    setIsLoading(true);
    try {
      const response = await transfersApi.resolveAccount(transferData.bankCode, transferData.accountNumber);
      if (response.data.success) {
        setTransferData(prev => ({ ...prev, accountName: response.data.data.account_name }));
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to resolve account');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRequestOtp = async () => {
    const wallet = selectedWalletType === 'user' ? wallets.user_wallet : wallets.business_wallet;
    if (!wallet) {
      Alert.alert('Error', 'Wallet not found');
      return;
    }

    setIsLoading(true);
    try {
      await transfersApi.requestTransferOtp(wallet.id);
      Alert.alert('Success', 'OTP sent to your registered email/phone');
      setShowOtpModal(true);
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to send OTP');
    } finally {
      setIsLoading(false);
    }
  };

  const handleInitiateTransfer = async () => {
    const wallet = selectedWalletType === 'user' ? wallets.user_wallet : wallets.business_wallet;
    if (!wallet) {
      Alert.alert('Error', 'Wallet not found');
      return;
    }

    if (!transferData.amount || !transferData.otp) {
      Alert.alert('Error', 'Please fill all fields');
      return;
    }

    setIsLoading(true);
    try {
      await transfersApi.singleTransfer({
        bankCode: transferData.bankCode,
        accountNumber: transferData.accountNumber,
        accountName: transferData.accountName,
        amount: parseFloat(transferData.amount),
        remark: transferData.remark,
        otp: transferData.otp,
        wallet_id: wallet.id,
      });
      Alert.alert('Success', 'Transfer initiated successfully');
      setShowTransferModal(false);
      setShowOtpModal(false);
      setTransferData({
        bankCode: '',
        accountNumber: '',
        accountName: '',
        amount: '',
        remark: '',
        otp: '',
      });
      fetchWalletData();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Transfer failed');
    } finally {
      setIsLoading(false);
    }
  };

  const openTransferModal = (walletType: 'user' | 'business') => {
    setSelectedWalletType(walletType);
    setTransferData({
      bankCode: '',
      accountNumber: '',
      accountName: '',
      amount: '',
      remark: '',
      otp: '',
    });
    setShowTransferModal(true);
  };

  const renderWalletCard = (wallet: any | undefined, label: string, walletType: 'user' | 'business') => (
    <View style={styles.walletCard}>
      <Text style={styles.walletLabel}>{label}</Text>
      <Text style={styles.walletBalance}>
        {wallet ? `${wallet.currency} ${parseFloat(wallet.balance).toLocaleString()}` : '₦0.00'}
      </Text>
      {wallet && wallet.virtual_account_number && (
        <View style={styles.accountInfo}>
          <View style={styles.accountDetailRow}>
            <Text style={styles.accountDetailLabel}>Account Number:</Text>
            <Text style={styles.accountNumber}>{wallet.virtual_account_number}</Text>
          </View>
          <View style={styles.accountDetailRow}>
            <Text style={styles.accountDetailLabel}>Bank:</Text>
            <Text style={styles.bankName}>{wallet.bank_name || 'Squad (GTBank)'}</Text>
          </View>
          {wallet.account_name && (
            <View style={styles.accountDetailRow}>
              <Text style={styles.accountDetailLabel}>Account Name:</Text>
              <Text style={styles.accountNameText}>{wallet.account_name}</Text>
            </View>
          )}
        </View>
      )}
      <View style={styles.walletActions}>
        <TouchableOpacity 
          style={styles.actionButton}
          onPress={() => navigation.navigate('FundWallet', { walletType })}
        >
          <Text style={styles.actionButtonText}>Fund Wallet</Text>
        </TouchableOpacity>
        <TouchableOpacity 
          style={styles.actionButton}
          onPress={() => openTransferModal(walletType)}
        >
          <Text style={styles.actionButtonText}>Transfer</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  if (isKycLoading) {
    return (
      <View style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  if (!kycStatus.ninVerified || !kycStatus.bvnVerified) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.header}>
          <TouchableOpacity 
            style={styles.menuButton}
            onPress={() => navigation.getParent()?.dispatch(DrawerActions.openDrawer())}
          >
            <Ionicons name="menu" size={24} color={colors.text} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>My Wallets</Text>
        </View>
        <View style={styles.kycPromptContainer}>
          <View style={styles.kycIconContainer}>
            <Ionicons name="lock-closed" size={64} color={colors.primary} />
          </View>
          <Text style={styles.kycTitle}>KYC Verification Required</Text>
          <Text style={styles.kycSubtitle}>
            To access your wallet and perform transactions, you need to verify both your NIN and BVN.
          </Text>
          
          <View style={styles.kycStatusList}>
            <View style={styles.kycStatusItem}>
              <Ionicons 
                name={kycStatus.bvnVerified ? "checkmark-circle" : "alert-circle"} 
                size={20} 
                color={kycStatus.bvnVerified ? colors.success : colors.error} 
              />
              <Text style={styles.kycStatusText}>
                BVN {kycStatus.bvnVerified ? 'Verified' : 'Not Verified'}
              </Text>
            </View>
            <View style={styles.kycStatusItem}>
              <Ionicons 
                name={kycStatus.ninVerified ? "checkmark-circle" : "alert-circle"} 
                size={20} 
                color={kycStatus.ninVerified ? colors.success : colors.error} 
              />
              <Text style={styles.kycStatusText}>
                NIN {kycStatus.ninVerified ? 'Verified' : 'Not Verified'}
              </Text>
            </View>
          </View>

          <TouchableOpacity 
            style={styles.kycButton}
            onPress={() => navigation.navigate('KycPrompt')}
          >
            <Text style={styles.kycButtonText}>Complete KYC Now</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <ScrollView 
      style={styles.container}
      refreshControl={
        <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} colors={[colors.primary]} />
      }
    >
      <View style={styles.header}>
        <TouchableOpacity 
          style={styles.menuButton}
          onPress={() => navigation.getParent()?.dispatch(DrawerActions.openDrawer())}
        >
          <Ionicons name="menu" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>My Wallets</Text>
      </View>

      {renderWalletCard(wallets.user_wallet, 'Personal Wallet', 'user')}
      {renderWalletCard(wallets.business_wallet, 'Business Wallet', 'business')}

      <View style={styles.quickActions}>
        <TouchableOpacity 
          style={styles.quickActionButton}
          onPress={() => setShowVirtualAccountModal(true)}
        >
          <Ionicons name="card-outline" size={24} color={colors.primary} />
          <Text style={styles.quickActionText}>Create Virtual Account</Text>
        </TouchableOpacity>
        <TouchableOpacity 
          style={styles.quickActionButton}
          onPress={() => navigation.navigate('Transfers')}
        >
          <Ionicons name="swap-horizontal-outline" size={24} color={colors.primary} />
          <Text style={styles.quickActionText}>View Transfers</Text>
        </TouchableOpacity>
      </View>

      <TouchableOpacity 
        style={styles.createBusinessButton}
        onPress={() => navigation.navigate('BusinessKyc')}
      >
        <Text style={styles.createBusinessText}>Create Business Account</Text>
      </TouchableOpacity>

      <Modal
        visible={showTransferModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowTransferModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Send Money</Text>
              <TouchableOpacity onPress={() => setShowTransferModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <ScrollView showsVerticalScrollIndicator={false}>
              <View style={styles.field}>
                <Text style={styles.label}>Select Bank</Text>
                <TouchableOpacity 
                  style={styles.bankSelectButton}
                  onPress={() => setShowBankSearchModal(true)}
                >
                  <Text style={[
                    styles.bankSelectText,
                    !transferData.bankCode && styles.bankSelectPlaceholder
                  ]}>
                    {banks.find(b => b.code === transferData.bankCode)?.name || 'Select a bank'}
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
                    value={transferData.accountNumber}
                    onChangeText={(text) => setTransferData(prev => ({ ...prev, accountNumber: text }))}
                    keyboardType="numeric"
                  />
                  <TouchableOpacity style={styles.verifyButton} onPress={handleResolveAccount}>
                    {isLoading ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={styles.verifyButtonText}>Verify</Text>
                    )}
                  </TouchableOpacity>
                </View>
              </View>

              {transferData.accountName ? (
                <View style={styles.accountNameContainer}>
                  <Ionicons name="checkmark-circle" size={20} color="#4CAF50" />
                  <Text style={styles.accountName}>{transferData.accountName}</Text>
                </View>
              ) : null}

              <View style={styles.field}>
                <Text style={styles.label}>Amount</Text>
                <TextInput
                  style={styles.input}
                  placeholder="Enter amount"
                  placeholderTextColor={colors.textSecondary}
                  value={transferData.amount}
                  onChangeText={(text) => setTransferData(prev => ({ ...prev, amount: text }))}
                  keyboardType="numeric"
                />
              </View>

              <View style={styles.field}>
                <Text style={styles.label}>Remark (Optional)</Text>
                <TextInput
                  style={styles.input}
                  placeholder="Add a remark"
                  placeholderTextColor={colors.textSecondary}
                  value={transferData.remark}
                  onChangeText={(text) => setTransferData(prev => ({ ...prev, remark: text }))}
                />
              </View>

              <TouchableOpacity 
                style={[styles.submitButton, isLoading && styles.submitButtonDisabled]}
                onPress={handleRequestOtp}
                disabled={isLoading || !transferData.accountName}
              >
                {isLoading ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.submitButtonText}>Send OTP</Text>
                )}
              </TouchableOpacity>
            </ScrollView>
          </View>
        </View>
      </Modal>

      {/* Bank Search Modal */}
      <Modal
        visible={showBankSearchModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowBankSearchModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, { height: '80%' }]}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Select Bank</Text>
              <TouchableOpacity onPress={() => setShowBankSearchModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.bankSearchContainer}>
              <Ionicons name="search" size={20} color={colors.textSecondary} />
              <TextInput
                style={styles.bankSearchInput}
                placeholder="Search bank name..."
                placeholderTextColor={colors.textSecondary}
                value={bankSearchQuery}
                onChangeText={setBankSearchQuery}
                autoFocus
              />
            </View>

            <FlatList
              data={banks.filter(b => b.name.toLowerCase().includes(bankSearchQuery.toLowerCase()))}
              keyExtractor={(item) => item.code}
              renderItem={({ item }) => (
                <TouchableOpacity
                  style={styles.bankSelectItem}
                  onPress={() => {
                    setTransferData(prev => ({ ...prev, bankCode: item.code }));
                    setShowBankSearchModal(false);
                    setBankSearchQuery('');
                  }}
                >
                  <Text style={styles.bankSelectItemText}>{item.name}</Text>
                  {transferData.bankCode === item.code && (
                    <Ionicons name="checkmark-circle" size={20} color={colors.primary} />
                  )}
                </TouchableOpacity>
              )}
              contentContainerStyle={{ paddingBottom: 20 }}
            />
          </View>
        </View>
      </Modal>

      <Modal
        visible={showOtpModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowOtpModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Enter OTP</Text>
              <TouchableOpacity onPress={() => setShowOtpModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>OTP Code</Text>
              <TextInput
                style={styles.input}
                placeholder="Enter OTP"
                placeholderTextColor={colors.textSecondary}
                value={transferData.otp}
                onChangeText={(text) => setTransferData(prev => ({ ...prev, otp: text }))}
                keyboardType="numeric"
                maxLength={6}
              />
            </View>

            <TouchableOpacity 
              style={[styles.submitButton, isLoading && styles.submitButtonDisabled]}
              onPress={handleInitiateTransfer}
              disabled={isLoading}
            >
              {isLoading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.submitButtonText}>Confirm Transfer</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      <Modal
        visible={showVirtualAccountModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowVirtualAccountModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Create Virtual Account</Text>
              <TouchableOpacity onPress={() => setShowVirtualAccountModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <Text style={styles.description}>
              Create a virtual account to receive payments directly into your wallet.
            </Text>

            <TouchableOpacity 
              style={[styles.submitButton, isLoading && styles.submitButtonDisabled]}
              onPress={handleCreateVirtualAccount}
              disabled={isLoading}
            >
              {isLoading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <Text style={styles.submitButtonText}>Create Virtual Account</Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.surfaceVariant,
  },
  center: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    padding: 24,
    backgroundColor: colors.surface,
    flexDirection: 'row',
    alignItems: 'center',
  },
  menuButton: {
    padding: 8,
    marginRight: 8,
  },
  headerTitle: {
    flex: 1,
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  walletCard: {
    margin: 16,
    padding: 24,
    backgroundColor: colors.primary,
    borderRadius: 16,
  },
  walletLabel: {
    color: colors.primaryLight,
    fontSize: 14,
    marginBottom: 8,
  },
  walletBalance: {
    color: '#fff',
    fontSize: 32,
    fontWeight: 'bold',
    marginBottom: 24,
  },
  accountInfo: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    padding: 16,
    borderRadius: 12,
    marginBottom: 20,
  },
  accountDetailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  accountDetailLabel: {
    color: colors.primaryLight,
    fontSize: 12,
  },
  accountNumber: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  bankName: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
  },
  accountNameText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
  },
  walletActions: {
    flexDirection: 'row',
    gap: 12,
  },
  actionButton: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.2)',
    padding: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  actionButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  quickActions: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    gap: 12,
  },
  quickActionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surface,
    padding: 16,
    borderRadius: 12,
    gap: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
  quickActionText: {
    color: colors.primary,
    fontWeight: '600',
    fontSize: 12,
  },
  createBusinessButton: {
    margin: 16,
    padding: 16,
    backgroundColor: colors.surface,
    borderRadius: 12,
    alignItems: 'center',
    borderWidth: 2,
    borderColor: colors.primary,
    borderStyle: 'dashed',
  },
  createBusinessText: {
    color: colors.primary,
    fontWeight: '600',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    maxHeight: '80%',
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
  field: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.text,
    marginBottom: 8,
  },
  input: {
    backgroundColor: colors.surface,
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
    backgroundColor: colors.surface,
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
  bankSearchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceVariant,
    borderRadius: 12,
    paddingHorizontal: 12,
    marginBottom: 16,
  },
  bankSearchInput: {
    flex: 1,
    paddingVertical: 12,
    fontSize: 16,
    color: colors.text,
    marginLeft: 8,
  },
  bankSelectItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  bankSelectItemText: {
    fontSize: 16,
    color: colors.text,
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
    marginBottom: 20,
    gap: 8,
  },
  accountName: {
    color: colors.success,
    fontWeight: '600',
    fontSize: 14,
  },
  submitButton: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  submitButtonDisabled: {
    opacity: 0.5,
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  description: {
    fontSize: 16,
    color: colors.textSecondary,
    lineHeight: 24,
    marginBottom: 24,
  },
  kycPromptContainer: {
    flex: 1,
    padding: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  kycIconContainer: {
    width: 120,
    height: 120,
    borderRadius: 60,
    backgroundColor: colors.primary + '10',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  kycTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 12,
    textAlign: 'center',
  },
  kycSubtitle: {
    fontSize: 16,
    color: colors.textSecondary,
    textAlign: 'center',
    lineHeight: 24,
    marginBottom: 32,
    paddingHorizontal: 20,
  },
  kycStatusList: {
    width: '100%',
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 32,
    borderWidth: 1,
    borderColor: colors.border,
  },
  kycStatusItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    gap: 12,
  },
  kycStatusText: {
    fontSize: 15,
    color: colors.text,
    fontWeight: '500',
  },
  kycButton: {
    width: '100%',
    backgroundColor: colors.primary,
    padding: 18,
    borderRadius: 16,
    alignItems: 'center',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  kycButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
