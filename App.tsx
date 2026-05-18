import React from 'react';
import { View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { ThemeProvider, useTheme } from './src/theme/ThemeContext';
import { AuthProvider } from './src/contexts/AuthContext';
import Navigation from './src/navigation';
import Toast from 'react-native-toast-message';
import ErrorBoundary from './src/components/ErrorBoundary';
import IdleTimeoutHandler from './src/components/IdleTimeoutHandler';

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ErrorBoundary>
          <ThemeProvider>
            <AuthProvider>
              <ThemeConsumer />
            </AuthProvider>
          </ThemeProvider>
        </ErrorBoundary>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

function ThemeConsumer() {
  const { mode } = useTheme();
  return (
    <IdleTimeoutHandler>
      <View style={{ flex: 1 }}>
        <Navigation />
        <Toast />
        <StatusBar style={mode === 'dark' ? 'light' : 'dark'} />
      </View>
    </IdleTimeoutHandler>
  );
}