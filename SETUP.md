# Metricorex-Mobile Development Setup

## Prerequisites

- **Flutter SDK**: 3.0.0 or higher
- **Android Studio / VS Code**: With Flutter and Dart plugins installed

## Quick Start

### 1. Install Flutter SDK
Follow official installation guide for Windows: https://docs.flutter.dev/get-started/install/windows

Verify installation:
```bash
flutter --version
flutter doctor
```

### 2. Navigate to Flutter project
```bash
cd Metricorex_flutter
```

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Generate platform-specific files if missing
```bash
flutter create .
```

### 5. Run the app
```bash
flutter run
```

## Troubleshooting

### No supported devices connected
If you get this error:
1. Ensure your Android emulator or physical device is connected and running:
   - Check with: `flutter devices`
2. Regenerate platform-specific files:
   ```bash
   cd Metricorex_flutter
   flutter create .
   ```

### Clear Flutter cache issues
```bash
flutter clean
flutter pub get
```


