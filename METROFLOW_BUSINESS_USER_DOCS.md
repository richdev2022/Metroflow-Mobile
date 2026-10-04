# Metricorex Mobile Version Documentation

## Table of Contents

1. [Authentication Flow](#authentication-flow)
2. [Dashboard & KPI](#dashboard--kpi)
3. [Tasks Management](#tasks-management)
4. [Team Management](#team-management)
5. [Wallet & Payments](#wallet--payments)
6. [Payroll Management](#payroll-management)
7. [Subscription & Billing](#subscription--billing)
8. [Settings](#settings)
9. [Other Features](#other-features)

---

## 1. Authentication Flow

### 1.1 Register Business

**Endpoint:** `POST /api/auth/register`

**Request Payload:**

```typescript
{
  businessName: string;
  businessEmail: string;
  businessIndustry?: string;
  adminName: string;
  adminEmail: string;
  password: string;
  kycReferenceId?: string;
  gtbAccount?: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  userId?: string;
  businessId?: string;
  token?: string;
  requiresOtp?: boolean;
}
```

**Flow:**

1. User enters business details (business name, email, industry)
2. User enters admin details (name, email, password)
3. Password validation: min 8 chars, alphanumeric + symbol
4. System creates business and admin user
5. User is redirected to OTP verification step

---

### 1.2 Login

**Endpoint:** `POST /api/auth/login`

**Request Payload:**

```typescript
{
  email: string;
  password: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  token?: string;
  userId?: string;
  businessId?: string;
  message?: string;
  requiresOtp?: boolean;
}
```

**Flow:**

1. User enters email and password
2. System validates credentials
3. If valid, returns token and redirects to dashboard

---

### 1.3 Verify OTP

**Endpoint:** `POST /api/auth/verify-otp`

**Request Payload:**

```typescript
{
  email: string;
  otpCode: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  token?: string;
  userId?: string;
  businessId?: string;
  message?: string;
}
```

---

### 1.4 Resend OTP

**Endpoint:** `POST /api/auth/resend-otp`

**Request Payload:**

```typescript
{
  email: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
}
```

---

### 1.5 Forgot Password

**Endpoint:** `POST /api/auth/forgot-password`

**Request Payload:**

```typescript
{
  email: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
}
```

---

### 1.6 Verify Reset OTP

**Endpoint:** `POST /api/auth/verify-reset-otp`

**Request Payload:**

```typescript
{
  email: string;
  otpCode: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
}
```

---

### 1.7 Reset Password

**Endpoint:** `POST /api/auth/reset-password`

**Request Payload:**

```typescript
{
  email: string;
  otpCode: string;
  newPassword: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
}
```

---

## 2. Dashboard & KPI

### 2.1 Get KPI Summary

**Calculated on client from tasks data**

**KPIs Included:**

- Current month tasks (total, completed, percentage)
- Monthly summary (total, completed, target vs accomplishment)
- Epic-based summaries (total, completed, percentage, start/end dates, assigned users)
- Overdue tasks list

**Filters:**

- Filter by team member
- Filter by epic
- Date range filter

---

## 3. Tasks Management

### 3.1 Get Tasks

**Endpoint:** `GET /api/tasks?limit=10000`

**Response:**

```typescript
{
  success: boolean;
  data?: {
    tasks: Task[];
    total: number;
    epicCounts: EpicCounts;
  };
  error?: string;
}
```

**Task Interface:**

```typescript
interface Task {
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
  status: "pending" | "in_progress" | "completed";
  isOverdue: boolean;
  assignedTo?: string[];
  attachments?: Attachment[];
  comments?: Comment[];
  images?: string[];
  createdAt: string;
  updatedAt: string;
}
```

---

### 3.2 Create Tasks (Bulk)

**Endpoint:** `POST /api/tasks/bulk`

**Request Payload:**

```typescript
{
  tasks: CreateTaskInput[];
}

interface CreateTaskInput {
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
```

**Response:**

```typescript
{
  success: boolean;
  data?: Task[];
  error?: string;
}
```

---

### 3.3 Update Task

**Endpoint:** `PUT /api/tasks/:id`

**Request Payload:** Partial<Task>

**Response:**

```typescript
{
  success: boolean;
  data?: Task;
  error?: string;
}
```

---

### 3.4 Bulk Update Tasks

**Endpoint:** `PUT /api/tasks/bulk-update`

**Request Payload:**

```typescript
{
  taskIds: string[];
  updates: Partial<Task>;
}
```

**Response:**

```typescript
{
  success: boolean;
  data?: Task[];
  error?: string;
}
```

---

### 3.5 Delete Task

**Endpoint:** `DELETE /api/tasks/:id`

**Response:**

```typescript
{
  success: boolean;
  error?: string;
}
```

---

### 3.6 Bulk Delete Tasks

**Endpoint:** `DELETE /api/tasks`

**Request Payload:**

```typescript
{
  taskIds: string[];
}
```

**Response:**

```typescript
{
  success: boolean;
  data?: { deletedCount: number };
  error?: string;
}
```

---

### 3.7 Get Comments for Task

**Endpoint:** `GET /api/comments/:taskId`

**Response:**

```typescript
{
  success: boolean;
  data?: Comment[];
  error?: string;
}
```

**Comment Interface:**

```typescript
interface Comment {
  id: string;
  taskId?: string;
  epicName?: string;
  epicId?: string;
  userId: string;
  userName?: string;
  userEmail?: string;
  parentCommentId?: string;
  content: string;
  mentions: Array<{ type: "user" | "task"; id: string }>;
  replies?: Comment[];
  reactions?: Reaction[];
  createdAt: string;
  updatedAt: string;
}

interface Reaction {
  userId: string;
  userName?: string;
  type: "like" | "love" | "laugh";
}
```

---

### 3.8 Add Comment

**Endpoint:** `POST /api/comments`

**Request Payload:**

```typescript
{
  taskId?: string;
  epicName?: string;
  epicId?: string;
  content: string;
  parentCommentId?: string;
  mentions?: Array<{ type: "user" | "task"; id: string }>;
}
```

**Response:**

```typescript
{
  success: boolean;
  data?: Comment;
  error?: string;
}
```

---

### 3.9 Delete Comment

**Endpoint:** `DELETE /api/comments/:id`

**Response:**

```typescript
{
  success: boolean;
  error?: string;
}
```

---

### 3.10 Toggle Reaction on Comment

**Endpoint:** `POST /api/comments/:id/reaction`

**Request Payload:**

```typescript
{
  type: "like" | "love" | "laugh";
}
```

**Response:**

```typescript
{
  success: boolean;
  data?: Reaction[];
  error?: string;
}
```

---

### 3.11 Get Epics

**Endpoint:** `GET /api/epics`

**Response:**

```typescript
{
  success: boolean;
  data?: Epic[];
  error?: string;
}

interface Epic {
  id: string;
  businessId: string;
  name: string;
  description?: string;
  status: "active" | "completed" | "archived";
  createdAt: string;
  updatedAt: string;
}
```

---

## 4. Team Management

### 4.1 Get Team Members

**Endpoint:** `GET /api/team`

**Response:**

```typescript
{
  success: boolean;
  data?: TeamMember[];
  error?: string;
}

interface TeamMember {
  id: string;
  name: string;
  email: string;
  role: "admin" | "manager" | "member";
  status: "active" | "invited" | "inactive";
  joinedAt?: string;
}
```

---

### 4.2 Invite Team Member

**Endpoint:** `POST /api/team/invite`

**Request Payload:**

```typescript
{
  name: string;
  email: string;
  role: "admin" | "manager" | "member";
}
```

**Response:**

```typescript
{
  success: boolean;
  data?: TeamMember;
  error?: string;
}
```

---

### 4.3 Update Member Status

**Endpoint:** `PUT /api/team/:id/status`

**Request Payload:**

```typescript
{
  status: "active" | "inactive";
}
```

**Response:**

```typescript
{
  success: boolean;
  error?: string;
}
```

---

### 4.4 Delete Team Member

**Endpoint:** `DELETE /api/team/:id`

**Response:**

```typescript
{
  success: boolean;
  error?: string;
}
```

---

## 5. Wallet & Payments

### 5.1 Get Wallet Info

**Endpoint:** `GET /api/wallet`

**Response:**

```typescript
{
  user_wallet: Wallet;
  business_wallet?: BusinessWallet;
}

interface Wallet {
  id: string;
  balance: number;
  currency: string;
  account_number: string;
  bank_name: string;
  type: "user" | "business";
}

interface BusinessWallet extends Wallet {
  business_name: string;
}
```

---

### 5.2 Fund Wallet via Card

**Endpoint:** `POST /api/wallet/fund/card`

**Request Payload:**

```typescript
{
  amount: number;
  wallet_type: "business" | "user";
}
```

**Response:**

```typescript
{
  payment_url?: string;
  success?: boolean;
  message?: string;
}
```

---

### 5.3 Create Business Wallet

**Endpoint:** `POST /api/wallet/business/create`

**Request Payload:**

```typescript
{
  gtb_account_number: string;
  business_name: string;
  kycReferenceId?: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 5.4 Create Virtual Account

**Endpoint:** `POST /api/wallet/create-virtual-account`

**Response:**

```typescript
{
  message: string;
  success?: boolean;
}
```

---

### 5.5 Submit Business KYC

**Endpoint:** `POST /api/kyc/business`

**Request:** `multipart/form-data`

- country: string
- state: string
- city: string
- street: string
- house_number: string
- proof_of_address: File (PDF, JPG, PNG)

**Response:**

```typescript
{
  success: boolean;
  message: string;
  kycId: string;
}
```

---

### 5.6 Initiate KYC (BVN/NIN)

**Endpoint:** `POST /api/kyc/initiate`

**Request Payload:**

```typescript
{
  type: "bvn" | "nin";
  number: string;
}
```

**Response:**

```typescript
{
  message: string;
}
```

---

### 5.7 Verify KYC OTP

**Endpoint:** `POST /api/kyc/verify-otp`

**Request Payload:**

```typescript
{
  otp: string;
}
```

**Response:**

```typescript
{
  message: string;
  success: boolean;
}
```

---

### 5.8 Get KYC Status

**Endpoint:** `GET /api/kyc/status`

**Response:**

```typescript
{
  user_kyc_status: "none" | "pending" | "verified" | "rejected";
  business_kyc_status: "none" | "pending" | "verified" | "rejected";
  bvn_verified: boolean;
  nin_verified: boolean;
}
```

---

### 5.9 Get Banks

**Endpoint:** `GET /api/transfers/banks`

**Response:**

```typescript
{
  success: boolean;
  data: Array<{ code: string; name: string }>;
}
```

---

### 5.10 Resolve Account

**Endpoint:** `POST /api/transfers/lookup`

**Request Payload:**

```typescript
{
  bankCode: string;
  accountNumber: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  data: {
    account_name: string;
  }
}
```

---

### 5.11 Request Transfer OTP

**Endpoint:** `POST /api/transfers/otp/request`

**Request Payload:**

```typescript
{
  wallet_id?: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message: string;
  fee_charged?: number;
}
```

---

### 5.12 Single Transfer with OTP

**Endpoint:** `POST /api/transfers/single`

**Request Payload:**

```typescript
{
  bankCode: string;
  accountNumber: string;
  accountName: string;
  amount: number;
  remark: string;
  otp: string;
  wallet_id: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message: string;
}
```

---

### 5.13 Bulk Transfer with OTP

**Endpoint:** `POST /api/transfers/bulk`

**Request Payload:**

```typescript
{
  type: "salary" | "manual" | "sprint" | "task";
  source_wallet_id: string;
  otp: string;
  data: {
    items: Array<{
      amount: number;
      bankCode: string;
      accountNumber: string;
    }>;
  }
}
```

**Response:**

```typescript
{
  success: boolean;
  message: string;
}
```

---

### 5.14 Get Transfer History

**Endpoint:** `GET /api/transfers`

**Query Params:**

- search?: string
- status?: string
- startDate?: string
- endDate?: string
- page?: number
- limit?: number

**Response:**

```typescript
{
  success: boolean;
  data: Transfer[];
  pagination?: {
    total: number;
    page: number;
    limit: number;
  };
}

interface Transfer {
  id: string;
  amount: number;
  currency: string;
  status: "pending" | "success" | "failed";
  recipient_name: string;
  failure_reason?: string;
  created_at: string;
}
```

---

### 5.15 Retry Transfer

**Endpoint:** `POST /api/transfers/:id/retry`

**Response:**

```typescript
{
  success: boolean;
}
```

---

## 6. Payroll Management

### 6.1 Get Payroll Summary

**Endpoint:** `GET /api/payroll/summary`

**Query Params:**

- search?: string
- role?: string
- startDate?: string
- endDate?: string
- page?: number
- limit?: number

**Response:**

```typescript
{
  success: boolean;
  payroll?: PayrollEmployee[];
}

interface PayrollEmployee {
  id: string;
  name: string;
  email: string;
  salary: number | string;
  salary_currency: string;
  bank_account_number?: string | null;
  bank_code?: string | null;
  account_name?: string | null;
  role: string;
  bonuses_total: number;
  deductions_total: number;
  net_salary: number;
  next_pay_date: string;
  salary_calculation_status: string;
  adjustments?: {
    bonuses: number;
    deductions: number;
    bonus_list: AdjustmentItem[];
    deduction_list: AdjustmentItem[];
  };
}

interface AdjustmentItem {
  user_id: string;
  type: "bonus" | "deduction";
  amount: string;
  currency: string;
}
```

---

### 6.2 Get Payroll Config

**Endpoint:** `GET /api/payroll/config`

**Response:**

```typescript
{
  success: boolean;
  config: PayrollConfig;
}

interface PayrollConfig {
  salary_interval: "daily" | "weekly" | "monthly" | "yearly" | "custom";
  salary_custom_date?: string | null;
}
```

---

### 6.3 Update Payroll Config

**Endpoint:** `PUT /api/payroll/config`

**Request Payload:**

```typescript
{
  salary_interval: "daily" | "weekly" | "monthly" | "yearly" | "custom";
  salary_custom_date?: string | null;
}
```

**Response:**

```typescript
{
  success: boolean;
  message: string;
  config?: PayrollConfig;
}
```

---

### 6.4 Update Employee Payroll

**Endpoint:** `PUT /api/payroll/user/:id`

**Request Payload:**

```typescript
{
  salary: number;
  salary_currency: string;
  bank_code: string;
  account_number: string;
  account_name?: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 6.5 Add Payroll Adjustment

**Endpoint:** `POST /api/payroll/adjustments`

**Request Payload:**

```typescript
{
  userId: string;
  type: "bonus" | "deduction";
  amount: number;
  reason: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 6.6 Get Adjustments for User

**Endpoint:** `GET /api/payroll/adjustments?userId=:userId`

**Response:**

```typescript
{
  success: boolean;
  adjustments: PayrollAdjustment[];
}

interface PayrollAdjustment {
  id: string;
  business_id: string;
  user_id: string;
  type: "bonus" | "deduction";
  amount: string;
  currency: string;
  reason: string;
  status: "pending" | "processed";
  transfer_id?: string | null;
  created_at: string;
  updated_at: string;
  processed_at?: string | null;
  user_name?: string;
  user_email?: string;
}
```

---

### 6.7 Delete Adjustment

**Endpoint:** `DELETE /api/payroll/adjustments/:id`

**Response:**

```typescript
{
  success: boolean;
  message?: string;
}
```

---

## 7. Subscription & Billing

### 7.1 Get Current Subscription

**Endpoint:** `GET /api/subscription/current`

**Response:**

```typescript
{
  success: boolean;
  subscription?: Subscription;
}

interface Subscription {
  id: string;
  name: string;
  subscription_status: "active" | "cancelled" | "past_due";
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
```

---

### 7.2 Get Plans

**Endpoint:** `GET /api/subscription/plans`

**Response:**

```typescript
{
  success: boolean;
  plans?: Plan[];
}

interface Plan {
  id: string;
  name: string;
  price: number;
  discount?: string;
  duration?: "monthly" | "yearly";
  currency?: string;
  description: string;
  features: string[];
  max_team_members: number;
  trial_days: number;
}
```

---

### 7.3 Get Saved Cards

**Endpoint:** `GET /api/subscription/cards`

**Response:**

```typescript
{
  success: boolean;
  cards?: Card[];
}

interface Card {
  id: string;
  last4: string;
  card_type: string;
  exp_month: string;
  exp_year: string;
  is_active: boolean;
}
```

---

### 7.4 Initiate Payment (Upgrade)

**Endpoint:** `POST /api/subscription/initiate-payment`

**Request Payload:**

```typescript
{
  planId: string;
  currency: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  checkout_url?: string;
  error?: string;
}
```

---

### 7.5 Cancel Subscription

**Endpoint:** `POST /api/subscription/cancel`

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 7.6 Downgrade to Free

**Endpoint:** `POST /api/subscription/downgrade`

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 7.7 Add Card

**Endpoint:** `POST /api/subscription/cards/initiate`

**Response:**

```typescript
{
  success: boolean;
  checkout_url?: string;
  error?: string;
}
```

---

### 7.8 Remove Card

**Endpoint:** `DELETE /api/subscription/cards/:id`

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 7.9 Set Active Card

**Endpoint:** `PUT /api/subscription/cards/:id/active`

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 7.10 Get Transaction History

**Endpoint:** `GET /api/subscription/transactions`

**Query Params:**

- page?: number
- perPage?: number
- search?: string
- status?: string
- startDate?: string
- endDate?: string

**Response:**

```typescript
{
  success: boolean;
  transactions?: PaymentTransaction[];
  pagination?: {
    totalPages?: number;
  };
  meta?: {
    last_page?: number;
  };
}

interface PaymentTransaction {
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
```

---

### 7.11 Export Transactions

**Endpoint:** `GET /api/subscription/transactions/export`

**Query Params:**

- startDate?: string
- endDate?: string

**Response:** CSV file download

---

## 8. Settings

### 8.1 Get Settings

**Endpoint:** `GET /api/settings`

**Response:**

```typescript
{
  success: boolean;
  settings?: BusinessProfile;
  error?: string;
}

interface BusinessProfile {
  id: string;
  name: string;
  email: string;
  phone_number: string;
  industry: string;
  logo_url: string;
  currency: string;
}
```

---

### 8.2 Update Settings

**Endpoint:** `PUT /api/settings`

**Request Payload:**

```typescript
{
  name?: string;
  industry?: string;
  logo_url?: string;
  currency?: "NGN" | "USD";
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 8.3 Request Contact Update OTP

**Endpoint:** `POST /api/settings/update-contact/request-otp`

**Request Payload:**

```typescript
{
  type: "email" | "phone";
  value: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 8.4 Verify Contact Update OTP

**Endpoint:** `POST /api/settings/update-contact/verify-otp`

**Request Payload:**

```typescript
{
  otp: string;
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 8.5 Get OTP Preference

**Endpoint:** `GET /api/settings/otp-preference`

**Response:**

```typescript
{
  success: boolean;
  preference: "email" | "sms" | "both";
  error?: string;
}
```

---

### 8.6 Update OTP Preference

**Endpoint:** `PUT /api/settings/otp-preference`

**Request Payload:**

```typescript
{
  preference: "email" | "sms" | "both";
}
```

**Response:**

```typescript
{
  success: boolean;
  message?: string;
  error?: string;
}
```

---

### 8.7 Get Fee Schedule

**Endpoint:** `GET /api/fees`

**Response:**

```typescript
{
  success: boolean;
  data?: FeeConfig[];
  error?: string;
}

interface FeeConfig {
  id: string;
  name: string;
  fee_type: string;
  config_type: "flat" | "percentage_cap" | "flat_conditional" | "range";
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
```

---

## 9. Other Features

### 9.1 Ideas Management

**Endpoints (implied):**

- `GET /api/ideas` - List ideas
- `POST /api/ideas` - Create idea
- `PUT /api/ideas/:id/status` - Update idea status

**Idea Interface:**

```typescript
interface Idea {
  id: string;
  businessId: string;
  userId: string;
  userName?: string;
  title: string;
  description: string;
  status: "under_review" | "executed" | "rejected";
  createdAt: string;
  updatedAt: string;
}
```

---

### 9.2 Ranking

- Display team members ranked by task completion rate
- Shows overall and per-member performance
- Filterable by different time periods

---

### 9.3 Backlog

- Tasks organized by epic
- Kanban-style or list view
- Filterable and searchable

---

### 9.4 Activity Logs

- Track all user and system activities
- Filterable by user, action type, date range

---

### 9.5 Accept Invite

**Endpoint:** `GET /accept-invite/:token`

Flow:

1. User clicks invite link
2. System validates token
3. User creates account or logs in
4. Joins the team

---

## Authentication Headers

All authenticated requests must include:

```
Authorization: Bearer <token>
```

## Local Storage (for mobile)

Store:

- token
- userId
- businessId
- userName

## Date Formats

All dates are in ISO 8601 format: `YYYY-MM-DDTHH:mm:ss.sssZ`

## Currency

Primary currencies: NGN (Nigerian Naira), USD (US Dollar)

## Error Responses

All error responses follow:

```typescript
{
  success: boolean;
  error?: string;
  message?: string;
}
```

---

## Mobile-Specific Considerations

1. **State Management**: Use AsyncStorage for persistent storage
2. **Image Uploads**: Use React Native's ImagePicker or DocumentPicker
3. **Push Notifications**: Implement for OTP, transfers, task updates
4. **Offline Support**: Cache frequently accessed data
5. **Biometric Auth**: Add fingerprint/face ID for secure access
6. **Deep Linking**: For payment callbacks and invite links
