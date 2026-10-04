# Payroll Feature Documentation

## Overview

The payroll feature provides comprehensive salary management capabilities including single and bulk salary transfers, epic-based transfers, payroll configuration, and salary adjustments.

## Feature Architecture

### Main Components

1. **Payroll Screen** - Employee list, salary management, adjustments
2. **Bulk Transfer Screen** - Salary and epic transfer initiation
3. **Transfers Screen** - Transfer history and monitoring
4. **API Service** - Backend integration layer
5. **Data Models** - Employee, PayrollConfig, PayrollAdjustment, Transfer

## Data Models

### Employee Model

```dart
class Employee {
  final String id;
  final String name;
  final String email;
  final dynamic salary;
  final String salaryCurrency;
  final String? bankAccountNumber;
  final String? bankCode;
  final String? accountName;
  final String role;
  final int? bonusesTotal;
  final int? deductionsTotal;
  final double netSalary;
  final String? nextPayDate;
  final String? salaryCalculationStatus;
  final String? contractStartDate;
  final Adjustments? adjustments;
}
```

### PayrollConfig Model

```dart
class PayrollConfig {
  final String salaryInterval;
  final String? salaryCustomDate;
}
```

### PayrollAdjustment Model

```dart
class PayrollAdjustment {
  final String id;
  final String businessId;
  final String userId;
  final String type;
  final String amount;
  final String currency;
  final String reason;
  final String status;
  final String? transferId;
  final String createdAt;
  final String updatedAt;
  final String? processedAt;
  final String? userName;
  final String? userEmail;
}
```

### Transfer Model

```dart
class Transfer {
  final String id;
  final String recipientName;
  final String recipientAccount;
  final String recipientBank;
  final double amount;
  final String currency;
  final String status;
  final String createdAt;
  final String? failureReason;
}
```

## API Endpoints

### Payroll Endpoints

#### 1. Get Payroll Summary

**Endpoint:** `GET /payroll/summary`

**Query Parameters:**
- `page` (number, default: 1) - Page number
- `limit` (number, default: 20) - Items per page
- `search` (string, optional) - Search employees by name or email
- `role` (string, optional) - Filter by role
- `startDate` (string, optional) - Filter start date
- `endDate` (string, optional) - Filter end date

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "emp-001",
      "name": "John Doe",
      "email": "john@example.com",
      "salary": 50000,
      "salary_currency": "NGN",
      "bank_account_number": "0123456789",
      "bank_code": "044",
      "account_name": "JOHN DOE",
      "role": "developer",
      "bonuses_total": 5000,
      "deductions_total": 2000,
      "net_salary": 53000,
      "next_pay_date": "2024-01-31",
      "salary_calculation_status": "ready",
      "contract_start_date": "2023-01-15",
      "adjustments": {
        "bonuses": 1,
        "deductions": 1,
        "bonus_list": [
          {
            "userId": "emp-001",
            "type": "bonus",
            "amount": "5000",
            "currency": "NGN"
          }
        ],
        "deduction_list": [
          {
            "userId": "emp-001",
            "type": "deduction",
            "amount": "2000",
            "currency": "NGN"
          }
        ]
      }
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalPages": 5,
    "totalItems": 100
  }
}
```

#### 2. Get Payroll Config

**Endpoint:** `GET /payroll/config`

**Response:**
```json
{
  "success": true,
  "data": {
    "salary_interval": "monthly",
    "salary_custom_date": null
  }
}
```

#### 3. Update Payroll Config

**Endpoint:** `PUT /payroll/config`

**Request Body:**
```json
{
  "salary_interval": "monthly|weekly|biweekly|daily|yearly|custom",
  "salary_custom_date": "2024-01-15T09:00:00.000Z"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Payroll configuration updated"
}
```

#### 4. Update Payroll User

**Endpoint:** `PUT /payroll/user/{id}`

**Request Body:**
```json
{
  "salary": 60000,
  "salary_currency": "NGN",
  "bank_account_number": "0123456789",
  "bank_code": "044",
  "account_name": "JOHN DOE",
  "contract_start_date": "2023-01-15"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Employee payroll details updated"
}
```

#### 5. Add Payroll Adjustment

**Endpoint:** `POST /payroll/adjustments`

**Request Body:**
```json
{
  "userId": "emp-001",
  "type": "bonus|deduction",
  "amount": 5000,
  "currency": "NGN",
  "reason": "Performance bonus"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Adjustment added successfully"
}
```

#### 6. Get Payroll Adjustments

**Endpoint:** `GET /payroll/adjustments`

**Query Parameters:**
- `userId` (string, optional) - Filter by user ID

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "adj-001",
      "business_id": "biz-001",
      "user_id": "emp-001",
      "type": "bonus",
      "amount": "5000",
      "currency": "NGN",
      "reason": "Performance bonus",
      "status": "pending|processed|failed",
      "transfer_id": null,
      "created_at": "2024-01-10T10:00:00.000Z",
      "updated_at": "2024-01-10T10:00:00.000Z",
      "processed_at": null,
      "user_name": "John Doe",
      "user_email": "john@example.com"
    }
  ]
}
```

#### 7. Delete Payroll Adjustment

**Endpoint:** `DELETE /payroll/adjustments/{id}`

**Response:**
```json
{
  "success": true,
  "message": "Adjustment deleted"
}
```

### Transfer Endpoints

#### 8. Get Banks

**Endpoint:** `GET /transfers/banks`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "code": "044",
      "name": "Access Bank"
    }
  ]
}
```

#### 9. Resolve Account

**Endpoint:** `POST /transfers/account-lookup`

**Request Body:**
```json
{
  "bank_code": "044",
  "account_number": "0123456789"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "account_name": "JOHN DOE"
  }
}
```

#### 10. Request Transfer OTP

**Endpoint:** `POST /transfers/otp/request`

**Request Body:**
```json
{
  "wallet_id": "wallet-001"
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP sent successfully"
}
```

#### 11. Single Transfer

**Endpoint:** `POST /transfers/single`

**Request Body:**
```json
{
  "type": "salary|manual",
  "otp": "123456",
  "source_wallet_id": "wallet-001",
  "recipient_account": "0123456789",
  "recipient_bank": "044",
  "recipient_name": "JOHN DOE",
  "amount": 53000,
  "remark": "Salary Payment",
  "source_type": "salary|epic",
  "source_id": ""
}
```

**Response:**
```json
{
  "success": true,
  "message": "Transfer initiated successfully"
}
```

#### 12. Bulk Transfer

**Endpoint:** `POST /transfers/bulk`

**Request Body:**
```json
{
  "type": "salary|manual",
  "otp": "123456",
  "source_wallet_id": "wallet-001",
  "items": [
    {
      "recipient_account": "0123456789",
      "recipient_bank": "044",
      "recipient_name": "JOHN DOE",
      "amount": 53000,
      "remark": "Salary Payment",
      "source_type": "salary",
      "source_id": ""
    }
  ],
  "transfers": [
    {
      "recipient_account": "0123456789",
      "recipient_bank": "044",
      "recipient_name": "JOHN DOE",
      "amount": 53000,
      "remark": "Salary Payment",
      "source_type": "salary",
      "source_id": ""
    }
  ],
  "data": {
    "items": [
      {
        "recipient_account": "0123456789",
        "recipient_bank": "044",
        "recipient_name": "JOHN DOE",
        "amount": 53000,
        "remark": "Salary Payment",
        "source_type": "salary",
        "source_id": ""
      }
    ],
    "transfers": [
      {
        "recipient_account": "0123456789",
        "recipient_bank": "044",
        "recipient_name": "JOHN DOE",
        "amount": 53000,
        "remark": "Salary Payment",
        "source_type": "salary",
        "source_id": ""
      }
    ]
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Bulk transfer initiated successfully"
}
```

#### 13. Get Transfers

**Endpoint:** `GET /transfers`

**Query Parameters:**
- `page` (number, default: 1)
- `limit` (number, default: 20)
- `status` (string, optional) - pending|success|failed
- `search` (string, optional) - Search by recipient name

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "trans-001",
      "recipient_name": "JOHN DOE",
      "recipient_account": "0123456789",
      "recipient_bank": "044",
      "amount": 53000,
      "currency": "NGN",
      "status": "pending|success|failed",
      "created_at": "2024-01-15T10:00:00.000Z",
      "failure_reason": null
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalPages": 5,
    "totalItems": 100
  }
}
```

#### 14. Retry Transfer

**Endpoint:** `POST /transfers/{id}/retry`

**Response:**
```json
{
  "success": true,
  "message": "Transfer retry initiated"
}
```

#### 15. Export Transactions

**Endpoint:** `GET /subscription/transactions/export`

**Query Parameters:**
- `status` (string, optional) - Filter by status

**Response:** CSV data as text

### Wallet Endpoints

#### 16. Get Wallet

**Endpoint:** `GET /wallet`

**Response:**
```json
{
  "success": true,
  "business_wallet": {
    "id": "wallet-001",
    "balance": 500000,
    "currency": "NGN"
  },
  "user_wallet": {
    "id": "wallet-002",
    "balance": 100000,
    "currency": "NGN"
  }
}
```

### Epic Endpoints

#### 17. Get Epics

**Endpoint:** `GET /epics`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "epic-001",
      "name": "Q1 2024 Project",
      "description": "First quarter deliverables"
    }
  ]
}
```

## User Flows

### 1. Payroll Management Flow

```
Payroll Screen
├── Fetch Payroll Summary & Config
├── View Employee List
│   ├── Search & Filter
│   ├── Pagination
│   └── View Total Net Pay
├── Employee Details
│   ├── View Salary Breakdown
│   ├── View Adjustments
│   └── Edit Employee
├── Adjustments
│   ├── Add Bonus/Deduction
│   ├── View Adjustment List
│   └── Delete Adjustment
└── Configure Payroll
    ├── Set Salary Interval
    └── Set Custom Date (if applicable)
```

### 2. Salary Transfer Flow

```
Bulk Transfer Screen
├── Select Transfer Type: Salary
├── Fetch Data (Employees, Wallets, Banks)
├── Select Source Wallet
├── Review Employees & Net Salary
├── View Transfer Summary
├── Request OTP
├── Enter OTP
└── Initiate Bulk Salary Transfer
    └── Each employee receives netSalary to their bank account
```

### 3. Epic Transfer Flow

```
Bulk Transfer Screen
├── Select Transfer Type: Epic
├── Select Transfer Mode: Single or Bulk
├── Select Epic
├── Add Recipient(s)
│   ├── Select Bank
│   ├── Enter Account Number
│   ├── Verify Account Name
│   └── Enter Amount
├── Select Source Wallet
├── View Transfer Summary
├── Request OTP
├── Enter OTP
└── Initiate Epic Transfer
    └── Linked to selected epic ID with epic remark
```

### 4. Single Transfer Flow

```
Bulk Transfer Screen (Epic mode, Single)
├── Select Epic
├── Add Single Recipient
│   ├── Select Bank
│   ├── Enter Account Number
│   ├── Verify Account Name
│   └── Enter Amount
├── Select Wallet
├── Request OTP
├── Enter OTP
└── Initiate Single Transfer
```

### 5. Bulk Transfer Flow

```
Bulk Transfer Screen (Epic mode, Bulk)
├── Select Epic
├── Add Multiple Recipients
│   └── For each recipient:
│       ├── Select Bank
│       ├── Enter Account Number
│       ├── Verify Account Name
│       └── Enter Amount
├── Select Wallet
├── View Summary (Total Amount & Recipient Count)
├── Request OTP
├── Enter OTP
└── Initiate Bulk Transfer
```

### 6. Transfer History Flow

```
Transfers Screen
├── Fetch Transfers (Paginated)
├── Filter by Status (All/Pending/Success/Failed)
├── Search Transfers
├── View Transfer Cards
│   ├── Recipient Name
│   ├── Amount
│   ├── Status
│   └── Date
├── Retry Failed Transfers
├── Export to CSV
└── View Transfer Detail
```

## Key Features

### 1. Salary Intervals

Supported intervals:
- **daily** - Daily salary payments
- **weekly** - Weekly salary payments
- **monthly** - Monthly salary payments (default)
- **yearly** - Annual salary payments
- **custom** - Custom date and time for payroll

### 2. Adjustment Types

- **Bonus** - Positive adjustment (increases net salary)
- **Deduction** - Negative adjustment (decreases net salary)

### 3. Transfer Types

- **Salary** - Automated transfers to all employees based on payroll data
- **Epic** - Manual transfers linked to a specific epic/project

### 4. Transfer Modes (Epic only)

- **Single** - Transfer to one recipient
- **Bulk** - Transfer to multiple recipients

### 5. Transfer Statuses

- **pending** - Transfer queued for processing
- **success** - Transfer completed successfully
- **failed** - Transfer failed (can retry)

## Integration Points

### API Service Integration

All API calls are managed through `ApiService` class in `/lib/services/api.dart`:

- Uses Dio for HTTP requests
- Automatic Bearer token injection
- Response success/failure handling
- Session expiry detection
- Toast notifications for user feedback
- Error handling for plan upgrade requirements

### State Management

- Uses Flutter Riverpod for state management
- Component local state for forms and modals
- Shared preferences for token storage

### Navigation

Uses GoRouter for navigation:
- `/main` - Main dashboard
- `/main/bulk-transfer` - Bulk transfer screen
- `/main/transfer-detail` - Transfer detail screen

## Error Handling

### Common Errors

1. **Plan Upgrade Required** - When accessing payroll features without sufficient plan
2. **Invalid Token** - Session expired, triggers logout
3. **Insufficient Balance** - Wallet has insufficient funds
4. **Invalid OTP** - Wrong OTP entered
5. **Account Verification Failed** - Invalid bank account details

### Error States

Each screen handles loading, error, and empty states with appropriate UI feedback.

## Business Rules

1. **Net Salary Calculation**: Base salary + total bonuses - total deductions
2. **OTP Requirement**: All transfers require OTP verification
3. **Source Wallet Selection**: Can choose between business wallet or user wallet
4. **Adjustments**: Can only be added/removed before salary transfer
5. **Epic Linking**: Epic transfers are tagged with epic ID for tracking

## Files

- `/lib/screens/payroll_screen.dart` - Payroll management UI
- `/lib/screens/bulk_transfer_screen.dart` - Transfer initiation UI
- `/lib/screens/transfers_screen.dart` - Transfer history UI
- `/lib/services/api.dart` - API service integration
- `/lib/models/employee.dart` - Employee data model
- `/lib/models/payroll_config.dart` - Payroll config model
- `/lib/models/payroll_adjustment.dart` - Payroll adjustment model
- `/lib/models/transfer.dart` - Transfer data model
- `/test_payroll_wallet.dart` - Test script for API endpoints