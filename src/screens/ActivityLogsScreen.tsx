import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { activityLogsApi } from '../services/api';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useNavigation } from '@react-navigation/native';

interface ActivityLog {
  id: string;
  businessId: string;
  taskId: string | null;
  userId: string;
  action: string;
  actionType: string;
  description: string;
  metadata: any;
  createdAt: string;
  userName: string;
  taskTitle: string | null;
}

export default function ActivityLogsScreen() {
  const { colors } = useTheme();
  const navigation = useNavigation();
  const [logs, setLogs] = useState<ActivityLog[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);

  useEffect(() => {
    fetchLogs(1, true);
  }, []);

  const fetchLogs = async (pageNumber: number, refresh = false) => {
    try {
      if (!refresh && !hasMore) return;
      
      if (refresh) {
        setIsRefreshing(true);
      } else {
        setIsLoadingMore(true);
      }

      const response = await activityLogsApi.getLogs(pageNumber, 20);
      if (response.data.success) {
        const newLogs = response.data.data.logs;
        if (refresh) {
          setLogs(newLogs);
        } else {
          setLogs(prev => [...prev, ...newLogs]);
        }
        setHasMore(newLogs.length === 20);
        setPage(pageNumber);
      }
    } catch (error) {
      console.error('Failed to fetch logs:', error);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
      setIsLoadingMore(false);
    }
  };

  const onRefresh = () => {
    fetchLogs(1, true);
  };

  const loadMore = () => {
    if (!isLoadingMore && hasMore) {
      fetchLogs(page + 1);
    }
  };

  const getActionIcon = (actionType: string) => {
    const type = actionType.toLowerCase();
    if (type.includes('task')) return 'list';
    if (type.includes('wallet') || type.includes('transfer')) return 'wallet';
    if (type.includes('user') || type.includes('team')) return 'people';
    if (type.includes('auth') || type.includes('login')) return 'lock-closed';
    return 'flash';
  };

  const styles = createStyles(colors);

  const renderItem = ({ item }: { item: ActivityLog }) => (
    <View style={styles.logCard}>
      <View style={styles.logIconContainer}>
        <Ionicons name={getActionIcon(item.actionType)} size={20} color={colors.primary} />
      </View>
      <View style={styles.logContent}>
        <View style={styles.logHeaderRow}>
          <Text style={styles.logAction}>{item.action.toUpperCase()}</Text>
          <Text style={styles.logDate}>
            {new Date(item.createdAt).toLocaleString([], { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
          </Text>
        </View>
        <Text style={styles.logDescription}>{item.description}</Text>
        {item.taskTitle && (
          <View style={styles.taskTag}>
            <Ionicons name="document-text-outline" size={12} color={colors.textSecondary} />
            <Text style={styles.taskTagText}>{item.taskTitle}</Text>
          </View>
        )}
        <View style={styles.logFooter}>
          <Text style={styles.logUser}>By {item.userName}</Text>
        </View>
      </View>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Activity Logs</Text>
      </View>

      <FlatList
        data={logs}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        onRefresh={onRefresh}
        refreshing={isRefreshing}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        ListFooterComponent={() => (
          isLoadingMore ? <ActivityIndicator style={{ margin: 16 }} color={colors.primary} /> : null
        )}
        ListEmptyComponent={
          !isLoading ? (
            <View style={styles.emptyState}>
              <Ionicons name="receipt-outline" size={64} color={colors.textSecondary} />
              <Text style={styles.emptyText}>No activities recorded yet</Text>
            </View>
          ) : null
        }
      />
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    padding: 24,
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    marginRight: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 24,
  },
  logCard: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  logIconContainer: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.primary + '10',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  logContent: {
    flex: 1,
  },
  logHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
  },
  logAction: {
    fontSize: 12,
    fontWeight: 'bold',
    color: colors.primary,
    letterSpacing: 0.5,
  },
  logDate: {
    fontSize: 11,
    color: colors.textSecondary,
  },
  logDescription: {
    fontSize: 15,
    color: colors.text,
    lineHeight: 20,
    marginBottom: 8,
  },
  taskTag: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceVariant,
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    alignSelf: 'flex-start',
    marginBottom: 8,
    gap: 4,
  },
  taskTagText: {
    fontSize: 11,
    color: colors.textSecondary,
    fontWeight: '500',
  },
  logFooter: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
  },
  logUser: {
    fontSize: 12,
    color: colors.textSecondary,
    fontStyle: 'italic',
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
