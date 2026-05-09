import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, Alert, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { tasksApi, teamApi, epicsApi } from '../services/api';
import { Task, TeamMember, Epic } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import type { CompositeNavigationProp } from '@react-navigation/native';
import type { BottomTabNavigationProp } from '@react-navigation/bottom-tabs';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { MainTabParamList, RootStackParamList } from '../navigation';
import { LinearGradient } from 'expo-linear-gradient';

type DashboardNavigationProp = CompositeNavigationProp<
  BottomTabNavigationProp<MainTabParamList>,
  NativeStackNavigationProp<RootStackParamList>
>;

export default function DashboardScreen() {
  const { colors } = useTheme();
  const navigation = useNavigation<DashboardNavigationProp>();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [teamMembers, setTeamMembers] = useState<TeamMember[]>([]);
  const [epics, setEpics] = useState<Epic[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [selectedMember, setSelectedMember] = useState<string>('all');
  const [selectedEpic, setSelectedEpic] = useState<string>('all');
  const [startDate, setStartDate] = useState<string>('');
  const [endDate, setEndDate] = useState<string>('');

  const fetchData = async (showLoader = true) => {
    if (showLoader) setIsLoading(true);
    try {
      const [tasksResponse, teamResponse, epicsResponse] = await Promise.all([
        tasksApi.getTasks(10000, {
          assignedTo: selectedMember === 'all' ? undefined : selectedMember,
          epicId: selectedEpic === 'all' ? undefined : selectedEpic,
          startDate: startDate || undefined,
          endDate: endDate || undefined,
        }),
        teamApi.getTeam(),
        epicsApi.getEpics(),
      ]);

      if (tasksResponse.data.success) {
        setTasks(tasksResponse.data.data.tasks);
      }
      if (teamResponse.data.success) {
        setTeamMembers(teamResponse.data.data);
      }
      if (epicsResponse.data.success) {
        setEpics(epicsResponse.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch dashboard data:', error);
    } finally {
      setIsLoading(false);
      setIsRefreshing(false);
    }
  };

  const onRefresh = () => {
    setIsRefreshing(true);
    fetchData(false);
  };

  // Re-fetch when filters change
  useEffect(() => {
    fetchData();
  }, [selectedMember, selectedEpic, startDate, endDate]);

  const handleRefresh = () => {
    fetchData();
  };

  const handleDateChange = (type: 'start' | 'end') => {
    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, '0');
    const day = String(today.getDate()).padStart(2, '0');
    const dateStr = `${year}-${month}-${day}`;
    
    if (type === 'start') {
      setStartDate(dateStr);
    } else {
      setEndDate(dateStr);
    }
  };

  const clearFilters = () => {
    setSelectedMember('all');
    setSelectedEpic('all');
    setStartDate('');
    setEndDate('');
  };

  // Calculate stats from filtered tasks
  const totalTasks = tasks.length;
  const completedTasks = tasks.filter(t => t.status === 'completed').length;
  const inProgressTasks = tasks.filter(t => t.status === 'in_progress').length;
  const overdueTasks = tasks.filter(t => t.isOverdue);
  const completionPercentage = totalTasks > 0 ? Math.round((completedTasks / totalTasks) * 100) : 0;

  const getStatsByMember = () => {
    const stats: { [key: string]: { total: number; completed: number } } = {};
    teamMembers.forEach(member => {
      stats[member.id] = { total: 0, completed: 0 };
    });

    tasks.forEach(task => {
      if (task.assignedTo) {
        task.assignedTo.forEach(userId => {
          if (stats[userId]) {
            stats[userId].total++;
            if (task.status === 'completed') {
              stats[userId].completed++;
            }
          }
        });
      }
    });

    return stats;
  };

  const memberStats = getStatsByMember();

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
      <ScrollView 
        style={styles.scrollView}
        refreshControl={
          <RefreshControl refreshing={isRefreshing} onRefresh={onRefresh} colors={[colors.primary]} />
        }
      >
        <View style={styles.header}>
          <TouchableOpacity 
            style={styles.menuButton}
            onPress={() => navigation.getParent()?.dispatch(DrawerActions.openDrawer())}
          >
            <Ionicons name="menu" size={24} color={colors.text} />
          </TouchableOpacity>
          <Text style={styles.title}>Dashboard</Text>
          <TouchableOpacity onPress={handleRefresh} style={styles.refreshButton}>
            <Ionicons name="refresh-outline" size={24} color={colors.primary} />
          </TouchableOpacity>
        </View>

        {/* Filters Section */}
        <View style={styles.filtersSection}>
          <Text style={styles.sectionTitle}>Filters</Text>
          
          {/* Team Member Filter */}
          <View style={styles.filterGroup}>
            <Text style={styles.filterLabel}>Team Member</Text>
            <ScrollView horizontal showsHorizontalScrollIndicator={false}>
              <View style={styles.filterChips}>
                <TouchableOpacity
                  style={[styles.filterChip, selectedMember === 'all' && styles.filterChipActive]}
                  onPress={() => setSelectedMember('all')}
                >
                  <Text style={[styles.filterChipText, selectedMember === 'all' && styles.filterChipTextActive]}>All</Text>
                </TouchableOpacity>
                {teamMembers.map(member => (
                  <TouchableOpacity
                    key={member.id}
                    style={[styles.filterChip, selectedMember === member.id && styles.filterChipActive]}
                    onPress={() => setSelectedMember(member.id)}
                  >
                    <Text style={[styles.filterChipText, selectedMember === member.id && styles.filterChipTextActive]}>
                      {member.name}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </ScrollView>
          </View>

          {/* Epic Filter */}
          <View style={styles.filterGroup}>
            <Text style={styles.filterLabel}>Epic</Text>
            <ScrollView horizontal showsHorizontalScrollIndicator={false}>
              <View style={styles.filterChips}>
                <TouchableOpacity
                  style={[styles.filterChip, selectedEpic === 'all' && styles.filterChipActive]}
                  onPress={() => setSelectedEpic('all')}
                >
                  <Text style={[styles.filterChipText, selectedEpic === 'all' && styles.filterChipTextActive]}>All Epics</Text>
                </TouchableOpacity>
                {epics.map(epic => (
                  <TouchableOpacity
                    key={epic.id}
                    style={[styles.filterChip, selectedEpic === epic.id && styles.filterChipActive]}
                    onPress={() => setSelectedEpic(epic.id)}
                  >
                    <Text style={[styles.filterChipText, selectedEpic === epic.id && styles.filterChipTextActive]}>
                      {epic.name}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </ScrollView>
          </View>

          {/* Date Range Filter */}
          <View style={styles.filterGroup}>
            <Text style={styles.filterLabel}>Date Range</Text>
            <View style={styles.dateRow}>
              <TouchableOpacity
                style={styles.dateButton}
                onPress={() => handleDateChange('start')}
              >
                <Ionicons name="calendar-outline" size={16} color={colors.primary} />
                <Text style={[styles.dateButtonText, !startDate && styles.dateButtonPlaceholder]}>
                  {startDate || 'Start Date'}
                </Text>
              </TouchableOpacity>
              <Text style={styles.dateSeparator}>to</Text>
              <TouchableOpacity
                style={styles.dateButton}
                onPress={() => handleDateChange('end')}
              >
                <Ionicons name="calendar-outline" size={16} color={colors.primary} />
                <Text style={[styles.dateButtonText, !endDate && styles.dateButtonPlaceholder]}>
                  {endDate || 'End Date'}
                </Text>
              </TouchableOpacity>
              {(startDate || endDate) && (
                <TouchableOpacity onPress={clearFilters}>
                  <Ionicons name="close-circle" size={20} color={colors.textSecondary} />
                </TouchableOpacity>
              )}
            </View>
          </View>
        </View>

        {/* Stats Grid */}
        <View style={styles.statsGrid}>
          {/* Quick Actions */}
          <TouchableOpacity style={styles.actionCard} onPress={() => navigation.navigate('Backlog')}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.actionIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="archive-outline" size={20} color="#fff" />
            </LinearGradient>
            <Text style={styles.actionLabel}>Backlog</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionCard} onPress={() => navigation.navigate('Ideas')}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.actionIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="bulb-outline" size={20} color="#fff" />
            </LinearGradient>
            <Text style={styles.actionLabel}>Ideas</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionCard} onPress={() => navigation.navigate('ActivityLogs')}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.actionIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="receipt-outline" size={20} color="#fff" />
            </LinearGradient>
            <Text style={styles.actionLabel}>Logs</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionCard} onPress={() => navigation.navigate('Team')}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.actionIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="people-outline" size={20} color="#fff" />
            </LinearGradient>
            <Text style={styles.actionLabel}>Team</Text>
          </TouchableOpacity>

          {/* KPI Cards */}
          <View style={[styles.statCard, styles.statCardShadow]}>
            <View style={[styles.statIcon, { backgroundColor: colors.primary + '20' }]}>
              <Ionicons name="list-outline" size={24} color={colors.primary} />
            </View>
            <Text style={styles.statValue}>{totalTasks}</Text>
            <Text style={styles.statLabel}>Total Tasks</Text>
          </View>

          <View style={[styles.statCard, styles.statCardShadow]}>
            <View style={[styles.statIcon, { backgroundColor: colors.success + '20' }]}>
              <Ionicons name="checkmark-circle-outline" size={24} color={colors.success} />
            </View>
            <Text style={styles.statValue}>{completedTasks}</Text>
            <Text style={styles.statLabel}>Completed</Text>
          </View>

          <View style={[styles.statCard, styles.statCardShadow]}>
            <View style={[styles.statIcon, { backgroundColor: colors.warning + '20' }]}>
              <Ionicons name="time-outline" size={24} color={colors.warning} />
            </View>
            <Text style={styles.statValue}>{inProgressTasks}</Text>
            <Text style={styles.statLabel}>In Progress</Text>
          </View>

          <View style={[styles.statCard, styles.statCardShadow]}>
            <View style={[styles.statIcon, { backgroundColor: colors.error + '20' }]}>
              <Ionicons name="alert-circle-outline" size={24} color={colors.error} />
            </View>
            <Text style={styles.statValue}>{overdueTasks.length}</Text>
            <Text style={styles.statLabel}>Overdue</Text>
          </View>
        </View>

        {/* Completion Rate */}
        <View style={styles.progressSection}>
          <Text style={styles.sectionTitle}>Completion Rate</Text>
          <View style={styles.progressCard}>
            <View style={styles.progressBarContainer}>
              <View style={styles.progressBar}>
                <LinearGradient
                  colors={[colors.primary, colors.primaryLight]}
                  style={[styles.progressFill, { width: `${completionPercentage}%` }]}
                  start={{ x: 0, y: 0 }}
                  end={{ x: 1, y: 0 }}
                />
              </View>
              <Text style={styles.progressText}>{completionPercentage}%</Text>
            </View>
          </View>
        </View>

        {/* Overdue Tasks */}
        {overdueTasks.length > 0 && (
          <View style={styles.overdueSection}>
            <Text style={styles.sectionTitle}>Overdue Tasks</Text>
            {overdueTasks.slice(0, 3).map(task => (
              <View key={task.id} style={styles.overdueCard}>
                <View style={styles.overdueIcon}>
                  <Ionicons name="alert" size={20} color={colors.error} />
                </View>
                <View style={styles.overdueContent}>
                  <Text style={styles.overdueTitle}>{task.title}</Text>
                  <Text style={styles.overdueDate}>Due: {new Date(task.dueDate || task.endDate).toLocaleDateString()}</Text>
                </View>
              </View>
            ))}
          </View>
        )}

        {/* Team Performance */}
        <View style={styles.teamRankingSection}>
          <Text style={styles.sectionTitle}>Team Performance</Text>
          {teamMembers
            .filter(member => memberStats[member.id]?.total > 0)
            .sort((a, b) => {
              const aRate = memberStats[a.id]?.total > 0 ? memberStats[a.id].completed / memberStats[a.id].total : 0;
              const bRate = memberStats[b.id]?.total > 0 ? memberStats[b.id].completed / memberStats[b.id].total : 0;
              return bRate - aRate;
            })
            .slice(0, 5)
            .map((member, index) => {
              const stats = memberStats[member.id];
              const rate = stats?.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0;
              return (
                <View key={member.id} style={styles.teamMemberRow}>
                  <Text style={styles.rank}>{index + 1}</Text>
                  <View style={styles.memberInfo}>
                    <Text style={styles.memberName}>{member.name}</Text>
                    <Text style={styles.memberRole}>{member.role}</Text>
                  </View>
                  <View style={styles.memberStats}>
                    <Text style={styles.completionRate}>{rate}%</Text>
                    <Text style={styles.taskCount}>{stats?.completed}/{stats?.total}</Text>
                  </View>
                </View>
              );
            })}
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
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  scrollView: {
    flex: 1,
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
    flex: 1,
    fontSize: 28,
    fontWeight: 'bold',
    color: colors.text,
  },
  refreshButton: {
    padding: 8,
  },
  filtersSection: {
    padding: 24,
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 16,
  },
  filterGroup: {
    marginBottom: 16,
  },
  filterLabel: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.textSecondary,
    marginBottom: 8,
  },
  filterChips: {
    flexDirection: 'row',
    gap: 8,
  },
  filterChip: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: colors.surfaceVariant,
    borderWidth: 1,
    borderColor: colors.border,
  },
  filterChipActive: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 6,
  },
  filterChipText: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  filterChipTextActive: {
    color: '#fff',
    fontWeight: '600',
  },
  dateRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dateButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 8,
    backgroundColor: colors.surfaceVariant,
    borderWidth: 1,
    borderColor: colors.border,
    gap: 6,
  },
  dateButtonText: {
    fontSize: 14,
    color: colors.text,
  },
  dateButtonPlaceholder: {
    color: colors.textSecondary,
  },
  dateSeparator: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    padding: 16,
    gap: 12,
  },
  actionCard: {
    flex: 1,
    minWidth: '22%',
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: colors.text,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 4,
  },
  actionIconGradient: {
    width: 44,
    height: 44,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#2563eb',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 6,
  },
  actionLabel: {
    fontSize: 12,
    color: colors.text,
    marginTop: 8,
    fontWeight: '600',
  },
  statCard: {
    flex: 1,
    minWidth: '45%',
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 20,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
  },
  statCardShadow: {
    shadowColor: colors.text,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
    elevation: 8,
  },
  statIcon: {
    width: 52,
    height: 52,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  statValue: {
    fontSize: 32,
    fontWeight: 'bold',
    color: colors.text,
  },
  statLabel: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 6,
    fontWeight: '500',
  },
  progressSection: {
    padding: 24,
  },
  progressCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 20,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: colors.text,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.08,
    shadowRadius: 12,
    elevation: 8,
  },
  progressBarContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  progressBar: {
    flex: 1,
    height: 14,
    backgroundColor: colors.surfaceVariant,
    borderRadius: 7,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    borderRadius: 7,
  },
  progressText: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.primary,
    minWidth: 52,
    textAlign: 'right',
  },
  overdueSection: {
    padding: 24,
  },
  overdueCard: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: colors.text,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 4,
  },
  overdueIcon: {
    marginRight: 12,
  },
  overdueContent: {
    flex: 1,
  },
  overdueTitle: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
  overdueDate: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 4,
  },
  teamRankingSection: {
    padding: 24,
  },
  teamMemberRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: colors.border,
    shadowColor: colors.text,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 4,
  },
  rank: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.primary,
    width: 36,
  },
  memberInfo: {
    flex: 1,
  },
  memberName: {
    fontSize: 15,
    fontWeight: '600',
    color: colors.text,
  },
  memberRole: {
    fontSize: 13,
    color: colors.textSecondary,
    marginTop: 2,
  },
  memberStats: {
    alignItems: 'flex-end',
  },
  completionRate: {
    fontSize: 18,
    fontWeight: '700',
    color: colors.primary,
  },
  taskCount: {
    fontSize: 13,
    color: colors.textSecondary,
  },
});
