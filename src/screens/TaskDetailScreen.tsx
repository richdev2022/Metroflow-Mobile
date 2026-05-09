import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, TextInput, Alert, Image, KeyboardAvoidingView, Platform, Modal } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { useTheme } from '../theme/ThemeContext';
import { tasksApi, commentsApi, assignmentsApi, teamApi } from '../services/api';
import { Task, Comment, TeamMember } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';

type Props = NativeStackScreenProps<RootStackParamList, 'TaskDetail'>;

export default function TaskDetailScreen({ route, navigation }: Props) {
  const { taskId } = route.params;
  const { colors } = useTheme();
  const [task, setTask] = useState<Task | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [newComment, setNewComment] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSubmittingComment, setIsSubmittingComment] = useState(false);
  const [showAssignModal, setShowAssignModal] = useState(false);

  useEffect(() => {
    fetchTaskDetails();
    fetchTeamMembers();
  }, [taskId]);

  const fetchTaskDetails = async () => {
    try {
      const tasksResponse = await tasksApi.getTasks();
      if (tasksResponse.data.success) {
        const foundTask = tasksResponse.data.data.tasks.find((t: Task) => t.id === taskId);
        if (foundTask) {
          setTask(foundTask);
          const commentsResponse = await commentsApi.getComments(taskId);
          if (commentsResponse.data.success) {
            setComments(commentsResponse.data.data);
          }
        } else {
          Alert.alert('Error', 'Task not found');
          navigation.goBack();
        }
      }
    } catch (error) {
      console.error('Failed to fetch task details:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const fetchTeamMembers = async () => {
    try {
      const response = await teamApi.getTeam();
      if (response.data.success) {
        setTeamMembers(response.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch team members:', error);
    }
  };

  const handleToggleAssignment = async (userId: string) => {
    if (!task) return;
    
    const isAssigned = task.assignedTo?.includes(userId);
    
    try {
      if (isAssigned) {
        // Find assignment ID if available, otherwise use taskId and userId logic
        // For simplicity with the provided API, we might need a separate call or handle it differently
        // If we don't have assignment IDs, we might just re-assign the whole list
        const newUserIds = task.assignedTo?.filter(id => id !== userId) || [];
        await tasksApi.updateTask(taskId, { assignedTo: newUserIds });
        setTask({ ...task, assignedTo: newUserIds });
      } else {
        const newUserIds = [...(task.assignedTo || []), userId];
        await assignmentsApi.assignTasks({ taskIds: [taskId], userIds: [userId] });
        setTask({ ...task, assignedTo: newUserIds });
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to update assignment');
    }
  };

  const handleToggleReaction = async (commentId: string, type: 'like' | 'love' | 'laugh') => {
    try {
      await commentsApi.toggleReaction(commentId, type);
      // Refresh comments
      const response = await commentsApi.getComments(taskId);
      if (response.data.success) {
        setComments(response.data.data);
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to update reaction');
    }
  };

  const handleAddComment = async () => {
    if (!newComment.trim()) return;

    setIsSubmittingComment(true);
    try {
      const response = await commentsApi.addComment({
        taskId,
        content: newComment.trim(),
      });

      if (response.data.success) {
        setNewComment('');
        // Refresh comments
        const commentsResponse = await commentsApi.getComments(taskId);
        if (commentsResponse.data.success) {
          setComments(commentsResponse.data.data);
        }
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to add comment');
    } finally {
      setIsSubmittingComment(false);
    }
  };

  const handleUpdateStatus = async (status: Task['status']) => {
    if (!task) return;
    try {
      const response = await tasksApi.updateTask(task.id, { status });
      if (response.data.success) {
        setTask({ ...task, status });
      }
    } catch (error) {
      Alert.alert('Error', 'Failed to update status');
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return '#4CAF50';
      case 'in_progress': return '#FF9800';
      case 'pending': return '#9E9E9E';
      default: return '#9E9E9E';
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

  if (!task) return null;

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Task Details</Text>
        <TouchableOpacity onPress={() => {/* Edit task logic */}} style={styles.editButton}>
          <Ionicons name="create-outline" size={24} color={colors.text} />
        </TouchableOpacity>
      </View>

      <KeyboardAvoidingView 
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ flex: 1 }}
      >
        <ScrollView style={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.statusSection}>
            <View style={[styles.statusBadge, { backgroundColor: getStatusColor(task.status) + '20' }]}>
              <View style={[styles.statusDot, { backgroundColor: getStatusColor(task.status) }]} />
              <Text style={[styles.statusText, { color: getStatusColor(task.status) }]}>
                {task.status.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
              </Text>
            </View>
            {task.isOverdue && (
              <View style={styles.overdueBadge}>
                <Text style={styles.overdueText}>Overdue</Text>
              </View>
            )}
          </View>

          <Text style={styles.title}>{task.title}</Text>
          
          {task.description && (
            <Text style={styles.description}>{task.description}</Text>
          )}

          <View style={styles.metaGrid}>
            <View style={styles.metaItem}>
              <Ionicons name="calendar-outline" size={20} color={colors.textSecondary} />
              <View style={styles.metaContent}>
                <Text style={styles.metaLabel}>Due Date</Text>
                <Text style={styles.metaValue}>{new Date(task.endDate).toLocaleDateString()}</Text>
              </View>
            </View>
            <View style={styles.metaItem}>
              <Ionicons name="folder-outline" size={20} color={colors.textSecondary} />
              <View style={styles.metaContent}>
                <Text style={styles.metaLabel}>Epic</Text>
                <Text style={styles.metaValue}>{task.epic || 'No Epic'}</Text>
              </View>
            </View>
          </View>

          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>Assignees</Text>
              <TouchableOpacity onPress={() => setShowAssignModal(true)} style={styles.addAssigneeButton}>
                <Ionicons name="person-add-outline" size={20} color={colors.primary} />
              </TouchableOpacity>
            </View>
            <View style={styles.assigneeList}>
              {task.assignedTo?.map((userId, index) => {
                const member = teamMembers.find(m => m.id === userId);
                return (
                  <View key={index} style={styles.assigneeItem}>
                    <View style={styles.avatar}>
                      <Text style={styles.avatarText}>{(member?.name || userId).charAt(0).toUpperCase()}</Text>
                    </View>
                    <Text style={styles.assigneeName}>{member?.name || userId}</Text>
                  </View>
                );
              }) || <Text style={styles.emptyText}>No one assigned</Text>}
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Actions</Text>
            <View style={styles.actionButtons}>
              {task.status !== 'pending' && (
                <TouchableOpacity 
                  style={[styles.actionButton, styles.pendingAction]}
                  onPress={() => handleUpdateStatus('pending')}
                >
                  <Text style={styles.actionButtonText}>Set Pending</Text>
                </TouchableOpacity>
              )}
              {task.status !== 'in_progress' && (
                <TouchableOpacity 
                  style={[styles.actionButton, styles.inProgressAction]}
                  onPress={() => handleUpdateStatus('in_progress')}
                >
                  <Text style={styles.actionButtonText}>Set In Progress</Text>
                </TouchableOpacity>
              )}
              {task.status !== 'completed' && (
                <TouchableOpacity 
                  style={[styles.actionButton, styles.completedAction]}
                  onPress={() => handleUpdateStatus('completed')}
                >
                  <Text style={styles.actionButtonText}>Complete Task</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Comments ({comments.length})</Text>
            {comments.map((comment) => (
              <View key={comment.id} style={styles.commentItem}>
                <View style={styles.commentHeader}>
                  <View style={styles.commentAvatar}>
                    <Text style={styles.commentAvatarText}>
                      {(comment.userName || comment.userId).charAt(0).toUpperCase()}
                    </Text>
                  </View>
                  <View style={styles.commentMeta}>
                    <Text style={styles.commentAuthor}>{comment.userName || 'User'}</Text>
                    <Text style={styles.commentDate}>{new Date(comment.createdAt).toLocaleDateString()}</Text>
                  </View>
                  <View style={styles.reactions}>
                    <TouchableOpacity 
                      onPress={() => handleToggleReaction(comment.id, 'like')}
                      style={[styles.reactionButton, comment.reactions?.some(r => r.type === 'like') && styles.activeReaction]}
                    >
                      <Text>👍</Text>
                    </TouchableOpacity>
                    <TouchableOpacity 
                      onPress={() => handleToggleReaction(comment.id, 'love')}
                      style={[styles.reactionButton, comment.reactions?.some(r => r.type === 'love') && styles.activeReaction]}
                    >
                      <Text>❤️</Text>
                    </TouchableOpacity>
                  </View>
                </View>
                <Text style={styles.commentContent}>{comment.content}</Text>
              </View>
            ))}
            {comments.length === 0 && (
              <Text style={styles.emptyText}>No comments yet</Text>
            )}
          </View>
        </ScrollView>

        <View style={styles.commentInputContainer}>
          <TextInput
            style={styles.commentInput}
            placeholder="Add a comment..."
            placeholderTextColor={colors.textSecondary}
            value={newComment}
            onChangeText={setNewComment}
            multiline
          />
          <TouchableOpacity 
            style={[styles.sendButton, !newComment.trim() && styles.sendButtonDisabled]}
            onPress={handleAddComment}
            disabled={!newComment.trim() || isSubmittingComment}
          >
            {isSubmittingComment ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Ionicons name="send" size={20} color="#fff" />
            )}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>

      <Modal
        visible={showAssignModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowAssignModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Assign Task</Text>
              <TouchableOpacity onPress={() => setShowAssignModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>
            <ScrollView>
              {teamMembers.map((member) => {
                const isAssigned = task.assignedTo?.includes(member.id);
                return (
                  <TouchableOpacity 
                    key={member.id} 
                    style={styles.memberItem}
                    onPress={() => handleToggleAssignment(member.id)}
                  >
                    <View style={styles.memberInfo}>
                      <View style={[styles.avatar, { backgroundColor: colors.primary + '20' }]}>
                        <Text style={[styles.avatarText, { color: colors.primary }]}>{member.name.charAt(0).toUpperCase()}</Text>
                      </View>
                      <View>
                        <Text style={styles.memberName}>{member.name}</Text>
                        <Text style={styles.memberRole}>{member.role}</Text>
                      </View>
                    </View>
                    <Ionicons 
                      name={isAssigned ? "checkbox" : "square-outline"} 
                      size={24} 
                      color={isAssigned ? colors.primary : colors.textSecondary} 
                    />
                  </TouchableOpacity>
                );
              })}
            </ScrollView>
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
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
  },
  backButton: {
    padding: 4,
  },
  editButton: {
    padding: 4,
  },
  content: {
    flex: 1,
    padding: 16,
  },
  statusSection: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 12,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 8,
  },
  statusText: {
    fontSize: 14,
    fontWeight: '600',
  },
  overdueBadge: {
    backgroundColor: '#F4433620',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  overdueText: {
    color: '#F44336',
    fontSize: 14,
    fontWeight: '600',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    marginBottom: 12,
  },
  description: {
    fontSize: 16,
    color: colors.textSecondary,
    lineHeight: 24,
    marginBottom: 24,
  },
  metaGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginBottom: 24,
    gap: 16,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    padding: 12,
    borderRadius: 12,
    flex: 1,
    minWidth: '45%',
  },
  metaContent: {
    marginLeft: 12,
  },
  metaLabel: {
    fontSize: 12,
    color: colors.textSecondary,
    marginBottom: 2,
  },
  metaValue: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text,
  },
  section: {
    marginBottom: 24,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.text,
  },
  addAssigneeButton: {
    padding: 4,
  },
  assigneeList: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  assigneeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    padding: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: colors.border,
  },
  avatar: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  avatarText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  assigneeName: {
    fontSize: 14,
    color: colors.text,
  },
  actionButtons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  actionButton: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
    flex: 1,
    minWidth: '30%',
    alignItems: 'center',
  },
  actionButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  pendingAction: { backgroundColor: '#9E9E9E' },
  inProgressAction: { backgroundColor: '#FF9800' },
  completedAction: { backgroundColor: '#4CAF50' },
  commentItem: {
    backgroundColor: colors.surface,
    padding: 12,
    borderRadius: 12,
    marginBottom: 12,
  },
  commentHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  commentAvatar: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.primary + '40',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  commentAvatarText: {
    color: colors.primary,
    fontWeight: 'bold',
  },
  commentMeta: {
    flex: 1,
  },
  commentAuthor: {
    fontSize: 14,
    fontWeight: 'bold',
    color: colors.text,
  },
  commentDate: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  commentContent: {
    fontSize: 14,
    color: colors.text,
    lineHeight: 20,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  commentInputContainer: {
    flexDirection: 'row',
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    backgroundColor: colors.background,
    alignItems: 'flex-end',
    gap: 12,
  },
  commentInput: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 8,
    paddingTop: 8,
    maxHeight: 100,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  sendButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendButtonDisabled: {
    backgroundColor: colors.textSecondary,
    opacity: 0.5,
  },
  reactions: {
    flexDirection: 'row',
    gap: 8,
    marginLeft: 'auto',
  },
  reactionButton: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    backgroundColor: colors.surfaceVariant,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  activeReaction: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    maxHeight: '80%',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.text,
  },
  memberItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  memberInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  memberName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  memberRole: {
    fontSize: 12,
    color: colors.textSecondary,
  },
});
