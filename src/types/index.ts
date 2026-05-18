export interface User {
  id: string;
  email: string;
  name: string;
  phone: string;
  kycStatus: 'none' | 'pending' | 'verified' | 'rejected';
  role: 'owner' | 'member' | 'admin' | 'manager';
}

export interface Wallet {
  id: string;
  balance: number;
  currency: string;
  account_number?: string;
  virtual_account_number?: string;
  bank_name?: string;
  bank_code?: string;
  account_name?: string;
  type: 'user' | 'business';
}

export interface SubscriptionTransaction {
  id: string;
  amount: number;
  currency: string;
  status: 'success' | 'failed' | 'pending';
  type: string;
  transaction_type?: string;
  reference?: string;
  created_at: string;
}

export interface Idea {
  id: string;
  businessId: string;
  userId: string;
  userName: string;
  title: string;
  description: string;
  status: 'under_review' | 'executed' | 'rejected';
  createdAt: string;
  updatedAt: string;
}

export interface BusinessWallet extends Wallet {
  business_name: string;
}

export interface Business {
  id: string;
  name: string;
  email: string;
  phone_number: string;
  industry: string;
  logo_url: string;
  currency: string;
  address?: {
    country: string;
    state: string;
    city: string;
    street: string;
    houseNumber: string;
  };
  kycStatus: 'none' | 'pending' | 'verified' | 'rejected';
  gtbAccountNumber?: string;
}

export interface TeamMember {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'manager' | 'member';
  status: 'active' | 'invited' | 'inactive';
  joinedAt?: string;
}

export interface Attachment {
  id: string;
  name: string;
  url: string;
  type: string;
}

export interface Reaction {
  userId: string;
  userName?: string;
  type: 'like' | 'love' | 'laugh';
}

export interface Comment {
  id: string;
  taskId?: string;
  epicName?: string;
  epicId?: string;
  userId: string;
  userName?: string;
  userEmail?: string;
  parentCommentId?: string;
  content: string;
  mentions: Array<{ type: 'user' | 'task'; id: string }>;
  replies?: Comment[];
  reactions?: Reaction[];
  createdAt: string;
  updatedAt: string;
}

export interface Task {
  id: string;
  businessId: string;
  createdBy: string;
  title: string;
  description?: string;
  epic?: string;
  epicId?: string;
  sprint?: string;
  targetValue: number;
  accomplishedValue: number;
  startDate: string;
  endDate: string;
  dueDate?: string;
  status: 'pending' | 'in_progress' | 'completed';
  isOverdue: boolean;
  assignedTo?: string[];
  attachments?: Attachment[];
  comments?: Comment[];
  images?: string[];
  createdAt: string;
  updatedAt: string;
}

export interface CreateTaskInput {
  title: string;
  description?: string;
  epic?: string;
  epicId?: string;
  sprint?: string;
  startDate?: string;
  endDate?: string;
  dueDate?: string;
  assignedTo?: string[];
  images?: string[];
}

export interface Epic {
  id: string;
  businessId: string;
  name: string;
  description?: string;
  status: 'active' | 'completed' | 'archived';
  createdAt: string;
  updatedAt: string;
}

export interface EpicCounts {
  [key: string]: { total: number; completed: number };
}

export interface Employee {
  id: string;
  name: string;
  email: string;
  salary: number | string;
  salary_currency: string;
  bank_account_number?: string | null;
  bank_code?: string | null;
  account_name?: string | null;
  role: string;
  bonuses_total?: number;
  deductions_total?: number;
  netSalary: number;
  next_pay_date?: string;
  salary_calculation_status?: string;
  contract_start_date?: string;
  bonusesTotal?: number;
  deductionsTotal?: number;
  adjustments?: {
    bonuses: number;
    deductions: number;
    bonus_list: AdjustmentItem[];
    deduction_list: AdjustmentItem[];
  };
}

export interface AdjustmentItem {
  user_id: string;
  type: 'bonus' | 'deduction';
  amount: string;
  currency: string;
}

export interface PayrollAdjustment {
  id: string;
  business_id: string;
  user_id: string;
  type: 'bonus' | 'deduction';
  amount: string;
  currency: string;
  reason: string;
  status: 'pending' | 'processed';
  transfer_id?: string | null;
  created_at: string;
  updated_at: string;
  processed_at?: string | null;
  user_name?: string;
  user_email?: string;
}

export interface PayrollConfig {
  salary_interval: 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom';
  salary_custom_date?: string | null;
}

export interface Transfer {
  id: string;
  amount: number;
  currency: string;
  status: 'pending' | 'success' | 'failed';
  recipient_name: string;
  recipient_account?: string;
  failure_reason?: string;
  created_at: string;
}

export interface Bank {
  code: string;
  name: string;
}

export interface Subscription {
  id: string;
  name: string;
  subscription_status: 'active' | 'cancelled' | 'past_due';
  trial_ends_at: string | null;
  plan_id: string;
  plan_name: string;
  plan_price: string;
  plan_discount?: string;
  max_team_members: number;
  features: string[];
  team_usage: number;
  next_due_subscription_date?: string;
}

export interface Plan {
  id: string;
  name: string;
  price: number;
  discount?: string;
  duration?: 'monthly' | 'yearly';
  currency?: string;
  description: string;
  features: string[];
  max_team_members: number;
  trial_days: number;
}

export interface Card {
  id: string;
  last4: string;
  card_type: string;
  exp_month: string;
  exp_year: string;
  is_active: boolean;
}

export interface PaymentTransaction {
  id: string;
  business_id?: string;
  plan_id?: string;
  amount: number | string;
  currency: string;
  reference: string;
  status: string;
  gateway_response?: any;
  created_at: string;
  updated_at?: string;
  transaction_type?: string;
  plan_name?: string;
}

export interface FeeConfig {
  id: string;
  name: string;
  fee_type: string;
  config_type: 'flat' | 'percentage_cap' | 'flat_conditional' | 'range';
  config: {
    amount?: number;
    percentage?: number;
    cap?: number;
    conditions?: Array<{
      fee: number;
      operator: string;
      threshold: number;
    }>;
    ranges?: Array<{
      min: number;
      max: number;
      fee: number;
    }>;
  };
  currency: string;
}

export interface Idea {
  id: string;
  businessId: string;
  userId: string;
  userName?: string;
  title: string;
  description: string;
  status: 'under_review' | 'executed' | 'rejected';
  createdAt: string;
  updatedAt: string;
}

export interface KYCStatus {
  user_kyc_status: 'none' | 'pending' | 'verified' | 'rejected';
  business_kyc_status: 'none' | 'pending' | 'verified' | 'rejected';
  bvn_verified: boolean;
  nin_verified: boolean;
}

export interface BusinessProfile {
  id: string;
  name: string;
  email: string;
  phone_number: string;
  industry: string;
  logo_url: string;
  currency: string;
}

export interface ApiResponse<T = any> {
  success: boolean;
  message?: string;
  error?: string;
  data?: T;
}
