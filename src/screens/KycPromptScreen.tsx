import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { useTheme } from '../theme/ThemeContext';
import { kycApi } from '../services/api';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

type KycPromptScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'KycPrompt'>;

export default function KycPromptScreen() {
  const navigation = useNavigation<KycPromptScreenNavigationProp>();
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(true);
  const [kycStatus, setKycStatus] = useState<any>(null);

  useEffect(() => {
    fetchStatus();
  }, []);

  const fetchStatus = async () => {
    try {
      const res = await kycApi.getStatus();
      setKycStatus(res.data.user);
    } catch (error) {
      console.error('Failed to fetch KYC status:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const styles = createStyles(colors);

  if (isLoading) {
    return (
      <View style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  const bvnVerified = kycStatus?.bvnStatus === 'verified';
  const ninVerified = kycStatus?.ninStatus === 'verified';

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Identity Verification</Text>
      </View>
      
      <Text style={styles.subtitle}>
        {bvnVerified || ninVerified 
          ? "Verify your remaining identity document to upgrade to Tier 2." 
          : "Complete KYC verification to access your wallet and all features."}
      </Text>
      
      <View style={styles.optionsContainer}>
        <TouchableOpacity 
          style={[styles.optionCard, bvnVerified && styles.optionVerified]}
          onPress={() => !bvnVerified && navigation.navigate('KycInitiate', { type: 'bvn' })}
          disabled={bvnVerified}
        >
          <View style={styles.optionInfo}>
            <Text style={[styles.optionTitle, bvnVerified && styles.textDisabled]}>Verify with BVN</Text>
            <Text style={styles.optionDesc}>Bank Verification Number</Text>
          </View>
          {bvnVerified ? (
            <Ionicons name="checkmark-circle" size={24} color={colors.success} />
          ) : (
            <Ionicons name="chevron-forward" size={24} color={colors.textSecondary} />
          )}
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={[styles.optionCard, ninVerified && styles.optionVerified]}
          onPress={() => !ninVerified && navigation.navigate('KycInitiate', { type: 'nin' })}
          disabled={ninVerified}
        >
          <View style={styles.optionInfo}>
            <Text style={[styles.optionTitle, ninVerified && styles.textDisabled]}>Verify with NIN</Text>
            <Text style={styles.optionDesc}>National Identification Number</Text>
          </View>
          {ninVerified ? (
            <Ionicons name="checkmark-circle" size={24} color={colors.success} />
          ) : (
            <Ionicons name="chevron-forward" size={24} color={colors.textSecondary} />
          )}
        </TouchableOpacity>
      </View>

      {(bvnVerified && ninVerified) && (
        <TouchableOpacity 
          style={styles.doneButton}
          onPress={() => navigation.reset({ index: 0, routes: [{ name: 'Main' }] })}
        >
          <LinearGradient
            colors={[colors.primary, colors.primaryLight]}
            style={styles.gradientButton}
          >
            <Text style={styles.doneButtonText}>Continue to Home</Text>
          </LinearGradient>
        </TouchableOpacity>
      )}
    </View>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: colors.background,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
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
  optionsContainer: {
    gap: 16,
  },
  optionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    padding: 24,
    justifyContent: 'space-between',
  },
  optionVerified: {
    backgroundColor: colors.success + '10',
    borderColor: colors.success,
  },
  optionInfo: {
    flex: 1,
  },
  optionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 4,
  },
  optionDesc: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  textDisabled: {
    color: colors.textSecondary,
  },
  doneButton: {
    marginTop: 'auto',
    borderRadius: 16,
    overflow: 'hidden',
    marginBottom: 20,
  },
  gradientButton: {
    padding: 18,
    alignItems: 'center',
  },
  doneButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
