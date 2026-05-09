import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { settingsApi } from '../services/api';
import { FeeConfig } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useNavigation, DrawerActions } from '@react-navigation/native';

export default function FeesScreen() {
  const { colors } = useTheme();
  const navigation = useNavigation();
  const [fees, setFees] = useState<FeeConfig[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    fetchFees();
  }, []);

  const fetchFees = async () => {
    try {
      const response = await settingsApi.getFees();
      if (response.data.success) {
        setFees(response.data.data || []);
      }
    } catch (error) {
      console.error('Failed to fetch fees:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const formatFeeValue = (fee: FeeConfig) => {
    const { config_type, config, currency } = fee;
    switch (config_type) {
      case 'flat':
        return `${currency} ${(config.amount ?? 0).toLocaleString()}`;
      case 'percentage_cap':
        return `${config.percentage}% (Max ${currency} ${(config.cap ?? 0).toLocaleString()})`;
      case 'flat_conditional':
        if (config.conditions && config.conditions.length > 0) {
          const cond = config.conditions[0];
          return `${currency} ${cond.fee.toLocaleString()}`;
        }
        return 'Conditional';
      case 'range':
        if (config.ranges && config.ranges.length > 0) {
          const minFee = Math.min(...config.ranges.map(r => r.fee));
          const maxFee = Math.max(...config.ranges.map(r => r.fee));
          return `${currency} ${minFee.toLocaleString()} - ${currency} ${maxFee.toLocaleString()}`;
        }
        return 'Variable';
      default:
        return 'N/A';
    }
  };

  const formatFeeDescription = (fee: FeeConfig) => {
    const { config_type, config, currency } = fee;
    switch (config_type) {
      case 'range':
        return config.ranges?.map(r => 
          `${currency} ${r.min.toLocaleString()} - ${r.max >= 999999999 ? 'Above' : currency + ' ' + r.max.toLocaleString()}: ${currency} ${r.fee.toLocaleString()}`
        ).join('\n');
      case 'flat_conditional':
        return config.conditions?.map(c => 
          `A fee of ${currency} ${c.fee.toLocaleString()} applies for transactions ${c.operator} ${currency} ${c.threshold.toLocaleString()}`
        ).join('\n');
      case 'percentage_cap':
        return `A ${config.percentage}% fee applies, capped at ${currency} ${config.cap?.toLocaleString()}.`;
      case 'flat':
        return `A flat fee of ${currency} ${config.amount?.toLocaleString()} applies to all transactions.`;
      default:
        return '';
    }
  };

  const styles = createStyles(colors);

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  const renderFeeItem = ({ item }: { item: FeeConfig }) => (
    <View style={styles.feeCard}>
      <View style={styles.feeHeader}>
        <Text style={styles.feeName}>{item.name}</Text>
        <Text style={styles.feeAmount}>{formatFeeValue(item)}</Text>
      </View>
      <Text style={styles.feeDescription}>{formatFeeDescription(item)}</Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity 
          style={styles.menuButton}
          onPress={() => navigation.dispatch(DrawerActions.openDrawer())}
        >
          <Ionicons name="menu" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Applicable Fees</Text>
      </View>

      <FlatList
        data={fees}
        renderItem={renderFeeItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContent}
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Ionicons name="pricetag-outline" size={64} color={colors.textSecondary} />
            <Text style={styles.emptyText}>No fee information available at the moment.</Text>
          </View>
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
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    padding: 24,
    flexDirection: 'row',
    alignItems: 'center',
  },
  menuButton: {
    padding: 8,
    marginRight: 8,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
  },
  listContent: {
    padding: 24,
    paddingTop: 0,
  },
  feeCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 20,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  feeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  feeName: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.text,
  },
  feeAmount: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.primary,
  },
  feeDescription: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  emptyState: {
    alignItems: 'center',
    marginTop: 100,
  },
  emptyText: {
    fontSize: 16,
    color: colors.textSecondary,
    textAlign: 'center',
    marginTop: 16,
    paddingHorizontal: 40,
  },
});
