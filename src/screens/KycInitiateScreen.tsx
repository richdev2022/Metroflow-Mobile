import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator } from 'react-native';
import { useNavigation, useRoute } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { RouteProp } from '@react-navigation/native';
import { kycApi } from '../services/api';
import { useTheme } from '../theme/ThemeContext';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

type KycInitiateScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'KycInitiate'>;
type KycInitiateScreenRouteProp = RouteProp<RootStackParamList, 'KycInitiate'>;

export default function KycInitiateScreen() {
  const navigation = useNavigation<KycInitiateScreenNavigationProp>();
  const route = useRoute<KycInitiateScreenRouteProp>();
  const { colors } = useTheme();
  const { type } = route.params;
  const [number, setNumber] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async () => {
    if (!number || (type === 'bvn' && number.length !== 11) || (type === 'nin' && number.length !== 11)) {
      Alert.alert('Error', `Please enter a valid ${type === 'bvn' ? '11-digit BVN' : '11-digit NIN'}`);
      return;
    }

    setLoading(true);
    try {
      await kycApi.initiate(type, number);
      navigation.navigate('KycOtp');
    } catch (error: any) {
      // Toast handles error display
    } finally {
      setLoading(false);
    }
  };

  const styles = createStyles(colors);

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>{type.toUpperCase()} Verification</Text>
      </View>
      
      <Text style={styles.subtitle}>
        Please enter your {type === 'bvn' ? '11-digit Bank Verification Number' : '11-digit National Identification Number'} to verify your identity.
      </Text>
      
      <View style={styles.inputContainer}>
        <Ionicons name="document-text-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
        <TextInput
          style={styles.input}
          placeholder={type === 'bvn' ? 'Enter 11-digit BVN' : 'Enter 11-digit NIN'}
          value={number}
          onChangeText={setNumber}
          keyboardType="numeric"
          maxLength={11}
          placeholderTextColor={colors.textSecondary}
        />
      </View>
      
      <TouchableOpacity 
        style={[styles.buttonContainer, (!number || loading) && styles.buttonDisabled]} 
        onPress={handleSubmit}
        disabled={!number || loading}
      >
        <LinearGradient
          colors={['#2563eb', '#3b82f6']}
          style={styles.button}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 0 }}
        >
          {loading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Send Verification Code</Text>
          )}
        </LinearGradient>
      </TouchableOpacity>
    </View>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: colors.background,
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
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    paddingHorizontal: 16,
    marginBottom: 40,
  },
  inputIcon: {
    marginRight: 12,
  },
  input: {
    flex: 1,
    paddingVertical: 18,
    fontSize: 18,
    color: colors.text,
    letterSpacing: 1,
  },
  buttonContainer: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#2563eb',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
  },
  button: {
    padding: 18,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
