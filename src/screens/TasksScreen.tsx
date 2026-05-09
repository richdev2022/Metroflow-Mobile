import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, TextInput, Alert, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { MainTabParamList } from '../navigation';
import { useTheme } from '../theme/ThemeContext';
import { tasksApi, epicsApi } from '../services/api';
import { Task, Epic } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import { CompositeScreenProps } from '@react-navigation/native';
import { BottomTabScreenProps } from '@react-navigation/bottom-tabs';

type Props = CompositeScreenProps<
  BottomTabScreenProps<MainTabParamList, 'Tasks'>,
  NativeStackScreenProps<any>
>;

export default function TasksScreen({ navigation }: Props) {
  const { colors } = useTheme();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [epics, setEpics] = useState<Epic[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [selectedStatus, setSelectedStatus] = useState<'all' | 'pending' | 'in_progress' | 'completed'>('all');
  const [selectedEpic, setSelectedEpic] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTasks, setSelectedTasks] = useState<string[]>([]);
  const [isSelectionMode, setIsSelectionMode] = useState(false);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async (showLoader = true) => {
    if (showLoader) setIsLoading(true);
    try {
      const [tasksResponse, epicsResponse] = await Promise.all([
        tasksApi.getTasks(),
        epicsApi.getEpics(),
      ]);

      if (tasksResponse.data.success) {
        setTasks(tasksResponse.data.data.tasks);
      }
      if (epicsResponse.data.success) {
        setEpics(epicsResponse.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch tasks:', error);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
    }
  };

  const onRefresh = () => {
    setIsRefreshing(true);
    fetchData(false);
  };

  const filteredTasks = tasks.filter(task => {
    const matchesStatus = selectedStatus === 'all' || task.status === selectedStatus;
    const matchesEpic = selectedEpic === 'all' || task.epicId === selectedEpic;
    const matchesSearch = searchQuery === '' || 
      task.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (task.description?.toLowerCase().includes(searchQuery.toLowerCase()));
    return matchesStatus && matchesEpic && matchesSearch;
  });

  const toggleTaskSelection = (taskId: string) => {
    if (isSelectionMode) {
      setSelectedTasks(prev => 
        prev.includes(taskId) 
          ? prev.filter(id => id !== taskId)
          : [...prev, taskId]
      );
    }
  };

  const handleLongPress = (taskId: string) => {
    if (!isSelectionMode) {
      setIsSelectionMode(true);
      setSelectedTasks([taskId]);
    }
  };

  const handleBulkDelete = async () => {
    Alert.alert(
      'Delete Tasks',
      `Are you sure you want to delete ${selectedTasks.length} task(s)?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await tasksApi.bulkDeleteTasks(selectedTasks);
              setTasks(prev => prev.filter(t => !selectedTasks.includes(t.id)));
              setSelectedTasks([]);
              setIsSelectionMode(false);
            } catch (error: any) {
              Alert.alert('Error', error.response?.data?.message || 'Failed to delete tasks');
            }
          },
        },
      ]
    );
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

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity 
          style={styles.menuButton}
          onPress={() => navigation.getParent()?.dispatch(DrawerActions.openDrawer())}
        >
          <Ionicons name="menu" size={24} color={colors.text} />
        </TouchableOpacity>
        {isSelectionMode ? (
          <View style={styles.selectionHeader}>
            <TouchableOpacity onPress={() => { setIsSelectionMode(false); setSelectedTasks([]); }}>
              <Ionicons name="close" size={24} color={colors.text} />
            </TouchableOpacity>
            <Text style={styles.selectionCount}>{selectedTasks.length} selected</Text>
            <TouchableOpacity onPress={handleBulkDelete}>
              <Ionicons name="trash-outline" size={24} color="#F44336" />
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.titleRow}>
            <Text style={styles.title}>Tasks</Text>
            <TouchableOpacity style={styles.addButton} onPress={() => navigation.navigate('CreateTask')}>
              <Ionicons name="add" size={24} color="#fff" />
            </TouchableOpacity>
          </View>
        )}

        <TextInput
          style={styles.searchInput}
          placeholder="Search tasks..."
          value={searchQuery}
          onChangeText={setSearchQuery}
        />
      </View>

      <ScrollView horizontal style={styles.filtersScroll} showsHorizontalScrollIndicator={false}>
        <View style={styles.filters}>
          {(['all', 'pending', 'in_progress', 'completed'] as const).map(status => (
            <TouchableOpacity
              key={status}
              style={[styles.filterChip, selectedStatus === status && styles.filterChipActive]}
              onPress={() => setSelectedStatus(status)}
            >
              <Text style={[styles.filterChipText, selectedStatus === status && styles.filterChipTextActive]}>
                {status === 'all' ? 'All' : status.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>

      <ScrollView horizontal style={styles.epicsScroll} showsHorizontalScrollIndicator={false}>
        <View style={styles.epics}>
          <TouchableOpacity
            style={[styles.epicChip, selectedEpic === 'all' && styles.epicChipActive]}
            onPress={() => setSelectedEpic('all')}
          >
            <Text style={[styles.epicChipText, selectedEpic === 'all' && styles.epicChipTextActive]}>
              All Epics
            </Text>
          </TouchableOpacity>
          {epics.map(epic => (
            <TouchableOpacity
              key={epic.id}
              style={[styles.epicChip, selectedEpic === epic.id && styles.epicChipActive]}
              onPress={() => setSelectedEpic(epic.id)}
            >
              <Text style={[styles.epicChipText, selectedEpic === epic.id && styles.epicChipTextActive]}>
                {epic.name}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>

      <ScrollView 
        style={styles.tasksList}
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} colors={[colors.primary]} />
        }
      >
        {filteredTasks.map(task => (
          <TouchableOpacity
            key={task.id}
            style={[
              styles.taskCard,
              selectedTasks.includes(task.id) && styles.taskCardSelected,
              task.isOverdue && styles.taskCardOverdue,
            ]}
            onPress={() => {
              if (isSelectionMode) {
                toggleTaskSelection(task.id);
              } else {
                navigation.navigate('TaskDetail', { taskId: task.id });
              }
            }}
            onLongPress={() => handleLongPress(task.id)}
          >
            <View style={styles.taskHeader}>
              <View style={[styles.statusDot, { backgroundColor: getStatusColor(task.status) }]} />
              <Text style={styles.taskTitle} numberOfLines={1}>{task.title}</Text>
              {task.isOverdue && <Text style={styles.overdueBadge}>Overdue</Text>}
            </View>
            {task.description && (
              <Text style={styles.taskDescription} numberOfLines={2}>
                {task.description}
              </Text>
            )}
            <View style={styles.taskMeta}>
              {task.epic && <Text style={styles.taskEpic}>📁 {task.epic}</Text>}
              <Text style={styles.taskDate}>
                {new Date(task.endDate).toLocaleDateString()}
              </Text>
            </View>
            {task.assignedTo && task.assignedTo.length > 0 && (
              <View style={styles.assignees}>
                {task.assignedTo.slice(0, 3).map((userId, index) => (
                  <View key={index} style={styles.assigneeAvatar}>
                    <Text style={styles.assigneeText}>
                      {userId.charAt(0).toUpperCase()}
                    </Text>
                  </View>
                ))}
                {task.assignedTo.length > 3 && (
                  <Text style={styles.moreAssignees}>+{task.assignedTo.length - 3}</Text>
                )}
              </View>
            )}
          </TouchableOpacity>
        ))}
        {filteredTasks.length === 0 && (
          <View style={styles.emptyState}>
            <Ionicons name="list-outline" size={64} color={colors.textSecondary} />
            <Text style={styles.emptyText}>No tasks found</Text>
          </View>
        )}
      </ScrollView>
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
  titleRow: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  menuButton: {
    padding: 8,
    marginRight: 8,
  },
  titleRow: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: colors.text,
  },
  addButton: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  selectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  selectionCount: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  searchInput: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 12,
    fontSize: 16,
    color: colors.text,
  },
  filtersScroll: {
    maxHeight: 48,
  },
  filters: {
    flexDirection: 'row',
    paddingHorizontal: 24,
    gap: 8,
  },
  filterChip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  filterChipActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  filterChipText: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  filterChipTextActive: {
    color: '#fff',
  },
  epicsScroll: {
    maxHeight: 48,
    marginTop: 8,
  },
  epics: {
    flexDirection: 'row',
    paddingHorizontal: 24,
    gap: 8,
  },
  epicChip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
  },
  epicChipActive: {
    backgroundColor: colors.primary + '20',
    borderColor: colors.primary,
  },
  epicChipText: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  epicChipTextActive: {
    color: colors.primary,
  },
  tasksList: {
    flex: 1,
    padding: 24,
  },
  taskCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  taskCardSelected: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  taskCardOverdue: {
    borderColor: '#F44336',
  },
  taskHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  statusDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: 8,
  },
  taskTitle: {
    flex: 1,
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  overdueBadge: {
    backgroundColor: '#F44336',
    color: '#fff',
    fontSize: 10,
    fontWeight: '600',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  taskDescription: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 8,
  },
  taskMeta: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  taskEpic: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  taskDate: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  assignees: {
    flexDirection: 'row',
    marginTop: 12,
    gap: -8,
  },
  assigneeAvatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: colors.surface,
  },
  assigneeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  moreAssignees: {
    fontSize: 12,
    color: colors.textSecondary,
    marginLeft: 12,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 64,
  },
  emptyText: {
    fontSize: 16,
    color: colors.textSecondary,
    marginTop: 16,
  },
});
