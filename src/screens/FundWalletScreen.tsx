import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator, Modal } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation, useRoute } from '@react-navigation/native';
import { useTheme } from '../theme/ThemeContext';
import { walletApi } from '../services/api';
import { Wallet } from '../types';
import { WebView } from 'react-native-webview';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

type RouteParams = {
  walletType: 'business' | 'user';
};

type PaymentMethod = 'card' | 'bank';

export default function FundWalletScreen() {
  const navigation = useNavigation();
  const route = useRoute();
  const { colors } = useTheme();
  const { walletType } = route.params as RouteParams;
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState<PaymentMethod>('card');
  const [loading, setLoading] = useState(false);
  const [wallets, setWallets] = useState<{ user_wallet?: Wallet; business_wallet?: Wallet }>({});
  const [showWebView, setShowWebView] = useState(false);
  const [paymentUrl, setPaymentUrl] = useState('');
  const [showPaymentInfo, setShowVirtualAccountInfo] = useState(false);
  const [cardPaymentInfo, setCardPaymentInfo] = useState<{ fee: number; total_amount: number; payment_url: string } | null>(null);

  useEffect(() => {
    fetchWalletInfo();
  }, []);

  const fetchWalletInfo = async () => {
    try {
      const res = await walletApi.getInfo();
      setWallets(res.data);
    } catch (error) {
      console.error('Failed to fetch wallet info:', error);
    }
  };

  const handleContinue = async () => {
    if (!amount || parseFloat(amount) <= 0) {
      Alert.alert('Error', 'Please enter a valid amount');
      return;
    }

    if (method === 'bank') {
      setShowVirtualAccountInfo(true);
      return;
    }

    // Card payment flow
    setLoading(true);
    try {
      const response = await walletApi.fundCard(parseFloat(amount), walletType);
      if (response.data.success) {
        setCardPaymentInfo({
          fee: response.data.fee,
          total_amount: response.data.total_amount,
          payment_url: response.data.payment_url
        });
      }
    } catch (error: any) {
      // Toast handles error display
    } finally {
      setLoading(false);
    }
  };

  const handleStartPayment = () => {
    if (cardPaymentInfo?.payment_url) {
      setPaymentUrl(cardPaymentInfo.payment_url);
      setShowWebView(true);
    }
  };

  const handleWebViewNavigationStateChange = (newNavState: any) => {
    const { url } = newNavState;
    if (!url) return;

    // Check for success/callback URL from Squad
    if (url.includes('success') || url.includes('callback')) {
      // Extract reference from URL
      const urlParams = new URLSearchParams(url.split('?')[1]);
      const reference = urlParams.get('reference');
      
      verifyPayment(reference);
    }
  };

  const verifyPayment = async (reference: string | null) => {
    if (!reference) {
      setShowWebView(false);
      setCardPaymentInfo(null);
      Alert.alert('Success', 'Payment processed successfully', [
        { text: 'OK', onPress: () => navigation.goBack() }
      ]);
      return;
    }

    setLoading(true);
    try {
      await walletApi.verifyPayment(reference);
      setShowWebView(false);
      setCardPaymentInfo(null);
      Alert.alert('Success', 'Payment verified successfully!', [
        { text: 'OK', onPress: () => navigation.goBack() }
      ]);
    } catch (error: any) {
      Alert.alert('Warning', 'Payment status could not be verified. Please check your wallet balance.', [
        { text: 'OK', onPress: () => navigation.goBack() }
      ]);
    } finally {
      setLoading(false);
    }
  };

  const selectedWallet = walletType === 'business' ? wallets.business_wallet : wallets.user_wallet;

  const styles = createStyles(colors);

  return (
    <View style={styles.container}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
            <Ionicons name="arrow-back" size={24} color={colors.text} />
          </TouchableOpacity>
          <Text style={styles.title}>Fund Wallet</Text>
        </View>

        <Text style={styles.subtitle}>Choose how you want to fund your {walletType} wallet</Text>
        
        <View style={styles.methodsContainer}>
          <TouchableOpacity 
            style={[styles.methodCard, method === 'card' && styles.activeMethod]}
            onPress={() => setMethod('card')}
          >
            <View style={[styles.methodIcon, method === 'card' && styles.activeMethodIcon]}>
              <Ionicons name="card-outline" size={24} color={method === 'card' ? '#fff' : colors.primary} />
            </View>
            <View style={styles.methodInfo}>
              <Text style={styles.methodTitle}>Card Payment</Text>
              <Text style={styles.methodDesc}>Instant funding via Debit/Credit Card</Text>
            </View>
            <View style={styles.radio}>
              <View style={[styles.radioInner, method === 'card' && styles.radioActive]} />
            </View>
          </TouchableOpacity>
          
          <TouchableOpacity 
            style={[styles.methodCard, method === 'bank' && styles.activeMethod]}
            onPress={() => setMethod('bank')}
          >
            <View style={[styles.methodIcon, method === 'bank' && styles.activeMethodIcon]}>
              <Ionicons name="business-outline" size={24} color={method === 'bank' ? '#fff' : colors.primary} />
            </View>
            <View style={styles.methodInfo}>
              <Text style={styles.methodTitle}>Bank Transfer</Text>
              <Text style={styles.methodDesc}>Transfer to your virtual account</Text>
            </View>
            <View style={styles.radio}>
              <View style={[styles.radioInner, method === 'bank' && styles.radioActive]} />
            </View>
          </TouchableOpacity>
        </View>
        
        <View style={styles.amountSection}>
          <Text style={styles.label}>Amount to Fund</Text>
          <View style={styles.inputWrapper}>
            <Text style={styles.currencySymbol}>₦</Text>
            <TextInput
              style={styles.amountInput}
              placeholder="0.00"
              value={amount}
              onChangeText={setAmount}
              keyboardType="numeric"
              placeholderTextColor={colors.textSecondary}
            />
          </View>
          <View style={styles.quickAmounts}>
            {['5000', '10000', '20000', '50000'].map((val) => (
              <TouchableOpacity 
                key={val} 
                style={[styles.quickAmountButton, amount === val && styles.quickAmountActive]}
                onPress={() => setAmount(val)}
              >
                <Text style={[styles.quickAmountText, amount === val && styles.quickAmountTextActive]}>₦{parseFloat(val).toLocaleString()}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        <TouchableOpacity 
          style={[styles.mainButton, (!amount || loading) && styles.buttonDisabled]} 
          disabled={!amount || loading}
          onPress={handleContinue}
        >
          <LinearGradient
            colors={['#2563eb', '#3b82f6']}
            style={styles.gradientButton}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 0 }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Continue</Text>
            )}
          </LinearGradient>
        </TouchableOpacity>
      </ScrollView>

      {/* Payment Confirmation Modal */}
      <Modal visible={!!cardPaymentInfo} transparent animationType="fade">
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Confirm Payment</Text>
              <TouchableOpacity onPress={() => setCardPaymentInfo(null)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>
            
            <View style={styles.paymentDetails}>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Amount</Text>
                <Text style={styles.detailValue}>₦{parseFloat(amount).toLocaleString()}</Text>
              </View>
              <View style={styles.detailRow}>
                <Text style={styles.detailLabel}>Service Fee</Text>
                <Text style={styles.detailValue}>₦{cardPaymentInfo?.fee.toLocaleString()}</Text>
              </View>
              <View style={[styles.detailRow, styles.totalRow]}>
                <Text style={styles.totalLabel}>Total</Text>
                <Text style={styles.totalValue}>₦{cardPaymentInfo?.total_amount.toLocaleString()}</Text>
              </View>
            </View>

            <TouchableOpacity style={styles.modalActionButton} onPress={handleStartPayment}>
              <LinearGradient
                colors={['#2563eb', '#3b82f6']}
                style={styles.gradientButton}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 0 }}
              >
                <Text style={styles.buttonText}>Proceed to Payment</Text>
              </LinearGradient>
            </TouchableOpacity>
            
            <TouchableOpacity style={styles.cancelButton} onPress={() => setCardPaymentInfo(null)}>
              <Text style={styles.cancelButtonText}>Cancel</Text>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      {/* Bank Transfer Info Modal */}
      <Modal visible={showPaymentInfo} transparent animationType="slide">
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Bank Transfer Details</Text>
              <TouchableOpacity onPress={() => setShowVirtualAccountInfo(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            {selectedWallet?.virtual_account_number ? (
              <View style={styles.bankInfoCard}>
                <Text style={styles.bankInfoTitle}>Transfer money to the account below</Text>
                
                <View style={styles.bankDetailItem}>
                  <Text style={styles.bankDetailLabel}>BANK NAME</Text>
                  <Text style={styles.bankDetailValue}>{selectedWallet.bank_name || 'Squad (GTBank)'}</Text>
                </View>
                
                <View style={styles.bankDetailItem}>
                  <Text style={styles.bankDetailLabel}>ACCOUNT NUMBER</Text>
                  <View style={styles.accountNumberRow}>
                    <Text style={styles.bankDetailValueBig}>{selectedWallet.virtual_account_number}</Text>
                    <TouchableOpacity onPress={() => Alert.alert('Copied', 'Account number copied to clipboard')}>
                      <Ionicons name="copy-outline" size={20} color={colors.primary} />
                    </TouchableOpacity>
                  </View>
                </View>
                
                <View style={styles.bankDetailItem}>
                  <Text style={styles.bankDetailLabel}>ACCOUNT NAME</Text>
                  <Text style={styles.bankDetailValue}>{selectedWallet.account_name || 'Metroflow Wallet'}</Text>
                </View>
              </View>
            ) : (
              <View style={styles.emptyState}>
                <Ionicons name="alert-circle-outline" size={48} color={colors.warning} />
                <Text style={styles.emptyText}>No virtual account found for this wallet. Please create one in the Wallet screen.</Text>
              </View>
            )}

            <TouchableOpacity 
              style={styles.modalActionButton} 
              onPress={() => setShowVirtualAccountInfo(false)}
            >
              <LinearGradient
                colors={['#2563eb', '#3b82f6']}
                style={styles.gradientButton}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 0 }}
              >
                <Text style={styles.buttonText}>I've made the transfer</Text>
              </LinearGradient>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      {/* WebView Modal */}
      <Modal visible={showWebView} animationType="slide">
        <SafeAreaView style={{ flex: 1 }}>
          <View style={styles.webViewHeader}>
            <TouchableOpacity onPress={() => setShowWebView(false)} style={styles.webViewClose}>
              <Ionicons name="close" size={28} color={colors.text} />
            </TouchableOpacity>
            <Text style={styles.webViewTitle}>Secure Payment</Text>
            <View style={{ width: 40 }} />
          </View>
          <WebView
            source={{ uri: paymentUrl }}
            onNavigationStateChange={handleWebViewNavigationStateChange}
            startInLoadingState
            renderLoading={() => <ActivityIndicator style={styles.webViewLoader} size="large" color={colors.primary} />}
          />
        </SafeAreaView>
      </Modal>
    </View>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    padding: 24,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    marginTop: 10,
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
    marginBottom: 32,
  },
  methodsContainer: {
    gap: 16,
    marginBottom: 32,
  },
  methodCard: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    backgroundColor: colors.surface,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  activeMethod: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '05',
  },
  methodIcon: {
    width: 48,
    height: 48,
    backgroundColor: colors.primary + '10',
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  activeMethodIcon: {
    backgroundColor: colors.primary,
  },
  methodInfo: {
    flex: 1,
  },
  methodTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.text,
  },
  methodDesc: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 2,
  },
  radio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  radioInner: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: 'transparent',
  },
  radioActive: {
    backgroundColor: colors.primary,
  },
  amountSection: {
    marginBottom: 40,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 12,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    backgroundColor: colors.surface,
    paddingHorizontal: 20,
    marginBottom: 16,
  },
  currencySymbol: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    marginRight: 8,
  },
  amountInput: {
    flex: 1,
    paddingVertical: 20,
    fontSize: 28,
    fontWeight: 'bold',
    color: colors.text,
  },
  quickAmounts: {
    flexDirection: 'row',
    gap: 10,
    flexWrap: 'wrap',
  },
  quickAmountButton: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  quickAmountActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  quickAmountText: {
    color: colors.text,
    fontWeight: '600',
    fontSize: 14,
  },
  quickAmountTextActive: {
    color: colors.primary,
  },
  mainButton: {
    borderRadius: 16,
    overflow: 'hidden',
  },
  gradientButton: {
    padding: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 32,
    borderTopRightRadius: 32,
    padding: 24,
    paddingBottom: 40,
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
  paymentDetails: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 20,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: colors.border,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  detailLabel: {
    color: colors.textSecondary,
    fontSize: 15,
  },
  detailValue: {
    color: colors.text,
    fontWeight: '600',
    fontSize: 15,
  },
  totalRow: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  totalLabel: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.text,
  },
  totalValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.primary,
  },
  modalActionButton: {
    borderRadius: 16,
    overflow: 'hidden',
    marginBottom: 12,
  },
  cancelButton: {
    padding: 16,
    alignItems: 'center',
  },
  cancelButtonText: {
    color: colors.textSecondary,
    fontSize: 16,
    fontWeight: '600',
  },
  bankInfoCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 24,
    borderWidth: 1,
    borderColor: colors.border,
    marginBottom: 24,
  },
  bankInfoTitle: {
    fontSize: 15,
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: 24,
  },
  bankDetailItem: {
    marginBottom: 20,
  },
  bankDetailLabel: {
    fontSize: 11,
    fontWeight: 'bold',
    color: colors.textSecondary,
    letterSpacing: 1,
    marginBottom: 4,
  },
  bankDetailValue: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  bankDetailValueBig: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    letterSpacing: 1,
  },
  accountNumberRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  emptyState: {
    alignItems: 'center',
    padding: 40,
  },
  emptyText: {
    textAlign: 'center',
    color: colors.textSecondary,
    marginTop: 16,
    lineHeight: 22,
  },
  webViewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    backgroundColor: colors.surface,
  },
  webViewClose: {
    padding: 4,
  },
  webViewTitle: {
    flex: 1,
    textAlign: 'center',
    fontSize: 17,
    fontWeight: 'bold',
    color: colors.text,
  },
  webViewLoader: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    marginLeft: -20,
    marginTop: -20,
  },
});
