import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, Alert, Modal, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { subscriptionApi } from '../services/api';
import { Subscription, Plan, Card, SubscriptionTransaction } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { WebView } from 'react-native-webview';
import { LinearGradient } from 'expo-linear-gradient';

type Props = NativeStackScreenProps<RootStackParamList, 'Subscription'>;

export default function SubscriptionScreen({ navigation }: Props) {
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(true);
  const [currentSubscription, setCurrentSubscription] = useState<Subscription | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [cards, setCards] = useState<Card[]>([]);
  const [transactions, setTransactions] = useState<SubscriptionTransaction[]>([]);
  const [selectedPlan, setSelectedPlan] = useState<string | null>(null);
  
  // WebView state
  const [showWebView, setShowWebView] = useState(false);
  const [webViewUrl, setWebViewUrl] = useState('');
  
  // Pagination state
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [statusFilter, setStatusFilter] = useState<string>('all');

  useEffect(() => {
    fetchData();
    fetchTransactions(1, true);
  }, [statusFilter]);

  const fetchData = async () => {
    try {
      const [subscriptionRes, plansRes, cardsRes] = await Promise.all([
        subscriptionApi.getCurrent(),
        subscriptionApi.getPlans(),
        subscriptionApi.getCards(),
      ]);

      if (subscriptionRes.data.success) {
        setCurrentSubscription(subscriptionRes.data.subscription);
      }
      if (plansRes.data.success) {
        setPlans(plansRes.data.plans || []);
      }
      if (cardsRes.data.success) {
        setCards(cardsRes.data.cards || []);
      }
    } catch (error) {
      console.error('Failed to fetch subscription data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const fetchTransactions = async (pageNumber: number, refresh = false) => {
    try {
      if (!refresh && !hasMore) return;
      if (refresh) setIsLoading(true);
      else setIsLoadingMore(true);

      const params: any = { page: pageNumber, perPage: 10 };
      if (statusFilter !== 'all') params.status = statusFilter;

      const response = await subscriptionApi.getTransactions(params);
      if (response.data.success) {
        const newTransactions = response.data.transactions || [];
        if (refresh) {
          setTransactions(newTransactions);
        } else {
          setTransactions(prev => [...prev, ...newTransactions]);
        }
        setHasMore(newTransactions.length === 10);
        setPage(pageNumber);
      }
    } catch (error) {
      console.error('Failed to fetch transactions:', error);
    } finally {
      setIsLoading(false);
      setIsLoadingMore(false);
    }
  };

  const handleUpgrade = async (plan: Plan) => {
    try {
      const response = await subscriptionApi.initiatePayment(plan.id, 'NGN');
      if (response.data.success && response.data.checkout_url) {
        setWebViewUrl(response.data.checkout_url);
        setShowWebView(true);
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to initiate payment');
    }
  };

  const handleAddCard = async () => {
    try {
      const response = await subscriptionApi.addCard();
      if (response.data.success && response.data.checkout_url) {
        setWebViewUrl(response.data.checkout_url);
        setShowWebView(true);
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to initiate card addition');
    }
  };

  const handleCancel = async () => {
    Alert.alert(
      'Cancel Subscription',
      'Are you sure you want to cancel your subscription? You will lose access to premium features at the end of your billing period.',
      [
        { text: 'Keep Subscription', style: 'cancel' },
        {
          text: 'Cancel Subscription',
          style: 'destructive',
          onPress: async () => {
            try {
              await subscriptionApi.cancel();
              Alert.alert('Success', 'Subscription cancelled successfully');
              fetchData();
            } catch (error: any) {
              Alert.alert('Error', error.response?.data?.message || 'Failed to cancel subscription');
            }
          },
        },
      ]
    );
  };

  const handleDowngrade = async () => {
    Alert.alert(
      'Downgrade Plan',
      'Are you sure you want to downgrade to the Free Plan?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Downgrade',
          onPress: async () => {
            try {
              await subscriptionApi.downgrade();
              Alert.alert('Success', 'Downgraded to free plan successfully');
              fetchData();
            } catch (error: any) {
              Alert.alert('Error', error.response?.data?.message || 'Failed to downgrade');
            }
          },
        },
      ]
    );
  };

  const handleWebViewNavigationStateChange = (newNavState: any) => {
    const { url } = newNavState;
    if (!url) return;

    if (url.includes('success') || url.includes('callback') || url.includes('verify')) {
      setShowWebView(false);
      // Extract reference if present in URL
      const referenceMatch = url.match(/reference=([^&]+)/);
      if (referenceMatch) {
        handleVerifyPayment(referenceMatch[1]);
      } else {
        fetchData();
        Alert.alert('Success', 'Action completed successfully');
      }
    }
  };

  const handleVerifyPayment = async (reference: string) => {
    try {
      await subscriptionApi.verifyPayment(reference);
      fetchData();
      Alert.alert('Success', 'Payment verified successfully');
    } catch (error) {
      console.error('Failed to verify payment:', error);
    }
  };

  const handleSetActiveCard = async (cardId: string) => {
    try {
      await subscriptionApi.setActiveCard(cardId);
      fetchData();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to set active card');
    }
  };

  const handleRemoveCard = async (cardId: string) => {
    Alert.alert(
      'Remove Card',
      'Are you sure you want to remove this card?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: async () => {
            try {
              await subscriptionApi.removeCard(cardId);
              fetchData();
            } catch (error: any) {
              Alert.alert('Error', error.response?.data?.message || 'Failed to remove card');
            }
          },
        },
      ]
    );
  };

  const styles = createStyles(colors);

  if (isLoading && !isLoadingMore) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  const renderTransaction = ({ item }: { item: SubscriptionTransaction }) => (
    <View style={styles.transactionCard}>
      <View style={styles.transactionInfo}>
        <Text style={styles.transactionType}>{item.type.toUpperCase()}</Text>
        <Text style={styles.transactionDate}>
          {new Date(item.created_at).toLocaleDateString()}
        </Text>
      </View>
      <View style={styles.transactionAmount}>
        <Text style={styles.amountText}>{item.currency} {item.amount.toLocaleString()}</Text>
        <View style={[styles.statusBadge, { 
            backgroundColor: item.status === 'success' ? colors.success + '20' : colors.error + '20' 
          }]}>
            <Text style={[styles.statusText, { 
              color: item.status === 'success' ? colors.success : colors.error 
            }]}>
              {item.status}
            </Text>
          </View>
      </View>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView} showsVerticalScrollIndicator={false}>
        <View style={styles.header}>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <Ionicons name="arrow-back" size={24} color={colors.text} />
          </TouchableOpacity>
          <Text style={styles.title}>Subscription</Text>
          <View style={{ width: 24 }} />
        </View>

        {currentSubscription && (
          <View style={styles.currentPlanSection}>
            <Text style={styles.sectionTitle}>Current Plan</Text>
            <View style={styles.currentPlanCard}>
              <View style={styles.planHeader}>
                <Text style={styles.planName}>{currentSubscription.plan_name}</Text>
                <View style={[styles.statusBadge, { 
                  backgroundColor: currentSubscription.subscription_status === 'active' ? colors.success + '20' : colors.error + '20' 
                }]}>
                  <Text style={[styles.statusText, { 
                    color: currentSubscription.subscription_status === 'active' ? colors.success : colors.error 
                  }]}>
                    {currentSubscription.subscription_status.charAt(0).toUpperCase() + currentSubscription.subscription_status.slice(1)}
                  </Text>
                </View>
              </View>
              <Text style={styles.planPrice}>₦{currentSubscription.plan_price}/month</Text>
              <View style={styles.planFeatures}>
                {currentSubscription.features?.map((feature, index) => (
                  <View key={index} style={styles.featureRow}>
                    <Ionicons name="checkmark-circle" size={16} color={colors.primary} />
                    <Text style={styles.featureText}>{feature}</Text>
                  </View>
                ))}
              </View>
              <View style={styles.usageInfo}>
                <Text style={styles.usageText}>
                  Next renewal: {new Date(currentSubscription.next_due_subscription_date).toLocaleDateString()}
                </Text>
              </View>
              <View style={styles.planActions}>
                {currentSubscription.plan_name !== 'Free' && (
                  <>
                    <TouchableOpacity style={styles.downgradeButton} onPress={handleDowngrade}>
                      <Text style={styles.downgradeButtonText}>Downgrade to Free</Text>
                    </TouchableOpacity>
                    {currentSubscription.subscription_status === 'active' && (
                      <TouchableOpacity style={styles.cancelButton} onPress={handleCancel}>
                        <Text style={styles.cancelButtonText}>Cancel Subscription</Text>
                      </TouchableOpacity>
                    )}
                  </>
                )}
              </View>
            </View>
          </View>
        )}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Upgrade Plan</Text>
          {plans.filter(p => p.name !== currentSubscription?.plan_name).map(plan => (
            <TouchableOpacity
              key={plan.id}
              style={[styles.planCard, selectedPlan === plan.id && styles.planCardSelected]}
              onPress={() => handleUpgrade(plan)}
            >
              <View style={styles.planCardHeader}>
                <Text style={styles.planCardName}>{plan.name}</Text>
                <Text style={styles.planCardPrice}>₦{plan.price}/month</Text>
              </View>
              <Text style={styles.planCardDescription}>{plan.description}</Text>
              <View style={styles.planCardFeatures}>
                {plan.features?.slice(0, 3).map((feature, index) => (
                  <Text key={index} style={styles.planCardFeature}>• {feature}</Text>
                ))}
              </View>
            </TouchableOpacity>
          ))}
        </View>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Payment Methods</Text>
            <TouchableOpacity onPress={handleAddCard}>
              <Text style={styles.addCardText}>Add Card</Text>
            </TouchableOpacity>
          </View>
          {cards.map(card => (
            <View key={card.id} style={styles.cardItem}>
              <View style={styles.cardInfo}>
                <Ionicons name="card-outline" size={24} color={colors.primary} />
                <View style={styles.cardDetails}>
                  <Text style={styles.cardNumber}>•••• •••• •••• {card.last4}</Text>
                  <Text style={styles.cardExpiry}>
                    {card.card_type} • Exp {card.exp_month}/{card.exp_year}
                  </Text>
                </View>
              </View>
              <View style={styles.cardActions}>
                {card.is_active ? (
                  <View style={styles.activeBadge}>
                    <Text style={styles.activeText}>Active</Text>
                  </View>
                ) : (
                  <TouchableOpacity onPress={() => handleSetActiveCard(card.id)}>
                    <Text style={styles.setActiveText}>Set Active</Text>
                  </TouchableOpacity>
                )}
                <TouchableOpacity onPress={() => handleDeleteCard(card.id)}>
                    <Ionicons name="trash-outline" size={20} color={colors.error} />
                  </TouchableOpacity>
              </View>
            </View>
          ))}
          {cards.length === 0 && (
            <View style={styles.emptyCards}>
              <Ionicons name="card-outline" size={48} color={colors.textSecondary} />
              <Text style={styles.emptyCardsText}>No payment methods added</Text>
            </View>
          )}
        </View>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Transaction History</Text>
            <TouchableOpacity onPress={() => subscriptionApi.exportTransactions()}>
              <Ionicons name="download-outline" size={20} color={colors.primary} />
            </TouchableOpacity>
          </View>
          
          <View style={styles.filterRow}>
            {(['all', 'success', 'failed'] as const).map(f => (
              <TouchableOpacity
                key={f}
                style={[styles.filterChip, statusFilter === f && styles.filterChipActive]}
                onPress={() => setStatusFilter(f)}
              >
                <Text style={[styles.filterChipText, statusFilter === f && styles.filterChipTextActive]}>
                  {f.toUpperCase()}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {transactions.map(item => (
            <View key={item.id} style={styles.transactionCard}>
              <View style={styles.transactionInfo}>
                <Text style={styles.transactionType}>{item.type?.toUpperCase() || 'PAYMENT'}</Text>
                <Text style={styles.transactionDate}>
                  {new Date(item.created_at).toLocaleDateString()}
                </Text>
              </View>
              <View style={styles.transactionAmount}>
                <Text style={styles.amountText}>{item.currency} {item.amount.toLocaleString()}</Text>
                <View style={[styles.statusBadge, { 
                  backgroundColor: item.status === 'success' ? colors.success + '20' : colors.error + '20' 
                }]}>
                  <Text style={[styles.statusText, { 
                    color: item.status === 'success' ? colors.success : colors.error 
                  }]}>{item.status}</Text>
                </View>
              </View>
            </View>
          ))}
          
          {hasMore && (
            <TouchableOpacity 
              style={styles.loadMoreButton} 
              onPress={() => fetchTransactions(page + 1)}
              disabled={isLoadingMore}
            >
              {isLoadingMore ? (
                <ActivityIndicator size="small" color={colors.primary} />
              ) : (
                <Text style={styles.loadMoreText}>Load More</Text>
              )}
            </TouchableOpacity>
          )}

          {transactions.length === 0 && !isLoading && (
            <View style={styles.emptyState}>
              <Text style={styles.emptyText}>No transactions found</Text>
            </View>
          )}
        </View>
      </ScrollView>

      {/* WebView Modal for Payments/Card Addition */}
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
            source={{ uri: webViewUrl }}
            onNavigationStateChange={handleWebViewNavigationStateChange}
            startInLoadingState
            renderLoading={() => <ActivityIndicator style={styles.webViewLoader} size="large" color={colors.primary} />}
          />
        </SafeAreaView>
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
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 24,
  },
  title: {
    fontSize: 20,
    fontWeight: '600',
    color: colors.text,
  },
  currentPlanSection: {
    padding: 24,
  },
  section: {
    padding: 24,
    paddingTop: 0,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 16,
  },
  addCardText: {
    fontSize: 14,
    color: colors.primary,
    fontWeight: '500',
  },
  currentPlanCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 24,
    borderWidth: 2,
    borderColor: colors.primary,
  },
  planHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  planName: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  statusBadge: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  planPrice: {
    fontSize: 32,
    fontWeight: 'bold',
    color: colors.primary,
    marginBottom: 16,
  },
  planFeatures: {
    marginBottom: 16,
  },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  featureText: {
    fontSize: 14,
    color: colors.text,
    marginLeft: 8,
  },
  usageInfo: {
    backgroundColor: colors.background,
    borderRadius: 12,
    padding: 12,
    marginBottom: 16,
  },
  usageText: {
    fontSize: 14,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  planActions: {
    gap: 12,
  },
  cancelButton: {
    borderWidth: 1,
    borderColor: colors.error,
    borderRadius: 12,
    padding: 14,
    alignItems: 'center',
  },
  cancelButtonText: {
    color: colors.error,
    fontSize: 14,
    fontWeight: '600',
  },
  downgradeButton: {
    backgroundColor: colors.primary + '10',
    borderRadius: 12,
    padding: 14,
    alignItems: 'center',
  },
  downgradeButtonText: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  planCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 20,
    marginBottom: 12,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  planCardSelected: {
    borderColor: colors.primary,
  },
  planCardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  planCardName: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  planCardPrice: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.primary,
  },
  planCardDescription: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 12,
  },
  planCardFeatures: {
    marginBottom: 12,
  },
  planCardFeature: {
    fontSize: 13,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  cardItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
    marginBottom: 8,
  },
  cardInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  cardDetails: {
    marginLeft: 12,
  },
  cardNumber: {
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  cardExpiry: {
    fontSize: 12,
    color: colors.textSecondary,
    marginTop: 2,
  },
  cardActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  activeBadge: {
    backgroundColor: colors.primary + '20',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 8,
  },
  activeText: {
    fontSize: 12,
    color: colors.primary,
    fontWeight: '500',
  },
  setActiveText: {
    fontSize: 14,
    color: colors.primary,
    fontWeight: '500',
  },
  emptyCards: {
    alignItems: 'center',
    paddingVertical: 32,
  },
  emptyCardsText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 12,
  },
  filterRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 16,
  },
  filterChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  filterChipActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  filterChipText: {
    fontSize: 11,
    fontWeight: 'bold',
    color: colors.textSecondary,
  },
  filterChipTextActive: {
    color: '#fff',
  },
  transactionCard: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
    marginBottom: 8,
  },
  transactionInfo: {
    flex: 1,
  },
  transactionType: {
    fontSize: 14,
    fontWeight: 'bold',
    color: colors.text,
  },
  transactionDate: {
    fontSize: 12,
    color: colors.textSecondary,
    marginTop: 4,
  },
  transactionAmount: {
    alignItems: 'flex-end',
  },
  amountText: {
    fontSize: 15,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 4,
  },
  loadMoreButton: {
    padding: 16,
    alignItems: 'center',
  },
  loadMoreText: {
    color: colors.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  emptyState: {
    padding: 32,
    alignItems: 'center',
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: 14,
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
