import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { walletApi } from '../services/api';
import { useTheme } from '../theme/ThemeContext';

export default function CreateBusinessWalletScreen() {
  const navigation = useNavigation();
  const { colors } = useTheme();
  const [businessName, setBusinessName] = useState('');
  const [gtbAccountNumber, setGtbAccountNumber] = useState('');
  const [kycReferenceId, setKycReferenceId] = useState('');
  const [loading, setLoading] = useState(false);

  const handleCreate = async () => {
    if (!businessName || !gtbAccountNumber) {
      Alert.alert('Error', 'Please fill in all required fields');
      return;
    }

    setLoading(true);
    try {
      const response = await walletApi.createBusiness(gtbAccountNumber, businessName, kycReferenceId || undefined);
      if (response.data.success) {
        Alert.alert(
          'Success',
          response.data.message || 'Business wallet created successfully',
          [{ text: 'OK', onPress: () => navigation.goBack() }]
        );
      } else {
        Alert.alert('Error', response.data.message || 'Failed to create business wallet');
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to create business wallet');
    } finally {
      setLoading(false);
    }
  };

  const styles = createStyles(colors);

  return (
    <ScrollView style={styles.container}>
      <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
        <Text style={styles.backButtonText}>← Back</Text>
      </TouchableOpacity>
      
      <Text style={styles.title}>Create Business Wallet</Text>
      <Text style={styles.subtitle}>
        Your business KYC has been approved! Now set up your business wallet.
      </Text>
      
      <View style={styles.form}>
        <Text style={styles.label}>Business Name</Text>
        <TextInput
          style={styles.input}
          placeholder="My Company Limited"
          value={businessName}
          onChangeText={setBusinessName}
        />
        
        <Text style={styles.label}>GTBank Account Number</Text>
        <Text style={styles.hint}>For settlement and compliance purposes</Text>
        <TextInput
          style={styles.input}
          placeholder="0123456789"
          value={gtbAccountNumber}
          onChangeText={setGtbAccountNumber}
          keyboardType="numeric"
          maxLength={10}
        />
        
        <Text style={styles.label}>KYC Reference ID (Optional)</Text>
        <TextInput
          style={styles.input}
          placeholder="KYC Ref ID if provided"
          value={kycReferenceId}
          onChangeText={setKycReferenceId}
        />
        
        <TouchableOpacity 
          style={[styles.button, (!businessName || !gtbAccountNumber) && styles.buttonDisabled]} 
          onPress={handleCreate}
          disabled={!businessName || !gtbAccountNumber || loading}
        >
          {loading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Create Business Wallet</Text>
          )}
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
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
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 8,
    color: colors.text,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
    marginBottom: 32,
    lineHeight: 24,
  },
  form: {
    gap: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 4,
  },
  hint: {
    fontSize: 12,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    padding: 16,
    fontSize: 16,
    backgroundColor: colors.surface,
    color: colors.text,
  },
  button: {
    backgroundColor: colors.primary,
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});