import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator, Alert, Share, TextInput, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Transfer } from '../types';
import { useTheme } from '../theme/ThemeContext';
import { transfersApi, subscriptionApi } from '../services/api';
import Ionicons from '@expo/vector-icons/Ionicons';

type FilterStatus = 'all' | 'pending' | 'success' | 'failed';

export default function TransfersScreen() {
  const navigation = useNavigation();
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [transfers, setTransfers] = useState<Transfer[]>([]);
  const [filterStatus, setFilterStatus] = useState<FilterStatus>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);

  const styles = createStyles(colors);

  useEffect(() => {
    fetchTransfers(1, true);
  }, [filterStatus, searchQuery]);

  const fetchTransfers = async (pageNumber: number, refresh = false) => {
    try {
      if (!refresh && !hasMore) return;
      
      if (refresh) {
        setIsRefreshing(true);
      } else if (pageNumber > 1) {
        setIsLoadingMore(true);
      } else {
        setIsLoading(true);
      }

      const params: any = {
        page: pageNumber,
        limit: 20,
      };
      if (filterStatus !== 'all') params.status = filterStatus;
      if (searchQuery) params.search = searchQuery;

      const response = await transfersApi.getTransfers(params);
      if (response.data.success) {
        const newTransfers = response.data.data || [];
        if (refresh) {
          setTransfers(newTransfers);
        } else {
          setTransfers(prev => [...prev, ...newTransfers]);
        }
        setHasMore(newTransfers.length === 20);
        setPage(pageNumber);
      }
    } catch (error) {
      console.error('Failed to fetch transfers:', error);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
      setIsLoadingMore(false);
    }
  };

  const handleRefresh = () => {
    fetchTransfers(1, true);
  };

  const loadMore = () => {
    if (!isLoadingMore && hasMore) {
      fetchTransfers(page + 1);
    }
  };

  const handleRetryTransfer = async (id: string) => {
    try {
      await transfersApi.retryTransfer(id);
      Alert.alert('Success', 'Transfer retry initiated');
      handleRefresh();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to retry transfer');
    }
  };

  const exportToCSV = async () => {
    setIsLoading(true);
    try {
      const params: any = {};
      if (filterStatus !== 'all') params.status = filterStatus;

      const response = await subscriptionApi.exportTransactions(params);
      
      if (response.data) {
        await Share.share({
          title: 'Transfer History',
          message: response.data,
        });
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to export transfers');
    } finally {
      setIsLoading(false);
    }
  };

  const renderItem = ({ item: transfer }: { item: Transfer }) => (
    <View key={transfer.id} style={styles.transferCard}>
      <View style={styles.transferHeader}>
        <Text style={styles.recipientName}>{transfer.recipient_name}</Text>
        <View style={[
          styles.statusBadge,
          transfer.status === 'success' && styles.successBadge,
          transfer.status === 'pending' && styles.pendingBadge,
          transfer.status === 'failed' && styles.failedBadge,
        ]}>
          <Text style={[
            styles.statusText,
            transfer.status === 'success' && styles.successText,
            transfer.status === 'pending' && styles.pendingText,
            transfer.status === 'failed' && styles.failedText,
          ]}>{transfer.status.toUpperCase()}</Text>
        </View>
      </View>
      <View style={styles.transferFooter}>
        <View>
          <Text style={styles.transferAmount}>
            {transfer.currency} {transfer.amount.toLocaleString()}
          </Text>
          <Text style={styles.transferDate}>
            {new Date(transfer.created_at).toLocaleString()}
          </Text>
        </View>
      </View>
      {transfer.status === 'failed' && (
        <View style={styles.failureContainer}>
          <Text style={styles.failureReason}>{transfer.failure_reason}</Text>
          <TouchableOpacity 
            style={styles.retryButton}
            onPress={() => handleRetryTransfer(transfer.id)}
          >
            <Text style={styles.retryButtonText}>Retry</Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Transfers</Text>
        <TouchableOpacity 
          style={styles.exportButton}
          onPress={exportToCSV}
        >
          <Ionicons name="download-outline" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      <View style={styles.searchSection}>
        <View style={styles.searchInputContainer}>
          <Ionicons name="search-outline" size={20} color={colors.textSecondary} />
          <TextInput
            style={styles.searchInput}
            placeholder="Search transfers..."
            placeholderTextColor={colors.textSecondary}
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
        </View>
      </View>

      <View style={styles.tabs}>
        {(['all', 'pending', 'success', 'failed'] as FilterStatus[]).map((status) => (
          <TouchableOpacity 
            key={status}
            style={[styles.tab, filterStatus === status && styles.activeTab]}
            onPress={() => setFilterStatus(status)}
          >
            <Text style={[styles.tabText, filterStatus === status && styles.activeTabText]}>
              {status.charAt(0).toUpperCase() + status.slice(1)}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      <FlatList
        data={transfers}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.transfersList}
        onRefresh={handleRefresh}
        refreshing={isRefreshing}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        ListFooterComponent={() => (
          isLoadingMore ? <ActivityIndicator style={{ margin: 16 }} color={colors.primary} /> : null
        )}
        ListEmptyComponent={
          !isLoading ? (
            <View style={styles.emptyState}>
              <Ionicons name="swap-horizontal-outline" size={64} color={colors.textSecondary} />
              <Text style={styles.emptyText}>No transfers found</Text>
            </View>
          ) : (
            <View style={styles.center}>
              <ActivityIndicator size="large" color={colors.primary} style={{ marginTop: 50 }} />
            </View>
          )
        }
      />
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.surfaceVariant,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 24,
    backgroundColor: colors.surface,
  },
  backButton: {
    marginRight: 16,
  },
  headerTitle: {
    flex: 1,
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  exportButton: {
    padding: 8,
  },
  searchSection: {
    paddingHorizontal: 16,
    paddingBottom: 12,
    backgroundColor: colors.surface,
  },
  searchInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceVariant,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    color: colors.text,
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
    gap: 8,
  },
  tab: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  activeTab: {
    backgroundColor: colors.primary,
  },
  tabText: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  activeTabText: {
    color: '#fff',
    fontWeight: '600',
  },
  transfersList: {
    padding: 16,
  },
  transferCard: {
    backgroundColor: colors.surface,
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  transferHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  recipientName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  successBadge: {
    backgroundColor: colors.success + '20',
  },
  pendingBadge: {
    backgroundColor: colors.warning + '20',
  },
  failedBadge: {
    backgroundColor: colors.error + '20',
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
  },
  successText: {
    color: colors.success,
  },
  pendingText: {
    color: colors.warning,
  },
  failedText: {
    color: colors.error,
  },
  transferFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  transferAmount: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.primary,
  },
  transferDate: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  failureContainer: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  failureReason: {
    fontSize: 14,
    color: colors.error,
    flex: 1,
  },
  retryButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
  },
  retryButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  emptyState: {
    alignItems: 'center',
    marginTop: 100,
  },
  emptyText: {
    fontSize: 16,
    color: colors.textSecondary,
    marginTop: 16,
  },
});
