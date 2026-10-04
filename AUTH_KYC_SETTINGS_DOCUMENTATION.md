# Authentication, KYC, and Settings Documentation

## Table of Contents
1. [Authentication Flow](#authentication-flow)
2. [KYC Verification Flow](#kyc-verification-flow)
3. [Wallet & Payroll Access Restriction](#wallet--payroll-access-restriction)
4. [Settings Screen Flow](#settings-screen-flow)
5. [API Endpoints](#api-endpoints)

---

## Authentication Flow

### Registration Flow
1. User navigates to registration screen
2. Enters business information:
   - Business name
   - Business email
   - Business industry (selected from dropdown)
3. Enters admin information:
   - Admin name
   - Admin email
   - Password
4. Submits form via `/auth/register` endpoint
5. If OTP verification required:
   - User receives OTP at admin email
   - Redirected to OTP verification screen
   - Enters OTP
   - Submits to `/auth/verify-otp`
6. On success: User is authenticated and redirected to KYC prompt or dashboard

### Login Flow
1. User navigates to login screen
2. Enters email and password
3. Submits via `/auth/login` endpoint
4. If OTP required:
   - Redirected to OTP verification screen
   - Enters OTP
   - Submits to `/auth/verify-otp`
5. On success:
   - User is authenticated
   - Token is stored securely
   - Checks KYC status
   - Redirected to appropriate screen (KYC prompt or dashboard)

### Biometric Login (Optional)
- **Availability**: Only available if:
  - Device supports biometrics
  - User has enabled biometric login
  - Credentials are stored securely
- **Flow**:
  1. On login screen, user selects biometric login
  2. Authenticates using fingerprint or face ID
  3. Validates stored credentials with backend
  4. On success: Logs user in automatically

### Password Reset Flow
1. User selects "Forgot Password"
2. Enters email address
3. Submits to `/auth/forgot-password`
4. Receives OTP via email
5. Enters OTP in verification screen
6. Submits OTP to `/auth/verify-reset-otp`
7. Sets new password
8. Submits new password to `/auth/reset-password`
9. On success: Redirected to login screen

### Authentication API Endpoints

#### 1. Registration
**Path**: `/auth/register`  
**Method**: POST  

**Request Body**:
```json
{
  "businessName": "string",
  "businessEmail": "string",
  "businessIndustry": "string",
  "adminName": "string",
  "adminEmail": "string",
  "password": "string"
}
```

**Response**:
```json
{
  "success": true,
  "token": "string",
  "userId": "string",
  "businessId": "string",
  "requiresOtp": false
}
```

OR (if OTP required):
```json
{
  "success": true,
  "requiresOtp": true,
  "email": "string"
}
```

#### 2. Login
**Path**: `/auth/login`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string",
  "password": "string"
}
```

**Response**:
```json
{
  "success": true,
  "token": "string",
  "userId": "string",
  "businessId": "string",
  "user": {
    "name": "string"
  },
  "requiresOtp": false
}
```

#### 3. Verify OTP
**Path**: `/auth/verify-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string",
  "otpCode": "string"
}
```

**Response**:
```json
{
  "success": true,
  "token": "string",
  "userId": "string",
  "businessId": "string",
  "user": {
    "name": "string"
  }
}
```

#### 4. Resend OTP
**Path**: `/auth/resend-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 5. Forgot Password
**Path**: `/auth/forgot-password`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 6. Verify Reset OTP
**Path**: `/auth/verify-reset-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string",
  "otpCode": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 7. Reset Password
**Path**: `/auth/reset-password`  
**Method**: POST  

**Request Body**:
```json
{
  "email": "string",
  "otpCode": "string",
  "newPassword": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

---

## KYC Verification Flow

### KYC Tiers
- **Tier 0**: No KYC verified
- **Tier 1**: Either BVN OR NIN verified
- **Tier 2**: Both BVN AND NIN verified
- **Tier 3**: Business KYC verified (proof of address submitted)

### KYC Flow Step-by-Step

#### 1. Initial Prompt (KycPromptScreen)
- **Entry Point**: After login or registration
- **Check**: Fetches current KYC status
- **Options Displayed**:
  - Both BVN and NIN not verified: Show both verification options
  - One already verified: Show remaining verification option + "Skip to Dashboard"
  - Both verified: Show "Continue to Home" button

#### 2. Initiate Verification (Step 1)
- User selects BVN or NIN verification
- User enters their 11-digit BVN/NIN number
- System calls `/kyc/initiate` endpoint
- If successful:
  - Receives OTP sent to registered phone
  - Receives user's first/last name for verification details
  - Proceeds to OTP verification screen

#### 3. Verify OTP (Step 2)
- Displays user's name and phone number that will receive OTP
- User enters 6-digit OTP code
- System calls `/kyc/verify-otp` endpoint
- If successful:
  - Refreshes KYC status
  - If now Tier 2 (both verified): Navigates to Business KYC screen
  - If only one verified: Returns to prompt screen to verify remaining document

#### 4. Business KYC (Tier 3)
- Available only after Tier 2 is completed
- Form Fields:
  - Country
  - State
  - City
  - Street
  - House Number
- File Upload: Proof of address (utility bill or bank statement)
- Submission: Calls `/kyc/business` endpoint with form data and file
- On success: Navigates to dashboard

#### 5. KYC Skip Option
- **Available only for Tier 1 users** (one document verified)
- Allows access to dashboard but restricts wallet and payroll features
- Can return to complete KYC later from dashboard

### KYC API Endpoints

#### 1. Initiate KYC
**Path**: `/kyc/initiate`  
**Method**: POST  

**Request Body**:
```json
{
  "type": "bvn|nin",
  "number": "string (11 digits)"
}
```

**Response**:
```json
{
  "success": true,
  "phone": "string",
  "firstName": "string",
  "lastName": "string"
}
```

#### 2. Verify KYC OTP
**Path**: `/kyc/verify-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "otp": "string (6 digits)"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 3. Get KYC Status
**Path**: `/kyc/status`  
**Method**: GET  

**Response**:
```json
{
  "success": true,
  "user": {
    "bvnStatus": "none|pending|verified",
    "ninStatus": "none|pending|verified",
    "rejectionReason": "string|null"
  },
  "business": {
    "status": "none|pending|verified",
    "rejectionReason": "string|null"
  },
  "bvn_verified": false,
  "nin_verified": false,
  "business_kyc_status": "none"
}
```

#### 4. Submit Business KYC
**Path**: `/kyc/business`  
**Method**: POST (Multipart Form Data)  

**Request Body**:
- `country`: string
- `state`: string
- `city`: string
- `street`: string
- `house_number`: string
- `proof_of_address`: file (Image)

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

---

## Wallet & Payroll Access Restriction

### Main Screen Gatekeeper
- **Protected Tabs**: Wallet (index 2) and Payroll (index 3)
- **Checks**:
  1. Tries to access wallet/payroll tab
  2. Fetches KYC status from `/kyc/status`
  3. Determines access:
     - **Tier 0**: Redirects to KYC prompt screen
     - **Tier 1**: Shows modal prompting to verify remaining document
     - **Tier 2+**: Allows access

### Wallet Screen Gatekeeper
- Also performs independent KYC check on init
- If not both BVN and NIN verified:
  - Shows locked screen
  - Displays "KYC Verification Required" message
  - Provides button to complete verification

---

## Settings Screen Flow

### Settings Overview
The settings screen provides access to:
- Business profile management
- Contact information updates (email/phone)
- KYC status and verification
- Transaction security (OTP preferences)
- Subscription management
- Theme preferences (dark mode)
- Biometric login toggle
- Account logout

### Profile Management
- **View**: Displays business name, email, phone number, and industry
- **Edit**: Allows updating business name, industry, and currency
- **Updates**: Calls `/settings` (PUT) endpoint

### Contact Information Update
1. User selects to update email or phone
2. Enters new contact information
3. Requests OTP via `/settings/update-contact/request-otp`
4. Enters received OTP
5. Verifies OTP via `/settings/update-contact/verify-otp`
6. Contact information is updated

### Transaction Security (OTP Preference)
- Allows user to choose OTP delivery method: Email, SMS, or Both
- Updated via `/settings/otp-preference` (PUT)

### Biometric Login
- Toggle to enable/disable biometric authentication
- Only available if device supports biometrics
- When enabled, user can log in without password using fingerprint/face ID
- Credentials are securely stored on device

### Dark Mode
- Toggle between light and dark themes
- Theme preference is saved across sessions

---

## Settings Screen API Endpoints

#### 1. Get Settings
**Path**: `/settings`  
**Method**: GET  

**Response**:
```json
{
  "success": true,
  "settings": {
    "name": "string",
    "email": "string",
    "phoneNumber": "string",
    "industry": "string",
    "currency": "string"
  }
}
```

#### 2. Update Settings
**Path**: `/settings`  
**Method**: PUT  

**Request Body**:
```json
{
  "name": "string",
  "industry": "string",
  "currency": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 3. Request Contact Update OTP
**Path**: `/settings/update-contact/request-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "type": "email|phone",
  "value": "string"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 4. Verify Contact Update OTP
**Path**: `/settings/update-contact/verify-otp`  
**Method**: POST  

**Request Body**:
```json
{
  "otp": "string (6 digits)"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

#### 5. Get OTP Preference
**Path**: `/settings/otp-preference`  
**Method**: GET  

**Response**:
```json
{
  "success": true,
  "preference": "email|sms|both"
}
```

#### 6. Update OTP Preference
**Path**: `/settings/otp-preference`  
**Method**: PUT  

**Request Body**:
```json
{
  "preference": "email|sms|both"
}
```

**Response**:
```json
{
  "success": true,
  "message": "string"
}
```

---

## API Endpoints Summary

| Category | Endpoint | Method | Description |
|----------|----------|--------|-------------|
| **Auth** | `/auth/register` | POST | Register new user |
| **Auth** | `/auth/login` | POST | Login user |
| **Auth** | `/auth/verify-otp` | POST | Verify registration/login OTP |
| **Auth** | `/auth/resend-otp` | POST | Resend OTP |
| **Auth** | `/auth/forgot-password` | POST | Initiate password reset |
| **Auth** | `/auth/verify-reset-otp` | POST | Verify password reset OTP |
| **Auth** | `/auth/reset-password` | POST | Reset password |
| **KYC** | `/kyc/initiate` | POST | Initiate BVN/NIN verification |
| **KYC** | `/kyc/verify-otp` | POST | Verify KYC OTP |
| **KYC** | `/kyc/status` | GET | Get KYC status |
| **KYC** | `/kyc/business` | POST | Submit business KYC |
| **Settings** | `/settings` | GET | Get user settings |
| **Settings** | `/settings` | PUT | Update user settings |
| **Settings** | `/settings/update-contact/request-otp` | POST | Request OTP for contact update |
| **Settings** | `/settings/update-contact/verify-otp` | POST | Verify contact update OTP |
| **Settings** | `/settings/otp-preference` | GET | Get OTP delivery preference |
| **Settings** | `/settings/otp-preference` | PUT | Update OTP delivery preference |
