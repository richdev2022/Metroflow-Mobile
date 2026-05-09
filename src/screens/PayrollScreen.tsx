import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, Alert, Modal, TextInput, ActivityIndicator, Switch } from 'react-native';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { MainTabParamList, RootStackParamList } from '../navigation';
import { CompositeNavigationProp } from '@react-navigation/native';
import { BottomTabNavigationProp } from '@react-navigation/bottom-tabs';
import { Employee, PayrollConfig, PayrollAdjustment } from '../types';
import { useTheme } from '../theme/ThemeContext';
import { payrollApi } from '../services/api';
import Ionicons from '@expo/vector-icons/Ionicons';

type PayrollScreenNavigationProp = CompositeNavigationProp<
  BottomTabNavigationProp<MainTabParamList, 'Payroll'>,
  NativeStackNavigationProp<RootStackParamList>
>;

export default function PayrollScreen() {
  const navigation = useNavigation<PayrollScreenNavigationProp>();
  const { colors } = useTheme();
  const [isLoading, setIsLoading] = useState(false);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [config, setConfig] = useState<PayrollConfig | null>(null);
  const [showConfigModal, setShowConfigModal] = useState(false);
  const [showAdjustmentModal, setShowAdjustmentModal] = useState(false);
  const [showEmployeeDetailModal, setShowEmployeeDetailModal] = useState(false);
  const [selectedEmployee, setSelectedEmployee] = useState<Employee | null>(null);
  const [adjustments, setAdjustments] = useState<PayrollAdjustment[]>([]);
  const [adjustmentData, setAdjustmentData] = useState({
    type: 'bonus' as 'bonus' | 'deduction',
    amount: '',
    reason: '',
  });
  const [configData, setConfigData] = useState({
    salary_interval: 'monthly' as PayrollConfig['salary_interval'],
    salary_custom_date: '',
  });

  const styles = createStyles(colors);

  useEffect(() => {
    fetchPayrollData();
  }, []);

  const fetchPayrollData = async () => {
    setIsLoading(true);
    try {
      const [summaryRes, configRes] = await Promise.all([
        payrollApi.getSummary(),
        payrollApi.getConfig(),
      ]);

      if (summaryRes.data.success) {
        setEmployees(summaryRes.data.payroll || []);
      }
      if (configRes.data.success) {
        setConfig(configRes.data.config);
        setConfigData(configRes.data.config);
      }
    } catch (error) {
      console.error('Failed to fetch payroll data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const fetchAdjustments = async (userId: string) => {
    try {
      const response = await payrollApi.getAdjustments(userId);
      if (response.data.success) {
        setAdjustments(response.data.adjustments || []);
      }
    } catch (error) {
      console.error('Failed to fetch adjustments:', error);
    }
  };

  const handleUpdateConfig = async () => {
    setIsLoading(true);
    try {
      const response = await payrollApi.updateConfig(configData);
      if (response.data.success) {
        setConfig(response.data.config || configData);
        Alert.alert('Success', 'Payroll config updated successfully');
        setShowConfigModal(false);
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to update config');
    } finally {
      setIsLoading(false);
    }
  };

  const handleAddAdjustment = async () => {
    if (!selectedEmployee || !adjustmentData.amount || !adjustmentData.reason) {
      Alert.alert('Error', 'Please fill all fields');
      return;
    }

    setIsLoading(true);
    try {
      await payrollApi.addAdjustment({
        userId: selectedEmployee.id,
        type: adjustmentData.type,
        amount: parseFloat(adjustmentData.amount),
        reason: adjustmentData.reason,
      });
      Alert.alert('Success', 'Adjustment added successfully');
      setShowAdjustmentModal(false);
      setAdjustmentData({ type: 'bonus', amount: '', reason: '' });
      fetchAdjustments(selectedEmployee.id);
      fetchPayrollData();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to add adjustment');
    } finally {
      setIsLoading(false);
    }
  };

  const handleDeleteAdjustment = async (id: string) => {
    Alert.alert(
      'Delete Adjustment',
      'Are you sure you want to delete this adjustment?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await payrollApi.deleteAdjustment(id);
              Alert.alert('Success', 'Adjustment deleted successfully');
              if (selectedEmployee) {
                fetchAdjustments(selectedEmployee.id);
                fetchPayrollData();
              }
            } catch (error: any) {
              Alert.alert('Error', error.response?.data?.message || 'Failed to delete adjustment');
            }
          },
        },
      ]
    );
  };

  const openEmployeeDetail = (employee: Employee) => {
    setSelectedEmployee(employee);
    fetchAdjustments(employee.id);
    setShowEmployeeDetailModal(true);
  };

  const totalNetPay = employees.reduce((sum, emp) => sum + (typeof emp.netSalary === 'number' ? emp.netSalary : 0), 0);

  if (isLoading && employees.length === 0) {
    return (
      <View style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity 
          style={styles.menuButton}
          onPress={() => navigation.getParent()?.dispatch(DrawerActions.openDrawer())}
        >
          <Ionicons name="menu" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Payroll</Text>
        <TouchableOpacity 
          style={styles.configButton}
          onPress={() => setShowConfigModal(true)}
        >
          <Ionicons name="settings-outline" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      <View style={styles.summaryCard}>
        <Text style={styles.summaryTitle}>Payroll Summary</Text>
        <View style={styles.summaryStats}>
          <View style={styles.stat}>
            <Text style={styles.statValue}>{employees.length}</Text>
            <Text style={styles.statLabel}>Employees</Text>
          </View>
          <View style={styles.stat}>
            <Text style={styles.statValue}>₦{totalNetPay.toLocaleString()}</Text>
            <Text style={styles.statLabel}>Total Net Pay</Text>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Employees</Text>
        </View>
        {employees.map((employee) => (
          <TouchableOpacity 
            key={employee.id} 
            style={styles.employeeCard}
            onPress={() => openEmployeeDetail(employee)}
          >
            <View style={styles.employeeInfo}>
              <Text style={styles.employeeName}>{employee.name}</Text>
              <Text style={styles.employeeEmail}>{employee.email}</Text>
              <View style={styles.adjustmentsBadge}>
                {employee.adjustments?.bonus_list?.length ? (
                  <Text style={styles.bonusText}>+{employee.adjustments.bonuses}</Text>
                ) : null}
                {employee.adjustments?.deduction_list?.length ? (
                  <Text style={styles.deductionText}>-{employee.adjustments.deductions}</Text>
                ) : null}
              </View>
            </View>
            <View style={styles.employeeSalary}>
              <Text style={styles.salaryAmount}>₦{(typeof employee.netSalary === 'number' ? employee.netSalary : 0).toLocaleString()}</Text>
              <Text style={styles.salaryLabel}>Net Pay</Text>
            </View>
          </TouchableOpacity>
        ))}
      </View>

      <TouchableOpacity 
        style={styles.bulkTransferButton}
        onPress={() => navigation.navigate('BulkTransfer')}
      >
        <Text style={styles.bulkTransferText}>Initiate Bulk Transfer</Text>
      </TouchableOpacity>

      <Modal
        visible={showConfigModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowConfigModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Payroll Config</Text>
              <TouchableOpacity onPress={() => setShowConfigModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <ScrollView showsVerticalScrollIndicator={false}>
              <View style={styles.field}>
                <Text style={styles.label}>Salary Interval</Text>
                <View style={styles.intervalOptions}>
                  {(['daily', 'weekly', 'monthly', 'yearly'] as const).map((interval) => (
                    <TouchableOpacity
                      key={interval}
                      style={[
                        styles.intervalOption,
                        configData.salary_interval === interval && styles.selectedIntervalOption,
                      ]}
                      onPress={() => setConfigData(prev => ({ ...prev, salary_interval: interval }))}
                    >
                      <Text style={[
                        styles.intervalOptionText,
                        configData.salary_interval === interval && styles.selectedIntervalOptionText,
                      ]}>
                        {interval.charAt(0).toUpperCase() + interval.slice(1)}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {configData.salary_interval === 'custom' && (
                <View style={styles.field}>
                  <Text style={styles.label}>Custom Date</Text>
                  <TextInput
                    style={styles.input}
                    placeholder="Enter custom date"
                    placeholderTextColor={colors.textSecondary}
                    value={configData.salary_custom_date || ''}
                    onChangeText={(text) => setConfigData(prev => ({ ...prev, salary_custom_date: text }))}
                  />
                </View>
              )}

              <TouchableOpacity 
                style={[styles.submitButton, isLoading && styles.submitButtonDisabled]}
                onPress={handleUpdateConfig}
                disabled={isLoading}
              >
                {isLoading ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.submitButtonText}>Save Config</Text>
                )}
              </TouchableOpacity>
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal
        visible={showEmployeeDetailModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowEmployeeDetailModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>{selectedEmployee?.name}</Text>
              <TouchableOpacity onPress={() => setShowEmployeeDetailModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <ScrollView showsVerticalScrollIndicator={false}>
              <View style={styles.employeeDetailCard}>
                <View style={styles.detailRow}>
                  <Text style={styles.detailLabel}>Salary</Text>
                  <Text style={styles.detailValue}>₦{(typeof selectedEmployee?.salary === 'number' ? selectedEmployee.salary : 0).toLocaleString()}</Text>
                </View>
                <View style={styles.detailRow}>
                  <Text style={styles.detailLabel}>Bonuses</Text>
                  <Text style={styles.bonusText}>+₦{selectedEmployee?.bonusesTotal?.toLocaleString() || '0'}</Text>
                </View>
                <View style={styles.detailRow}>
                  <Text style={styles.detailLabel}>Deductions</Text>
                  <Text style={styles.deductionText}>-₦{selectedEmployee?.deductionsTotal?.toLocaleString() || '0'}</Text>
                </View>
                <View style={[styles.detailRow, styles.netPayRow]}>
                  <Text style={styles.netPayLabel}>Net Pay</Text>
                  <Text style={styles.netPayValue}>₦{(typeof selectedEmployee?.netSalary === 'number' ? selectedEmployee.netSalary : 0).toLocaleString()}</Text>
                </View>
              </View>

              <View style={styles.section}>
                <View style={styles.sectionHeader}>
                  <Text style={styles.sectionTitle}>Adjustments</Text>
                  <TouchableOpacity 
                    style={styles.addButton}
                    onPress={() => setShowAdjustmentModal(true)}
                  >
                    <Ionicons name="add" size={20} color={colors.primary} />
                  </TouchableOpacity>
                </View>
                {adjustments.map((adjustment) => (
                  <View key={adjustment.id} style={styles.adjustmentCard}>
                    <View style={styles.adjustmentInfo}>
                      <Text style={styles.adjustmentType}>
                        {adjustment.type.charAt(0).toUpperCase() + adjustment.type.slice(1)}
                      </Text>
                      <Text style={styles.adjustmentReason}>{adjustment.reason}</Text>
                      <Text style={styles.adjustmentDate}>
                        {new Date(adjustment.created_at).toLocaleDateString()}
                      </Text>
                    </View>
                    <View style={styles.adjustmentAmountContainer}>
                      <Text style={[
                        styles.adjustmentAmount,
                        adjustment.type === 'bonus' ? styles.bonusText : styles.deductionText,
                      ]}>
                        {adjustment.type === 'bonus' ? '+' : '-'}{adjustment.currency} {adjustment.amount}
                      </Text>
                      <TouchableOpacity 
                        style={styles.deleteButton}
                        onPress={() => handleDeleteAdjustment(adjustment.id)}
                      >
                        <Ionicons name="trash-outline" size={16} color="#F44336" />
                      </TouchableOpacity>
                    </View>
                  </View>
                ))}
                {adjustments.length === 0 && (
                  <Text style={styles.emptyText}>No adjustments yet</Text>
                )}
              </View>
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal
        visible={showAdjustmentModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowAdjustmentModal(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Add Adjustment</Text>
              <TouchableOpacity onPress={() => setShowAdjustmentModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <ScrollView showsVerticalScrollIndicator={false}>
              <View style={styles.field}>
                <Text style={styles.label}>Type</Text>
                <View style={styles.typeOptions}>
                  <TouchableOpacity
                    style={[
                      styles.typeOption,
                      adjustmentData.type === 'bonus' && styles.selectedTypeOption,
                    ]}
                    onPress={() => setAdjustmentData(prev => ({ ...prev, type: 'bonus' }))}
                  >
                    <Ionicons 
                      name="add-circle" 
                      size={20} 
                      color={adjustmentData.type === 'bonus' ? '#fff' : '#4CAF50'} 
                    />
                    <Text style={[
                      styles.typeOptionText,
                      adjustmentData.type === 'bonus' && styles.selectedTypeOptionText,
                    ]}>
                      Bonus
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[
                      styles.typeOption,
                      adjustmentData.type === 'deduction' && styles.selectedTypeOption,
                    ]}
                    onPress={() => setAdjustmentData(prev => ({ ...prev, type: 'deduction' }))}
                  >
                    <Ionicons 
                      name="remove-circle" 
                      size={20} 
                      color={adjustmentData.type === 'deduction' ? '#fff' : '#F44336'} 
                    />
                    <Text style={[
                      styles.typeOptionText,
                      adjustmentData.type === 'deduction' && styles.selectedTypeOptionText,
                    ]}>
                      Deduction
                    </Text>
                  </TouchableOpacity>
                </View>
              </View>

              <View style={styles.field}>
                <Text style={styles.label}>Amount</Text>
                <TextInput
                  style={styles.input}
                  placeholder="Enter amount"
                  placeholderTextColor={colors.textSecondary}
                  value={adjustmentData.amount}
                  onChangeText={(text) => setAdjustmentData(prev => ({ ...prev, amount: text }))}
                  keyboardType="numeric"
                />
              </View>

              <View style={styles.field}>
                <Text style={styles.label}>Reason</Text>
                <TextInput
                  style={[styles.input, styles.textArea]}
                  placeholder="Enter reason"
                  placeholderTextColor={colors.textSecondary}
                  value={adjustmentData.reason}
                  onChangeText={(text) => setAdjustmentData(prev => ({ ...prev, reason: text }))}
                  multiline
                  numberOfLines={3}
                />
              </View>

              <TouchableOpacity 
                style={[styles.submitButton, isLoading && styles.submitButtonDisabled]}
                onPress={handleAddAdjustment}
                disabled={isLoading}
              >
                {isLoading ? (
                  <ActivityIndicator color="#fff" />
                ) : (
                  <Text style={styles.submitButtonText}>Add Adjustment</Text>
                )}
              </TouchableOpacity>
            </ScrollView>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.surfaceVariant,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    padding: 24,
    backgroundColor: colors.surface,
    flexDirection: 'row',
    alignItems: 'center',
  },
  menuButton: {
    padding: 8,
    marginRight: 8,
  },
  headerTitle: {
    flex: 1,
    fontSize: 24,
    fontWeight: 'bold',
    color: colors.text,
    textAlign: 'center',
  },
  configButton: {
    padding: 8,
    marginLeft: 8,
  },
  summaryCard: {
    margin: 16,
    padding: 24,
    backgroundColor: colors.primary,
    borderRadius: 16,
  },
  summaryTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 16,
  },
  summaryStats: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  stat: {
    alignItems: 'center',
  },
  statValue: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  statLabel: {
    color: '#93c5fd',
    fontSize: 12,
    marginTop: 4,
  },
  section: {
    marginHorizontal: 16,
    marginBottom: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  addButton: {
    backgroundColor: colors.primary + '15',
    padding: 8,
    borderRadius: 8,
  },
  addButtonText: {
    color: colors.primary,
    fontWeight: '600',
  },
  employeeCard: {
    backgroundColor: colors.surface,
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
  },
  employeeInfo: {
    flex: 1,
  },
  employeeName: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  employeeEmail: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 4,
  },
  adjustmentsBadge: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 4,
  },
  bonusText: {
    color: '#4CAF50',
    fontWeight: '600',
    fontSize: 12,
  },
  deductionText: {
    color: '#F44336',
    fontWeight: '600',
    fontSize: 12,
  },
  employeeSalary: {
    alignItems: 'flex-end',
  },
  salaryAmount: {
    fontSize: 18,
    fontWeight: 'bold',
    color: colors.primary,
  },
  salaryLabel: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  bulkTransferButton: {
    margin: 16,
    padding: 16,
    backgroundColor: colors.primary,
    borderRadius: 12,
    alignItems: 'center',
  },
  bulkTransferText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
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
    maxHeight: '85%',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.text,
  },
  field: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.text,
    marginBottom: 8,
  },
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 14,
    fontSize: 16,
    color: colors.text,
  },
  textArea: {
    height: 100,
    textAlignVertical: 'top',
  },
  intervalOptions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  intervalOption: {
    flex: 1,
    minWidth: '45%',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: colors.surface,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
  },
  selectedIntervalOption: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  intervalOptionText: {
    fontSize: 14,
    color: colors.text,
    fontWeight: '500',
  },
  selectedIntervalOptionText: {
    color: '#fff',
    fontWeight: '600',
  },
  typeOptions: {
    flexDirection: 'row',
    gap: 12,
  },
  typeOption: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    backgroundColor: colors.surface,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
    gap: 8,
  },
  selectedTypeOption: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  typeOptionText: {
    fontSize: 16,
    color: colors.text,
    fontWeight: '500',
  },
  selectedTypeOptionText: {
    color: '#fff',
    fontWeight: '600',
  },
  submitButton: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  submitButtonDisabled: {
    opacity: 0.5,
  },
  submitButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  employeeDetailCard: {
    backgroundColor: colors.surface,
    borderRadius: 16,
    padding: 16,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  netPayRow: {
    borderBottomWidth: 0,
    paddingTop: 12,
  },
  detailLabel: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  detailValue: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  netPayLabel: {
    fontSize: 16,
    fontWeight: 'bold',
    color: colors.text,
  },
  netPayValue: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.primary,
  },
  adjustmentCard: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    borderWidth: 1,
    borderColor: colors.border,
  },
  adjustmentInfo: {
    flex: 1,
  },
  adjustmentType: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 4,
  },
  adjustmentReason: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 4,
  },
  adjustmentDate: {
    fontSize: 12,
    color: colors.textSecondary,
  },
  adjustmentAmountContainer: {
    alignItems: 'flex-end',
    marginLeft: 12,
  },
  adjustmentAmount: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  deleteButton: {
    padding: 4,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    fontStyle: 'italic',
    textAlign: 'center',
    paddingVertical: 20,
  },
});
