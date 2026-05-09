import React, { useState, useEffect } from 'react';
import { View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as Font from 'expo-font';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { ThemeProvider } from './src/theme/ThemeContext';
import { AuthProvider } from './src/contexts/AuthContext';
import Navigation from './src/navigation';
import Toast from 'react-native-toast-message';
import ErrorBoundary from './src/components/ErrorBoundary';

export default function App() {
  const [fontsLoaded, setFontsLoaded] = useState(false);

  useEffect(() => {
    async function loadFonts() {
      try {
        // Note: fonts need to be added to assets/fonts/ directory
        // and @expo-google-fonts/rubik installed for these to work
        await Font.loadAsync({
          Rubik: require('./assets/fonts/Rubik-Regular.ttf'),
          RubikBold: require('./assets/fonts/Rubik-Bold.ttf'),
          RubikMedium: require('./assets/fonts/Rubik-Medium.ttf'),
        });
      } catch (error) {
        console.warn('Error loading fonts:', error);
        // Fallback to system fonts
      } finally {
        setFontsLoaded(true);
      }
    }
    loadFonts();
  }, []);

  if (!fontsLoaded) {
    return null;
  }

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ErrorBoundary>
          <ThemeProvider>
            <AuthProvider>
              <View style={{ flex: 1 }}>
                <Navigation />
                <Toast />
                <StatusBar style="dark" />
              </View>
            </AuthProvider>
          </ThemeProvider>
        </ErrorBoundary>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}