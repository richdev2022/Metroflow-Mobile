import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Share, Alert, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { RootStackParamList } from '../navigation';
import { useTheme } from '../theme/ThemeContext';
import { ideasApi } from '../services/api';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

type IdeaDetailRouteProp = RouteProp<RootStackParamList, 'IdeaDetail'>;

export default function IdeaDetailScreen() {
  const { colors } = useTheme();
  const navigation = useNavigation();
  const route = useRoute<IdeaDetailRouteProp>();
  const { idea } = route.params;
  
  const [isGeneratingDoc, setIsGeneratingDoc] = useState(false);
  const [docs, setDocs] = useState<any[]>([]);
  const [isLoadingDocs, setIsLoadingDocs] = useState(false);

  React.useEffect(() => {
    fetchDocumentation();
  }, []);

  const fetchDocumentation = async () => {
    setIsLoadingDocs(true);
    try {
      const response = await ideasApi.getDocumentation(idea.id);
      if (response.data.success) {
        setDocs(response.data.data || []);
      }
    } catch (error) {
      console.error('Failed to fetch documentation:', error);
    } finally {
      setIsLoadingDocs(false);
    }
  };

  const handleGenerateDoc = async () => {
    setIsGeneratingDoc(true);
    try {
      const response = await ideasApi.generateDocumentation(idea.id);
      if (response.data.success) {
        Alert.alert('Success', 'Documentation generated successfully!');
        fetchDocumentation();
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to generate documentation');
    } finally {
      setIsGeneratingDoc(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'executed': return colors.success;
      case 'under_review': return colors.warning;
      case 'rejected': return colors.error;
      default: return colors.textSecondary;
    }
  };

  const styles = createStyles(colors);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle} numberOfLines={1}>Idea Details</Text>
        <TouchableOpacity 
          style={styles.shareButton}
          onPress={() => Share.share({ 
            title: idea.title, 
            message: `${idea.title}\n\n${idea.description}\n\nStatus: ${idea.status.toUpperCase()}` 
          })}
        >
          <Ionicons name="share-social-outline" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        <View style={styles.card}>
          <View style={styles.ideaHeader}>
            <View style={[styles.statusBadge, { backgroundColor: getStatusColor(idea.status) + '20' }]}>
              <Text style={[styles.statusText, { color: getStatusColor(idea.status) }]}>
                {idea.status.replace('_', ' ').toUpperCase()}
              </Text>
            </View>
            <Text style={styles.dateText}>{new Date(idea.createdAt).toLocaleDateString()}</Text>
          </View>
          
          <Text style={styles.title}>{idea.title}</Text>
          <Text style={styles.description}>{idea.description}</Text>
          
          <View style={styles.footer}>
            <View style={styles.authorContainer}>
              <View style={[styles.avatar, { backgroundColor: colors.primary + '20' }]}>
                <Text style={[styles.avatarText, { color: colors.primary }]}>
                  {idea.userName?.charAt(0).toUpperCase() || 'A'}
                </Text>
              </View>
              <Text style={styles.authorName}>By {idea.userName || 'Anonymous'}</Text>
            </View>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Product Documentation</Text>
          
          {isLoadingDocs ? (
            <ActivityIndicator style={styles.loader} color={colors.primary} />
          ) : docs.length > 0 ? (
            docs.map((doc, index) => (
              <View key={doc.id || index} style={styles.docCard}>
                <Text style={styles.docTitle}>{doc.title}</Text>
                <Text style={styles.docContent}>{doc.content}</Text>
                <View style={styles.docFooter}>
                  <Text style={styles.docMeta}>
                    Generated: {new Date(doc.createdAt).toLocaleDateString()}
                  </Text>
                  <TouchableOpacity onPress={() => Share.share({ title: doc.title, message: doc.content })}>
                    <Ionicons name="share-outline" size={20} color={colors.primary} />
                  </TouchableOpacity>
                </View>
              </View>
            ))
          ) : (
            <View style={styles.emptyDoc}>
              <Ionicons name="document-text-outline" size={48} color={colors.textSecondary} />
              <Text style={styles.emptyText}>No documentation yet.</Text>
            </View>
          )}

          <TouchableOpacity 
            style={[styles.generateButton, isGeneratingDoc && styles.disabledButton]}
            onPress={handleGenerateDoc}
            disabled={isGeneratingDoc}
          >
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.gradientButton}
            >
              {isGeneratingDoc ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <>
                  <Ionicons name="flash-outline" size={20} color="#fff" style={{ marginRight: 8 }} />
                  <Text style={styles.generateButtonText}>
                    {docs.length > 0 ? 'Regenerate with AI' : 'Generate with AI'}
                  </Text>
                </>
              )}
            </LinearGradient>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 24,
    backgroundColor: colors.background,
  },
  backButton: {
    marginRight: 16,
  },
  headerTitle: {
    flex: 1,
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.text,
  },
  shareButton: {
    padding: 4,
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: 24,
    padding: 24,
    marginBottom: 24,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.05,
    shadowRadius: 12,
    elevation: 5,
  },
  ideaHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  statusBadge: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
  },
  statusText: {
    fontSize: 11,
    fontWeight: 'bold',
  },
  dateText: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 16,
    lineHeight: 32,
  },
  description: {
    fontSize: 16,
    color: colors.textSecondary,
    lineHeight: 26,
    marginBottom: 24,
  },
  footer: {
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingTop: 16,
  },
  authorContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  avatarText: {
    fontSize: 14,
    fontWeight: 'bold',
  },
  authorName: {
    fontSize: 14,
    color: colors.text,
    fontWeight: '600',
  },
  section: {
    marginBottom: 40,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 16,
  },
  docCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 20,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  docTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 12,
  },
  docContent: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 22,
    marginBottom: 16,
  },
  docFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingTop: 12,
  },
  docMeta: {
    fontSize: 11,
    color: colors.textSecondary,
  },
  emptyDoc: {
    alignItems: 'center',
    paddingVertical: 40,
    backgroundColor: colors.surface,
    borderRadius: 20,
    marginBottom: 16,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: colors.border,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 12,
  },
  loader: {
    marginVertical: 40,
  },
  generateButton: {
    borderRadius: 16,
    overflow: 'hidden',
    marginTop: 8,
  },
  gradientButton: {
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  generateButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  disabledButton: {
    opacity: 0.7,
  },
});
