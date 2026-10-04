
# Bulk Transfer Flow Documentation

## Overview

The bulk transfer flow enables users to initiate both salary and epic-based transfers in bulk with proper OTP verification. This feature supports two main transfer types: salary transfers to employees and epic transfers (single or bulk) to external recipients.

## Feature Architecture

### Main Components

1. **Bulk Transfer Screen** - `/lib/screens/bulk_transfer_screen.dart`
   - Transfer type selection (salary/epic)
   - Transfer mode selection (single/bulk for epic)
   - Recipient management
   - Account verification
   - OTP handling
   - Transfer summary display

2. **API Service** - `/lib/services/api.dart`
   - Backend integration for all transfer operations

3. **Data Models**
   - Employee
   - Epic
   - Bank
   - Wallet
   - Recipient (internal model)

## Data Flow

### Initialization Flow

```
User opens Bulk Transfer Screen
    ↓
_initState() called
    ↓
_fetchData() initiated
    ↓
Parallel API calls:
    ├── getPayrollSummary() - Fetch employee data
    ├── getWallet() - Fetch business/user wallets
    ├── getEpics() - Fetch available epics
    └── getBanks() - Fetch supported banks
    ↓
Data loaded, UI rendered
```

### Transfer Type Selection

```
User selects transfer type: [Salary | Epic]
    ↓
State updates: _transferType
    ↓
If Salary selected:
    └── Shows employee list with net salaries
    ↓
If Epic selected:
    ├── Shows transfer mode selection [Single | Bulk]
    ├── Shows epic selector
    └── Recipient management UI
```

### Recipient Management (Epic Mode)

```
Add Recipient
    ↓
_createRecipient()
    ↓
New Recipient added to _recipients list
    ↓
For each recipient:
    ├── Select Bank (from _banks list)
    ├── Enter Account Number
    ├── Click "Verify"
    │   └── _resolveAccountName(recipientId)
    │       ├── POST /transfers/account-lookup
    │       └── Updates recipient.recipientName if successful
    └── Enter Amount
```

### OTP Request Flow

```
User clicks "Request OTP"
    ↓
_handleRequestOtp()
    ↓
Validation checks:
    ├── Wallet selected?
    ├── If Epic: Epic selected?
    ├── If Epic: All recipients have valid details?
    ↓
Validation Passed?
    ├── Yes → POST /transfers/otp/request (wallet_id)
    │   └── Success: Show OTP modal, start countdown
    └── No → Show error snackbar
```

### Transfer Initiation Flow

```
User enters OTP and clicks "Initiate Transfer"
    ↓
_handleInitiateTransfer()
    ↓
Validation checks:
    ├── Wallet selected?
    ├── OTP is 6 digits?
    ├── If Epic: Epic selected?
    ├── If Epic: All recipients valid?
    ↓
Prepare transfers data:
    ├── Salary mode: Map employees to transfer items
    │   ├── recipient_account: emp.bankAccountNumber
    │   ├── recipient_bank: emp.bankCode
    │   ├── recipient_name: emp.name
    │   ├── amount: emp.netSalary
    │   ├── remark: "Salary Payment"
    │   └── source_type: "salary"
    │
    └── Epic mode: Map _recipients to transfer items
        ├── recipient_account: r.recipientAccount
        ├── recipient_bank: r.recipientBank
        ├── recipient_name: r.recipientName
        ├── amount: r.amount
        ├── remark: r.remark (epic name)
        ├── source_type: "epic"
        └── source_id: _selectedEpic!.id
    ↓
Build payload with:
    ├── type: "salary" | "manual"
    ├── otp: _otp
    ├── source_wallet_id: wallet.id
    ├── items: transfersData[]
    ├── transfers: transfersData[]
    └── data: { items, transfers }
    ↓
POST /transfers/bulk
    ↓
Success: Show success dialog, navigate back
    ↓
Error: Show error snackbar
```

## API Endpoints Used

### 1. Get Payroll Summary
**Endpoint:** `GET /payroll/summary`  
**Purpose:** Fetch employee data for salary transfers

### 2. Get Wallet
**Endpoint:** `GET /wallet`  
**Purpose:** Fetch business and user wallet details

### 3. Get Epics
**Endpoint:** `GET /epics`  
**Purpose:** Fetch available epics for epic transfers

### 4. Get Banks
**Endpoint:** `GET /transfers/banks`  
**Purpose:** Fetch list of supported banks

### 5. Resolve Account
**Endpoint:** `POST /transfers/account-lookup`  
**Request:**
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

### 6. Request Transfer OTP
**Endpoint:** `POST /transfers/otp/request`  
**Request:**
```json
{
  "wallet_id": "wallet-001"
}
```

### 7. Bulk Transfer
**Endpoint:** `POST /transfers/bulk`  
**Request (Salary):**
```json
{
  "type": "salary",
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
  "transfers": [...],
  "data": { "items": [...], "transfers": [...] }
}
```

**Request (Epic):**
```json
{
  "type": "manual",
  "otp": "123456",
  "source_wallet_id": "wallet-001",
  "items": [
    {
      "recipient_account": "0123456789",
      "recipient_bank": "044",
      "recipient_name": "JOHN DOE",
      "amount": 10000,
      "remark": "Q1 2024 Project",
      "source_type": "epic",
      "source_id": "epic-001"
    }
  ],
  "transfers": [...],
  "data": { "items": [...], "transfers": [...] }
}
```

## UI Components

### State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_employees` | `List&lt;Employee&gt;` | List of employees for salary transfers |
| `_epics` | `List&lt;Epic&gt;` | List of available epics |
| `_wallets` | `Map&lt;String, dynamic&gt;` | Business and user wallet data |
| `_banks` | `List&lt;Bank&gt;` | List of supported banks |
| `_recipients` | `List&lt;Recipient&gt;` | List of recipients for epic transfers |
| `_selectedWallet` | `String` | "business" or "user" |
| `_transferType` | `String` | "salary" or "epic" |
| `_transferMode` | `String` | "single" or "bulk" (epic only) |
| `_selectedEpic` | `Epic?` | Selected epic for epic transfers |
| `_otp` | `String` | Entered OTP |
| `_showOtpModal` | `bool` | OTP modal visibility |
| `_otpCountdown` | `int` | OTP resend countdown |
| `_canResendOtp` | `bool` | Whether OTP can be resent |

### Recipient Model (Internal)

```dart
class Recipient {
  final String id;
  final String recipientAccount;
  final String recipientBank;
  final String recipientName;
  final String amount;
  final String remark;
  final String sourceType;
  final String sourceId;
}
```

## Key Features

### 1. Dual Transfer Types

**Salary Transfer:**
- Pre-populated with employee data
- Uses net salary from payroll
- Automatic remark: "Salary Payment"
- Source type: "salary"

**Epic Transfer:**
- Manual recipient entry
- Linked to selected epic
- Custom amounts per recipient
- Source type: "epic" with epic ID

### 2. Transfer Modes (Epic Only)

**Single Mode:**
- One recipient only
- Remove button hidden

**Bulk Mode:**
- Multiple recipients supported
- Add/remove recipients dynamically

### 3. Account Verification

- Bank selection from pre-loaded list
- Account number input
- One-click verification via API
- Verified account name displayed with success indicator

### 4. OTP Management

- 30-second countdown timer
- Resend option after countdown
- Modal-based OTP entry
- 6-digit OTP validation

### 5. Wallet Selection

- Business wallet (default)
- User wallet (personal)
- Displays wallet balance with currency
- Disabled button if no wallet selected

### 6. Transfer Summary

- Shows recipient count
- Calculates total amount
- Formats currency with commas

## User Flows

### Complete Salary Transfer Flow

```
1. Navigate to Bulk Transfer Screen
2. Select "Salary" transfer type
3. Wait for data to load (employees, wallets, banks)
4. Review employee list and net salaries
5. Select source wallet (business or user)
6. Review transfer summary
7. Click "Request OTP"
8. Wait for OTP to be sent (30s countdown starts)
9. Enter 6-digit OTP
10. Click "Initiate Transfer"
11. Wait for success confirmation
12. Dialog shown, navigate back on OK
```

### Complete Epic Transfer Flow (Bulk)

```
1. Navigate to Bulk Transfer Screen
2. Select "Epic" transfer type
3. Select "Bulk" transfer mode
4. Click "Select Epic" and choose an epic
5. Click "Add Recipient" to add first recipient
6. For each recipient:
   a. Click "Select Bank" and choose a bank
   b. Enter account number
   c. Click "Verify" to confirm account name
   d. Enter transfer amount
7. Repeat step 6 to add more recipients
8. Select source wallet
9. Review transfer summary
10. Click "Request OTP"
11. Enter OTP when received
12. Click "Initiate Transfer"
13. Wait for success confirmation
```

## Error Handling

### Validation Errors

1. **Wallet not found** - Shown when trying to request OTP without selecting wallet
2. **Please select an Epic** - Shown for epic transfers without epic selection
3. **Please fill in all recipient details** - Shown when recipient fields are incomplete
4. **Please enter a valid 6-digit OTP** - OTP validation failure

### API Errors

All API errors are:
- Caught and displayed as snackbars
- Use ApiService.extractErrorMessage()
- Show user-friendly messages

### Common Error Scenarios

| Scenario | Error Message |
|----------|---------------|
| Insufficient wallet balance | Backend error message |
| Invalid OTP | "Invalid OTP" |
| Account verification failed | Backend error message |
| Network error | "Something went wrong" |

## Business Rules

1. **OTP Required**: All transfers must be verified with OTP
2. **Wallet Selection**: Can choose between business or personal wallet
3. **Epic Linking**: Epic transfers must be linked to an epic
4. **Account Verification**: Recommended but not strictly enforced (user can skip)
5. **Amount Format**: Accepts numbers, converted to double for API
6. **Salary Transfers**: Uses pre-calculated net salary from payroll
7. **Remark Generation**: 
   - Salary: "Salary Payment"
   - Epic: Epic name (truncated if &gt;30 chars)

## Files

- **Main Screen**: `/lib/screens/bulk_transfer_screen.dart`
- **API Service**: `/lib/services/api.dart`
- **Employee Model**: `/lib/models/employee.dart`
- **Epic Model**: `/lib/models/epic.dart`
- **Bank Model**: `/lib/models/bank.dart`
- **Wallet Model**: `/lib/models/wallet.dart`

## Navigation

| Route | Purpose |
|-------|---------|
| `/main/bulk-transfer` | Bulk transfer screen (current) |
| Back navigation | Returns to previous screen after success |

## Future Enhancements

Potential improvements:
1. Save frequently used recipients
2. CSV import for bulk recipients
3. Transfer template saving
4. Scheduled transfers
5. Transfer approval workflow
