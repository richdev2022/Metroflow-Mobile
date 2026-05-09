import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, TextInput, Alert, Modal, Share } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { ideasApi } from '../services/api';
import { Idea } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useNavigation } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';

interface Documentation {
  id: string;
  title: string;
  content: string;
  createdAt: string;
}

export default function IdeasScreen() {
  const { colors } = useTheme();
  const navigation = useNavigation();
  const [ideas, setIdeas] = useState<Idea[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isModalVisible, setIsModalVisible] = useState(false);
  const [newIdea, setNewIdea] = useState({ title: '', description: '' });
  const [isSubmitting, setIsSubmitting] = useState(false);
  
  const [selectedIdea, setSelectedIdea] = useState<Idea | null>(null);
  const [showDocModal, setShowDocModal] = useState(false);
  const [docs, setDocs] = useState<Documentation[]>([]);
  const [isGeneratingDoc, setIsGeneratingDoc] = useState(false);
  const [isFetchingDocs, setIsFetchingDocs] = useState(false);

  useEffect(() => {
    fetchIdeas();
  }, []);

  const fetchIdeas = async () => {
    try {
      const response = await ideasApi.getIdeas();
      if (response.data.success) {
        setIdeas(response.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch ideas:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCreateIdea = async () => {
    if (!newIdea.title || !newIdea.description) {
      Alert.alert('Error', 'Please fill all fields');
      return;
    }

    setIsSubmitting(true);
    try {
      const response = await ideasApi.createIdea(newIdea);
      if (response.data.success) {
        setIsModalVisible(false);
        setNewIdea({ title: '', description: '' });
        fetchIdeas();
      }
    } catch (error) {
      // Toast handles it
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleOpenDocumentation = async (idea: Idea) => {
    setSelectedIdea(idea);
    setShowDocModal(true);
    setIsFetchingDocs(true);
    try {
      const response = await ideasApi.getDocumentation(idea.id);
      if (response.data.success) {
        setDocs(response.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch documentation:', error);
    } finally {
      setIsFetchingDocs(false);
    }
  };

  const handleGenerateDocumentation = async () => {
    if (!selectedIdea) return;
    setIsGeneratingDoc(true);
    try {
      const response = await ideasApi.generateDocumentation(selectedIdea.id);
      if (response.data.success) {
        handleOpenDocumentation(selectedIdea);
      }
    } catch (error) {
      // Toast handles it
    } finally {
      setIsGeneratingDoc(false);
    }
  };

  const getStatusColor = (status: Idea['status']) => {
    switch (status) {
      case 'executed': return colors.success;
      case 'under_review': return colors.warning;
      case 'rejected': return colors.error;
      default: return colors.textSecondary;
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

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Ideas</Text>
        <TouchableOpacity style={styles.addButton} onPress={() => setIsModalVisible(true)}>
          <LinearGradient
            colors={[colors.primary, colors.primaryLight]}
            style={styles.addButtonGradient}
          >
            <Ionicons name="add" size={24} color="#fff" />
          </LinearGradient>
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
        {ideas.map((idea) => (
          <View key={idea.id} style={styles.ideaCard}>
            <View style={styles.ideaHeader}>
              <Text style={styles.ideaTitle}>{idea.title}</Text>
              <View style={[styles.statusBadge, { backgroundColor: getStatusColor(idea.status) + '20' }]}>
                <Text style={[styles.statusText, { color: getStatusColor(idea.status) }]}>
                  {idea.status.replace('_', ' ').toUpperCase()}
                </Text>
              </View>
            </View>
            <Text style={styles.ideaDescription}>{idea.description}</Text>
            
            <TouchableOpacity 
              style={styles.docButton}
              onPress={() => handleOpenDocumentation(idea)}
            >
              <Ionicons name="document-text-outline" size={16} color={colors.primary} />
              <Text style={styles.docButtonText}>Product Documentation</Text>
            </TouchableOpacity>

            <View style={styles.ideaFooter}>
              <Text style={styles.ideaMeta}>By {idea.userName || 'Anonymous'}</Text>
              <Text style={styles.ideaMeta}>{new Date(idea.createdAt).toLocaleDateString()}</Text>
            </View>
          </View>
        ))}
        {ideas.length === 0 && (
          <View style={styles.emptyState}>
            <Ionicons name="bulb-outline" size={64} color={colors.textSecondary} />
            <Text style={styles.emptyText}>No ideas yet. Be the first to suggest one!</Text>
          </View>
        )}
      </ScrollView>

      {/* Suggest Idea Modal */}
      <Modal visible={isModalVisible} animationType="slide" transparent={true}>
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Suggest an Idea</Text>
              <TouchableOpacity onPress={() => setIsModalVisible(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <TextInput
              style={styles.input}
              placeholder="Title"
              placeholderTextColor={colors.textSecondary}
              value={newIdea.title}
              onChangeText={(text) => setNewIdea({ ...newIdea, title: text })}
            />
            <TextInput
              style={[styles.input, styles.textArea]}
              placeholder="Description"
              placeholderTextColor={colors.textSecondary}
              value={newIdea.description}
              onChangeText={(text) => setNewIdea({ ...newIdea, description: text })}
              multiline
              numberOfLines={4}
            />

            <TouchableOpacity 
              style={[styles.submitButton, isSubmitting && styles.submitButtonDisabled]}
              onPress={handleCreateIdea}
              disabled={isSubmitting}
            >
              <LinearGradient
                colors={[colors.primary, colors.primaryLight]}
                style={styles.gradientButton}
              >
                {isSubmitting ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.submitButtonText}>Submit Idea</Text>
                )}
              </LinearGradient>
            </TouchableOpacity>
          </View>
        </View>
      </Modal>

      {/* Documentation Modal */}
      <Modal visible={showDocModal} animationType="slide" transparent={true}>
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, { height: '90%' }]}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>Documentation</Text>
                <Text style={styles.modalSubtitle}>{selectedIdea?.title}</Text>
              </View>
              <TouchableOpacity onPress={() => setShowDocModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            {isFetchingDocs ? (
              <ActivityIndicator style={{ marginTop: 40 }} color={colors.primary} />
            ) : (
              <ScrollView showsVerticalScrollIndicator={false}>
                {docs.length > 0 ? (
                  docs.map((doc) => (
                    <View key={doc.id} style={styles.docCard}>
                      <Text style={styles.docTitle}>{doc.title}</Text>
                      <Text style={styles.docContent}>{doc.content}</Text>
                      <View style={styles.docFooter}>
                        <Text style={styles.docMeta}>
                          Generated on {new Date(doc.createdAt).toLocaleDateString()}
                        </Text>
                        <TouchableOpacity 
                          onPress={() => Share.share({ title: doc.title, message: doc.content })}
                        >
                          <Ionicons name="share-outline" size={20} color={colors.primary} />
                        </TouchableOpacity>
                      </View>
                    </View>
                  ))
                ) : (
                  <View style={styles.emptyDocState}>
                    <Ionicons name="document-text-outline" size={64} color={colors.textSecondary} />
                    <Text style={styles.emptyText}>No documentation generated for this idea yet.</Text>
                  </View>
                )}
              </ScrollView>
            )}

            <TouchableOpacity 
              style={[styles.generateButton, isGeneratingDoc && styles.submitButtonDisabled]}
              onPress={handleGenerateDocumentation}
              disabled={isGeneratingDoc}
            >
              <LinearGradient
                colors={[colors.primary, colors.primaryLight]}
                style={styles.gradientButton}
              >
                {isGeneratingDoc ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.submitButtonText}>
                    {docs.length > 0 ? 'Regenerate Documentation' : 'Generate Documentation'}
                  </Text>
                )}
              </LinearGradient>
            </TouchableOpacity>
          </View>
        </View>
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 24,
  },
  backButton: {
    marginRight: 16,
  },
  title: {
    flex: 1,
    fontSize: 28,
    fontWeight: 'bold',
    color: colors.text,
  },
  addButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    overflow: 'hidden',
  },
  addButtonGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    flex: 1,
    paddingHorizontal: 24,
  },
  ideaCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 20,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.05,
    shadowRadius: 10,
    elevation: 4,
  },
  ideaHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 12,
  },
  ideaTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
    flex: 1,
    marginRight: 8,
  },
  statusBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusText: {
    fontSize: 10,
    fontWeight: 'bold',
  },
  ideaDescription: {
    fontSize: 15,
    color: colors.textSecondary,
    lineHeight: 22,
    marginBottom: 16,
  },
  docButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.primary + '10',
    padding: 12,
    borderRadius: 12,
    marginBottom: 16,
    gap: 8,
  },
  docButtonText: {
    color: colors.primary,
    fontWeight: '600',
    fontSize: 14,
  },
  ideaFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    borderTopWidth: 1,
    borderTopColor: colors.border,
    paddingTop: 12,
  },
  ideaMeta: {
    fontSize: 12,
    color: colors.textSecondary,
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
    minHeight: 450,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 24,
  },
  modalTitle: {
    fontSize: 22,
    fontWeight: 'bold',
    color: colors.text,
  },
  modalSubtitle: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 4,
  },
  input: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    fontSize: 16,
    color: colors.text,
    marginBottom: 16,
    borderWidth: 1.5,
    borderColor: colors.border,
  },
  textArea: {
    height: 150,
    textAlignVertical: 'top',
  },
  submitButton: {
    borderRadius: 16,
    overflow: 'hidden',
    marginTop: 8,
  },
  gradientButton: {
    padding: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  submitButtonDisabled: {
    opacity: 0.7,
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  docCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 20,
    marginBottom: 20,
    borderWidth: 1,
    borderColor: colors.border,
  },
  docTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 12,
  },
  docContent: {
    fontSize: 15,
    color: colors.textSecondary,
    lineHeight: 24,
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
    fontSize: 12,
    color: colors.textSecondary,
  },
  emptyDocState: {
    alignItems: 'center',
    paddingVertical: 60,
  },
  generateButton: {
    borderRadius: 16,
    overflow: 'hidden',
    marginTop: 16,
  },
});
