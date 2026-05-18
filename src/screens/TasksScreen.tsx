import React, { useState, useEffect } from 'react';
import { 
  View, 
  Text, 
  StyleSheet, 
  ScrollView, 
  TouchableOpacity, 
  ActivityIndicator, 
  TextInput, 
  Alert, 
  RefreshControl,
  FlatList,
  Keyboard,
  KeyboardAvoidingView,
  Platform
} from 'react-native';
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
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [total, setTotal] = useState(0);

  useEffect(() => {
    fetchData(1, true);
  }, []);

  const fetchData = async (pageNumber: number, refresh = false) => {
    try {
      if (refresh) {
        setIsRefreshing(true);
      } else if (pageNumber > 1) {
        setIsLoadingMore(true);
      } else {
        setIsLoading(true);
      }

      const params: any = {
        page: pageNumber,
        limit: 20,
      };
      if (selectedStatus !== 'all') params.status = selectedStatus;

      const [tasksResponse, epicsResponse] = await Promise.all([
        tasksApi.getTasks(params),
        epicsApi.getEpics(),
      ]);

      if (tasksResponse.data.success) {
        const newTasks = tasksResponse.data.data.tasks || [];
        if (refresh) {
          setTasks(newTasks);
        } else {
          setTasks(prev => [...prev, ...newTasks]);
        }
        setHasMore(newTasks.length === 20);
        setPage(pageNumber);
        setTotal(tasksResponse.data.data.total || 0);
      }
      if (epicsResponse.data.success) {
        setEpics(epicsResponse.data.data || []);
      }
    } catch (error) {
      console.error('Failed to fetch tasks:', error);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
      setIsLoadingMore(false);
    }
  };

  const onRefresh = () => {
    fetchData(1, true);
  };

  const loadMore = () => {
    if (!isLoadingMore && hasMore) {
      fetchData(page + 1);
    }
  };

  const filteredTasks = tasks.filter(task => {
    const matchesEpic = selectedEpic === 'all' || task.epicId === selectedEpic;
    const matchesSearch = searchQuery === '' || 
      task.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (task.description?.toLowerCase().includes(searchQuery.toLowerCase()));
    return matchesEpic && matchesSearch;
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
    Keyboard.dismiss();
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

  const renderItem = ({ item: task }: { item: Task }) => (
    <TouchableOpacity
      style={[
        styles.taskCard,
        selectedTasks.includes(task.id) && styles.taskCardSelected,
        task.isOverdue && styles.taskCardOverdue,
      ]}
      onPress={() => {
        Keyboard.dismiss();
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
  );

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <View style={styles.header}>
          <TouchableOpacity 
            style={styles.menuButton}
            onPress={() => {
              Keyboard.dismiss();
              navigation.getParent()?.dispatch(DrawerActions.openDrawer());
            }}
          >
            <Ionicons name="menu" size={24} color={colors.text} />
          </TouchableOpacity>
          {isSelectionMode ? (
            <View style={styles.selectionHeader}>
              <TouchableOpacity onPress={() => { 
                setIsSelectionMode(false); 
                setSelectedTasks([]); 
              }}>
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
              <TouchableOpacity 
                style={styles.addButton} 
                onPress={() => {
                  Keyboard.dismiss();
                  navigation.navigate('CreateTask');
                }}
              >
                <Ionicons name="add" size={24} color="#fff" />
              </TouchableOpacity>
            </View>
          )}
        </View>

        <View style={styles.searchContainer}>
          <View style={styles.searchInputContainer}>
            <Ionicons name="search-outline" size={20} color={colors.textSecondary} />
            <TextInput
              style={styles.searchInput}
              placeholder="Search tasks..."
              placeholderTextColor={colors.textSecondary}
              value={searchQuery}
              onChangeText={setSearchQuery}
              returnKeyType="search"
            />
            {searchQuery ? (
              <TouchableOpacity onPress={() => setSearchQuery('')}>
                <Ionicons name="close-circle" size={20} color={colors.textSecondary} />
              </TouchableOpacity>
            ) : null}
          </View>
        </View>

        <ScrollView horizontal style={styles.filtersScroll} showsHorizontalScrollIndicator={false}>
          <View style={styles.filters}>
            {(['all', 'pending', 'in_progress', 'completed'] as const).map(status => (
              <TouchableOpacity
                key={status}
                style={[styles.filterChip, selectedStatus === status && styles.filterChipActive]}
                onPress={() => {
                  Keyboard.dismiss();
                  setSelectedStatus(status);
                  fetchData(1, true);
                }}
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
              onPress={() => {
                Keyboard.dismiss();
                setSelectedEpic('all');
              }}
            >
              <Text style={[styles.epicChipText, selectedEpic === 'all' && styles.epicChipTextActive]}>
                All Epics
              </Text>
            </TouchableOpacity>
            {epics.map(epic => (
              <TouchableOpacity
                key={epic.id}
                style={[styles.epicChip, selectedEpic === epic.id && styles.epicChipActive]}
                onPress={() => {
                  Keyboard.dismiss();
                  setSelectedEpic(epic.id);
                }}
              >
                <Text style={[styles.epicChipText, selectedEpic === epic.id && styles.epicChipTextActive]}>
                  {epic.name}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </ScrollView>

        <FlatList
          data={filteredTasks}
          renderItem={renderItem}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.tasksList}
          refreshControl={
            <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} colors={[colors.primary]} />
          }
          onEndReached={loadMore}
          onEndReachedThreshold={0.5}
          ListFooterComponent={() => (
            isLoadingMore ? <ActivityIndicator style={{ margin: 16 }} color={colors.primary} /> : null
          )}
          ListEmptyComponent={
            !isLoading ? (
              <View style={styles.emptyState}>
                <Ionicons name="list-outline" size={64} color={colors.textSecondary} />
                <Text style={styles.emptyText}>No tasks found</Text>
              </View>
            ) : null
          }
        />
      </KeyboardAvoidingView>
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
    paddingHorizontal: 24,
    paddingTop: 24,
    paddingBottom: 8,
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
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  selectionCount: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  searchContainer: {
    paddingHorizontal: 24,
    paddingBottom: 16,
  },
  searchInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 12,
    gap: 8,
  },
  searchInput: {
    flex: 1,
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
    padding: 24,
    paddingBottom: 100,
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
