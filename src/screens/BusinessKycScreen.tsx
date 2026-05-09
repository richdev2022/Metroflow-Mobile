import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import * as DocumentPicker from 'expo-document-picker';
import { kycApi } from '../services/api';

export default function BusinessKycScreen() {
  const navigation = useNavigation();
  const [country, setCountry] = useState('');
  const [state, setState] = useState('');
  const [city, setCity] = useState('');
  const [street, setStreet] = useState('');
  const [houseNumber, setHouseNumber] = useState('');
  const [proofFile, setProofFile] = useState<{ uri: string; name: string; type: string } | null>(null);
  const [loading, setLoading] = useState(false);

  const handleUpload = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ['image/*', 'application/pdf'],
        copyToCacheDirectory: true,
      });
      if (!result.canceled && result.assets && result.assets[0]) {
        const asset = result.assets[0];
        setProofFile({
          uri: asset.uri,
          name: asset.name,
          type: asset.mimeType || 'application/octet-stream',
        });
        Alert.alert('Success', 'Document selected');
      }
    } catch (err) {
      Alert.alert('Error', 'Failed to pick file');
    }
  };

  const handleSubmit = async () => {
    if (!country || !state || !city || !street || !houseNumber || !proofFile) {
      Alert.alert('Error', 'Please fill all fields and upload proof of address');
      return;
    }

    setLoading(true);
    try {
      const formData = new FormData();
      formData.append('country', country);
      formData.append('state', state);
      formData.append('city', city);
      formData.append('street', street);
      formData.append('house_number', houseNumber);
      formData.append('proof_of_address', {
        uri: proofFile.uri,
        name: proofFile.name,
        type: proofFile.type,
      } as any);

      const response = await kycApi.submitBusiness(formData);
      if (response.data.success) {
        Alert.alert(
          'Submitted!',
          response.data.message || 'Your business KYC has been submitted for review.',
          [{ text: 'OK', onPress: () => navigation.goBack() }]
        );
      } else {
        Alert.alert('Error', response.data.message || 'Submission failed');
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to submit KYC');
    } finally {
      setLoading(false);
    }
  };

  return (
    <ScrollView style={styles.container}>
      <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
        <Text style={styles.backButtonText}>← Back</Text>
      </TouchableOpacity>
      
      <Text style={styles.title}>Business KYC Verification</Text>
      <Text style={styles.subtitle}>
        Provide your business address and proof of address document
      </Text>
      
      <View style={styles.form}>
        <Text style={styles.label}>Country</Text>
        <TextInput
          style={styles.input}
          placeholder="Nigeria"
          value={country}
          onChangeText={setCountry}
        />
        
        <Text style={styles.label}>State</Text>
        <TextInput
          style={styles.input}
          placeholder="Lagos"
          value={state}
          onChangeText={setState}
        />
        
        <Text style={styles.label}>City</Text>
        <TextInput
          style={styles.input}
          placeholder="Lagos"
          value={city}
          onChangeText={setCity}
        />
        
        <Text style={styles.label}>Street</Text>
        <TextInput
          style={styles.input}
          placeholder="Adeola Odeku Street"
          value={street}
          onChangeText={setStreet}
        />
        
        <Text style={styles.label}>House Number</Text>
        <TextInput
          style={styles.input}
          placeholder="123"
          value={houseNumber}
          onChangeText={setHouseNumber}
        />
        
        <TouchableOpacity style={styles.uploadButton} onPress={handleUpload}>
          <Text style={styles.uploadButtonText}>
            {proofFile ? `📄 ${proofFile.name}` : 'Upload Proof of Address'}
          </Text>
          {proofFile ? (
            <Text style={styles.uploadSubtext}>Tap to change file</Text>
          ) : (
            <Text style={styles.uploadSubtext}>(Utility Bill or Bank Statement)</Text>
          )}
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.button} onPress={handleSubmit} disabled={loading}>
          <Text style={styles.buttonText}>{loading ? 'Submitting...' : 'Submit for Review'}</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    padding: 24,
  },
  backButton: {
    marginBottom: 24,
  },
  backButtonText: {
    color: '#1e40af',
    fontSize: 16,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 8,
    color: '#1e40af',
  },
  subtitle: {
    fontSize: 16,
    color: '#6b7280',
    marginBottom: 32,
    lineHeight: 24,
  },
  form: {
    gap: 16,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    color: '#374151',
    marginBottom: 4,
  },
  input: {
    borderWidth: 1,
    borderColor: '#d1d5db',
    borderRadius: 8,
    padding: 16,
    fontSize: 16,
  },
  uploadButton: {
    borderWidth: 2,
    borderColor: '#1e40af',
    borderStyle: 'dashed',
    borderRadius: 12,
    padding: 24,
    alignItems: 'center',
  },
  uploadButtonText: {
    color: '#1e40af',
    fontSize: 16,
    fontWeight: '600',
  },
  uploadSubtext: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 4,
  },
  button: {
    backgroundColor: '#1e40af',
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
