# Metroflow Pay - Flutter App

## Getting Started

### Prerequisites
- Flutter SDK (3.0.0+)
- Android Studio / VS Code (with Flutter plugin)

### Installation
1. Navigate to Flutter project:
   ```bash
   cd metroflow_flutter
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate platform-specific files if missing:
   ```bash
   flutter create .
   ```

4. Start the development server:
   ```bash
   flutter run
   ```

### Features Implemented
- ✅ Authentication (Login/Register)
- ✅ KYC Verification flow (BVN/NIN + OTP)
- ✅ Wallet Management (Personal & Business wallets)
- ✅ Payroll & Employees
- ✅ Transfers & History
- ✅ Profile & Settings
- ✅ Theme Switching (Light/Dark/System)
- ✅ Biometrics (Fingerprint/FaceID)

### Project Structure
```
metroflow_flutter/
├── lib/
│   ├── screens/          # All screen components
│   ├── services/         # API & Biometrics services
│   ├── providers/        # Riverpod state management
│   ├── models/           # Data models
│   ├── utils/            # Utilities (logger)
│   ├── theme/            # App theme & colors
│   └── main.dart
└── pubspec.yaml
```
