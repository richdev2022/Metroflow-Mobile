import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';
import Toast from 'react-native-toast-message';

// @ts-ignore
const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL || 'https://metroflow-backend.netlify.app/api';

let logoutHandler: (() => Promise<void>) | null = null;

export const setLogoutHandler = (handler: () => Promise<void>) => {
  logoutHandler = handler;
};

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use(
  async (config) => {
    const token = await AsyncStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

api.interceptors.response.use(
  (response) => {
    if (response.data?.message && response.config.method !== 'get') {
      Toast.show({
        type: 'success',
        text1: 'Success',
        text2: response.data.message,
      });
    }
    return response;
  },
  async (error) => {
    const message = error.response?.data?.message || 'Something went wrong';
    
    if (error.response?.status === 401 || error.response?.status === 403) {
      await AsyncStorage.multiRemove(['token', 'userId', 'businessId', 'userName']);
      if (logoutHandler) {
        await logoutHandler();
      }
    }

    if (error.config?.method !== 'get' || (error.response?.status !== 401 && error.response?.status !== 403)) {
      Toast.show({
        type: 'error',
        text1: 'Error',
        text2: message,
      });
    }

    return Promise.reject(error);
  }
);

export const authApi = {
  register: (data: {
    businessName: string;
    businessEmail: string;
    businessIndustry?: string;
    adminName: string;
    adminEmail: string;
    password: string;
    kycReferenceId?: string;
    gtbAccount?: string;
  }) => api.post('/auth/register', data),
  
  login: (email: string, password: string) =>
    api.post('/auth/login', { email, password }),
  
  verifyOtp: (email: string, otpCode: string) =>
    api.post('/auth/verify-otp', { email, otpCode }),
  
  resendOtp: (email: string) =>
    api.post('/auth/resend-otp', { email }),
  
  forgotPassword: (email: string) =>
    api.post('/auth/forgot-password', { email }),
  
  verifyResetOtp: (email: string, otpCode: string) =>
    api.post('/auth/verify-reset-otp', { email, otpCode }),
  
  resetPassword: (email: string, otpCode: string, newPassword: string) =>
    api.post('/auth/reset-password', { email, otpCode, newPassword }),
};

export const tasksApi = {
  getTasks: (params?: {
    page?: number;
    limit?: number;
    status?: string;
  }) => api.get('/tasks', { params }),
  
  createTask: (data: {
    title: string;
    description?: string;
    epic?: string;
    epicId?: string;
    sprint?: string;
    startDate?: string;
    endDate?: string;
    dueDate?: string;
    assignedTo?: string[];
  }) => api.post('/tasks', data),
  
  createBulkTasks: (tasks: any[]) =>
    api.post('/tasks/bulk', { tasks }),
  
  bulkUpdateTasks: (data: {
    taskIds: string[];
    updates: any;
  }) => api.patch('/tasks/bulk', data),
  
  deleteTask: (id: string) =>
    api.delete(`/tasks/${id}`),
  
  bulkDeleteTasks: (taskIds: string[]) =>
    api.delete('/tasks', { data: { taskIds } }),
};

export const commentsApi = {
  getComments: (taskId: string) =>
    api.get(`/comments/${taskId}`),
  
  addComment: (data: {
    taskId: string;
    content: string;
    parentCommentId?: string;
  }) => api.post('/comments', data),
  
  deleteComment: (id: string) =>
    api.delete(`/comments/${id}`),
  
  toggleReaction: (id: string, type: 'like' | 'love' | 'laugh') =>
    api.put(`/comments/${id}/reaction`, { type }),
};

export const assignmentsApi = {
  assignTasks: (data: { taskIds: string[]; userIds: string[] }) =>
    api.post('/assignments', data),
  
  getAssignments: (taskId: string) =>
    api.get(`/assignments/${taskId}`),
  
  removeAssignment: (assignmentId: string) =>
    api.delete(`/assignments/${assignmentId}`),
};

export const epicsApi = {
  getEpics: () => api.get('/epics'),
  
  createEpic: (data: {
    name: string;
    description?: string;
  }) => api.post('/epics', data),
  
  linkTasksToEpic: (epicId: string, taskIds: string[]) =>
    api.post(`/epics/${epicId}/link-tasks`, { taskIds }),
  
  backfillEpics: () => api.post('/epics/backfill'),
};

export const teamApi = {
  getTeam: () => api.get('/team'),
  
  inviteMember: (data: { name: string; email: string; role: 'admin' | 'manager' | 'member' }) =>
    api.post('/team/invite', data),
  
  updateMemberStatus: (id: string, status: 'active' | 'inactive') =>
    api.put(`/team/${id}/status`, { status }),
  
  deleteMember: (id: string) =>
    api.delete(`/team/${id}`),
};

export const kycApi = {
  initiate: (type: 'bvn' | 'nin', number: string) =>
    api.post('/kyc/initiate', { type, number }),
  
  verifyOtp: (otp: string) => api.post('/kyc/verify-otp', { otp }),
  
  getStatus: () => api.get('/kyc/status'),
  
  submitBusiness: (formData: FormData) =>
    api.post('/kyc/business', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
};

export const walletApi = {
  getInfo: () => api.get('/wallet'),
  
  fundCard: (amount: number, walletType: 'business' | 'user') =>
    api.post('/wallet/fund/card', { amount, wallet_type: walletType }),
  
  createBusiness: (gtbAccountNumber: string, businessName: string, kycReferenceId?: string) =>
    api.post('/wallet/business/create', { 
      gtb_account_number: gtbAccountNumber, 
      business_name: businessName,
      kycReferenceId
    }),
  
  createVirtualAccount: () => api.post('/wallet/create-virtual-account'),
  
  verifyPayment: (reference: string) =>
    api.get('/wallet/verify', { params: { reference } }),
};

export const transfersApi = {
  getBanks: () => api.get('/transfers/banks'),
  
  resolveAccount: (bankCode: string, accountNumber: string) =>
    api.post('/api/transfers/account-lookup', { bank_code: bankCode, account_number: accountNumber }),
  
  requestTransferOtp: (walletId?: string) =>
    api.post('/transfers/otp/request', { wallet_id: walletId }),
  
  singleTransfer: (data: {
    bankCode: string;
    accountNumber: string;
    accountName: string;
    amount: number;
    remark: string;
    otp: string;
    wallet_id: string;
  }) => api.post('/transfers/single', data),
  
  bulkTransfer: (data: {
    transfers: Array<{
      recipient_account: string;
      recipient_bank: string;
      recipient_name: string;
      amount: number;
      remark: string;
      source_type: string;
      source_id: string;
    }>;
  }) => api.post('/api/transfers/bulk', data),
  
  bulkTransferV2: (data: {
    type: 'manual';
    otp: string;
    source_wallet_id: string;
    data: any;
  }) => api.post('/transfers/bulk', data),
  
  getTransfers: (params?: {
    search?: string;
    status?: string;
    startDate?: string;
    endDate?: string;
    page?: number;
    limit?: number;
  }) => api.get('/transfers', { params }),
  
  retryTransfer: (id: string) => api.post(`/transfers/${id}/retry`),
};

export const payrollApi = {
  getSummary: (params?: {
    search?: string;
    role?: string;
    startDate?: string;
    endDate?: string;
    page?: number;
    limit?: number;
  }) => api.get('/payroll/summary', { params }),
  
  getConfig: () => api.get('/payroll/config'),
  
  updateConfig: (data: {
    salary_interval: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom';
    salary_custom_date?: string;
  }) => api.put('/payroll/config', data),
  
  updateUser: (id: string, data: {
    salary: number;
    salary_currency: string;
    bank_account_number: string;
    bank_code: string;
    account_name: string;
    contract_start_date?: string;
  }) => api.put(`/payroll/user/${id}`, data),
  
  addAdjustment: (data: {
    userId: string;
    type: 'bonus' | 'deduction';
    amount: number;
    currency: string;
    reason: string;
  }) => api.post('/payroll/adjustments', data),
  
  getAdjustments: (userId?: string) =>
    api.get('/payroll/adjustments', { params: { userId } }),
  
  deleteAdjustment: (id: string) =>
    api.delete(`/payroll/adjustments/${id}`),
};

export const subscriptionApi = {
  getCurrent: () => api.get('/subscription/current'),
  
  getPlans: () => api.get('/subscription/plans'),
  
  getCards: () => api.get('/subscription/cards'),
  
  initiatePayment: (planId: string, currency: string) =>
    api.post('/subscription/initiate-payment', { planId, currency }),
  
  verifyPayment: (reference: string) =>
    api.post('/subscription/verify-payment', { reference }),
  
  cancel: () => api.post('/subscription/cancel'),
  
  downgrade: () => api.post('/subscription/downgrade'),
  
  addCard: () => api.post('/subscription/cards/initiate'),
  
  removeCard: (id: string) => api.delete(`/subscription/cards/${id}`),
  
  setActiveCard: (id: string) => api.put(`/subscription/cards/${id}/active`),
  
  getTransactions: (params?: {
    page?: number;
    perPage?: number;
    search?: string;
    status?: string;
    startDate?: string;
    endDate?: string;
  }) => api.get('/subscription/transactions', { params }),
  
  exportTransactions: (params?: {
    startDate?: string;
    endDate?: string;
  }) => api.get('/subscription/transactions/export', { params, responseType: 'blob' }),
};

export const settingsApi = {
  getSettings: () => api.get('/settings'),
  
  updateSettings: (data: {
    name?: string;
    industry?: string;
    logo_url?: string;
    currency?: 'NGN' | 'USD';
  }) => api.put('/settings', data),
  
  requestContactUpdateOtp: (type: 'email' | 'phone', value: string) =>
    api.post('/settings/update-contact/request-otp', { type, value }),
  
  verifyContactUpdateOtp: (otp: string) =>
    api.post('/settings/update-contact/verify-otp', { otp }),
  
  getOtpPreference: () => api.get('/settings/otp-preference'),
  
  updateOtpPreference: (preference: 'email' | 'sms' | 'both') =>
    api.put('/settings/otp-preference', { preference }),
  
  getFees: () => api.get('/fees'),
};

export const activityLogsApi = {
  getLogs: (page = 1, limit = 10) => 
    api.get('/activity-logs', { params: { page, limit } }),
};

export const ideasApi = {
  getIdeas: () => api.get('/ideas'),
  createIdea: (data: { title: string; description: string }) => 
    api.post('/ideas', data),
  updateIdea: (id: string, data: { title: string; description: string }) => 
    api.put(`/ideas/${id}`, data),
  updateStatus: (id: string, status: string) => 
    api.put(`/ideas/${id}/status`, { status }),
  deleteIdea: (id: string) => 
    api.delete(`/ideas/${id}`),
  generateDocumentation: (ideaId: string) => 
    api.post(`/ideas/${ideaId}/documentation`),
  getDocumentation: (ideaId: string) => 
    api.get(`/ideas/${ideaId}/documentation`),
  updateDocumentation: (id: string, formData: FormData) => 
    api.put(`/product-documentation/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  deleteDocumentation: (id: string) => 
    api.delete(`/product-documentation/${id}`),
  regenerateDocumentation: (id: string, areasOfConcern: string) => 
    api.post(`/product-documentation/${id}/regenerate`, { areasOfConcern }),
  getDocumentationPdf: (id: string) => 
    api.get(`/product-documentation/${id}/pdf`, { responseType: 'blob' }),
};

export const storage = {
  setToken: (token: string) => token ? AsyncStorage.setItem('token', token) : AsyncStorage.removeItem('token'),
  getToken: () => AsyncStorage.getItem('token'),
  removeToken: () => AsyncStorage.removeItem('token'),
  
  setUserId: (userId: string) => userId ? AsyncStorage.setItem('userId', userId) : AsyncStorage.removeItem('userId'),
  getUserId: () => AsyncStorage.getItem('userId'),
  
  setBusinessId: (businessId: string) => businessId ? AsyncStorage.setItem('businessId', businessId) : AsyncStorage.removeItem('businessId'),
  getBusinessId: () => AsyncStorage.getItem('businessId'),
  
  setUserName: (userName: string) => userName ? AsyncStorage.setItem('userName', userName) : AsyncStorage.removeItem('userName'),
  getUserName: () => AsyncStorage.getItem('userName'),

  setBiometricsEnabled: (enabled: boolean) => AsyncStorage.setItem('biometricsEnabled', JSON.stringify(enabled)),
  getBiometricsEnabled: () => AsyncStorage.getItem('biometricsEnabled').then(val => val ? JSON.parse(val) : false),
  removeBiometricsEnabled: () => AsyncStorage.removeItem('biometricsEnabled'),

  setBiometricsPromptShown: (shown: boolean) => AsyncStorage.setItem('biometricsPromptShown', JSON.stringify(shown)),
  getBiometricsPromptShown: () => AsyncStorage.getItem('biometricsPromptShown').then(val => val ? JSON.parse(val) : false),
  removeBiometricsPromptShown: () => AsyncStorage.removeItem('biometricsPromptShown'),

  setHasSeenOnboarding: (seen: boolean) => AsyncStorage.setItem('hasSeenOnboarding', JSON.stringify(seen)),
  getHasSeenOnboarding: () => AsyncStorage.getItem('hasSeenOnboarding').then(val => val ? JSON.parse(val) : false),
  
  clearAll: () => AsyncStorage.multiRemove([
    'token', 
    'userId', 
    'businessId', 
    'userName',
    'biometricsEnabled',
    'biometricsPromptShown'
  ]),
};

export default api;
