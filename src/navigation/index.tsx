import React, { useState, useEffect } from 'react';
import { NavigationContainer, DarkTheme, DefaultTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createDrawerNavigator, DrawerContentScrollView } from '@react-navigation/drawer';
import { useNavigation } from '@react-navigation/native';
import Ionicons from '@expo/vector-icons/Ionicons';
import { View, Text, Image, StyleSheet, TouchableOpacity, Alert, Switch, useWindowDimensions } from 'react-native';

import LoginScreen from '../screens/LoginScreen';
import RegisterScreen from '../screens/RegisterScreen';
import KycPromptScreen from '../screens/KycPromptScreen';
import KycInitiateScreen from '../screens/KycInitiateScreen';
import KycOtpScreen from '../screens/KycOtpScreen';
import WalletScreen from '../screens/WalletScreen';
import PayrollScreen from '../screens/PayrollScreen';
import TransfersScreen from '../screens/TransfersScreen';
import ProfileScreen from '../screens/SettingsScreen';
import BusinessKycScreen from '../screens/BusinessKycScreen';
import FundWalletScreen from '../screens/FundWalletScreen';
import CreateBusinessWalletScreen from '../screens/CreateBusinessWalletScreen';
import BulkTransferScreen from '../screens/BulkTransferScreen';
import OnboardingScreen1 from '../screens/OnboardingScreen1';
import OnboardingScreen2 from '../screens/OnboardingScreen2';
import OnboardingScreen3 from '../screens/OnboardingScreen3';
import VerifyOtpScreen from '../screens/VerifyOtpScreen';
import ForgotPasswordScreen from '../screens/ForgotPasswordScreen';
import VerifyResetOtpScreen from '../screens/VerifyResetOtpScreen';
import ResetPasswordScreen from '../screens/ResetPasswordScreen';
import DashboardScreen from '../screens/DashboardScreen';
import TasksScreen from '../screens/TasksScreen';
import TeamScreen from '../screens/TeamScreen';
import CreateTaskScreen from '../screens/CreateTaskScreen';
import TaskDetailScreen from '../screens/TaskDetailScreen';
import IdeasScreen from '../screens/IdeasScreen';
import BacklogScreen from '../screens/BacklogScreen';
import ActivityLogsScreen from '../screens/ActivityLogsScreen';
import SubscriptionScreen from '../screens/SubscriptionScreen';
import FeesScreen from '../screens/FeesScreen';
import { useTheme } from '../theme/ThemeContext';
import { useAuth } from '../contexts/AuthContext';

export type RootStackParamList = {
  Onboarding1: undefined;
  Onboarding2: undefined;
  Onboarding3: undefined;
  Login: undefined;
  Register: undefined;
  VerifyOtp: { email: string };
  ForgotPassword: undefined;
  VerifyResetOtp: { email: string };
  ResetPassword: { email: string; otp: string };
  KycPrompt: undefined;
  KycInitiate: { type: 'bvn' | 'nin' };
  KycOtp: undefined;
  Main: undefined;
  BusinessKyc: undefined;
  FundWallet: { walletType: 'business' | 'user' };
  CreateBusinessWallet: undefined;
  BulkTransfer: undefined;
  CreateTask: undefined;
  TaskDetail: { taskId: string };
  Ideas: undefined;
  Backlog: undefined;
  ActivityLogs: undefined;
  Subscription: undefined;
  Profile: undefined;
  Fees: undefined;
};

function SplashScreen({ onFinish }: { onFinish: () => void }) {
  const { colors } = useTheme();
  const styles = createSplashStyles(colors);

  useEffect(() => {
    const timer = setTimeout(() => {
      onFinish();
    }, 2000);
    return () => clearTimeout(timer);
  }, [onFinish]);

   return (
    <View style={styles.container}>
      <Image 
        source={require('../../Asset/Logo-white.png')} 
        style={styles.logo}
        resizeMode="contain"
      />
      <Text style={styles.appName}>Metroflow</Text>
    </View>
  );
}

const createSplashStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  logo: {
    width: 120,
    height: 120,
  },
  appName: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#fff',
    marginTop: 20,
  },
});

export type MainTabParamList = {
  Dashboard: undefined;
  Tasks: undefined;
  Wallet: undefined;
  Payroll: undefined;
};

export type DrawerParamList = {
  MainTabs: undefined;
  Profile: undefined;
  Ideas: undefined;
  Backlog: undefined;
  ActivityLogs: undefined;
  Transfers: undefined;
  Team: undefined;
  Subscription: undefined;
  Fees: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator<MainTabParamList>();
const Drawer = createDrawerNavigator<DrawerParamList>();

// Custom Drawer Content with Theme Toggle
function CustomDrawerContent(props: any) {
  const { colors, mode, toggleTheme } = useTheme();
  const { logout } = useAuth();
  const navigation = props.navigation;
  const dimensions = useWindowDimensions();

  const drawerItems = [
    { name: 'Profile', icon: 'person-outline', route: 'Profile' },
    { name: 'Subscription', icon: 'card-outline', route: 'Subscription' },
    { name: 'Pricing', icon: 'pricetag-outline', route: 'Fees' },
    { name: 'Ideas', icon: 'bulb-outline', route: 'Ideas' },
    { name: 'Backlog', icon: 'archive-outline', route: 'Backlog' },
    { name: 'Activity Logs', icon: 'receipt-outline', route: 'ActivityLogs' },
    { name: 'Transfers', icon: 'swap-horizontal-outline', route: 'Transfers' },
    { name: 'Team', icon: 'people-outline', route: 'Team' },
  ];

  const handleLogout = () => {
    Alert.alert('Logout', 'Are you sure you want to logout?', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Logout', style: 'destructive', onPress: logout },
    ]);
  };

  return (
    <DrawerContentScrollView 
      {...props} 
      style={{ backgroundColor: colors.surface }}
      contentContainerStyle={{ paddingTop: 0 }}
    >
      <View style={[styles.drawerHeader, { backgroundColor: colors.primary }]}>
        <Image 
          source={require('../../Asset/Logo-white.png')} 
          style={styles.drawerLogo}
          resizeMode="contain"
        />
        <Text style={styles.drawerTitle}>Metroflow</Text>
      </View>
      
      {drawerItems.map((item) => (
        <TouchableOpacity
          key={item.route}
          style={[styles.drawerItem, { borderBottomColor: colors.border }]}
          onPress={() => navigation.navigate(item.route as never)}
          activeOpacity={0.7}
        >
          <View style={styles.drawerItemContent}>
            <Ionicons name={item.icon as any} size={22} color={colors.primary} />
            <Text style={[styles.drawerItemText, { color: colors.text }]}>{item.name}</Text>
          </View>
          <Ionicons name="chevron-forward" size={18} color={colors.textSecondary} />
        </TouchableOpacity>
      ))}
      
      <View style={[styles.drawerSection, { borderTopColor: colors.border }]}>
        <View style={[styles.drawerItem, { borderBottomColor: colors.border }]}>
          <View style={styles.drawerItemContent}>
            <Ionicons name={mode === 'dark' ? 'moon-outline' : 'sunny-outline'} size={22} color={colors.primary} />
            <Text style={[styles.drawerItemText, { color: colors.text }]}>Dark Mode</Text>
          </View>
          <Switch
            value={mode === 'dark'}
            onValueChange={toggleTheme}
            trackColor={{ false: colors.border, true: colors.primary + '80' }}
            thumbColor={mode === 'dark' ? colors.primary : colors.textSecondary}
          />
        </View>
      </View>

      <TouchableOpacity 
        style={styles.drawerLogout} 
        onPress={handleLogout}
        activeOpacity={0.7}
      >
        <Ionicons name="log-out-outline" size={22} color="#F44336" />
        <Text style={styles.drawerLogoutText}>Logout</Text>
      </TouchableOpacity>
    </DrawerContentScrollView>
  );
}

// Tab Navigator with header menu button
function MainTabs() {
  const { colors } = useTheme();

  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
          paddingTop: 8,
          paddingBottom: 8,
          height: 65,
          elevation: 8,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: -2 },
          shadowOpacity: 0.1,
          shadowRadius: 4,
        },
        tabBarLabelStyle: {
          fontSize: 12,
          fontWeight: '500',
          marginTop: 4,
        },
      }}
    >
      <Tab.Screen 
        name="Dashboard" 
        component={DashboardScreen} 
        options={{ 
          title: 'Home',
          tabBarLabel: 'Home',
          tabBarIcon: ({ focused, color, size }) => (
            <Ionicons name={focused ? 'home' : 'home-outline'} size={size} color={color} />
          ),
        }}
      />
      <Tab.Screen 
        name="Tasks" 
        component={TasksScreen} 
        options={{ 
          title: 'Tasks',
          tabBarIcon: ({ focused, color, size }) => (
            <Ionicons name={focused ? 'list' : 'list-outline'} size={size} color={color} />
          ),
        }}
      />
      <Tab.Screen 
        name="Wallet" 
        component={WalletScreen} 
        options={{ 
          title: 'Wallet',
          tabBarIcon: ({ focused, color, size }) => (
            <Ionicons name={focused ? 'wallet' : 'wallet-outline'} size={size} color={color} />
          ),
        }}
      />
      <Tab.Screen 
        name="Payroll" 
        component={PayrollScreen} 
        options={{ 
          title: 'Payroll',
          tabBarIcon: ({ focused, color, size }) => (
            <Ionicons name={focused ? 'cash' : 'cash-outline'} size={size} color={color} />
          ),
        }}
      />
    </Tab.Navigator>
  );
}

// Main Drawer Navigator
function MainDrawer() {
  const { colors } = useTheme();

  return (
    <Drawer.Navigator
      drawerContent={(props) => <CustomDrawerContent {...props} />}
      screenOptions={{
        headerShown: false,
        drawerStyle: {
          backgroundColor: colors.surface,
          width: Math.min(useWindowDimensions().width * 0.85, 320),
        },
        drawerActiveTintColor: colors.primary,
        drawerInactiveTintColor: colors.textSecondary,
        drawerLabelStyle: {
          fontSize: 16,
          fontWeight: '500',
        },
        overlayColor: 'rgba(0, 0, 0, 0.5)',
      }}
    >
      <Drawer.Screen 
        name="MainTabs" 
        component={MainTabs} 
        options={{ drawerLabel: 'Home' }}
      />
      <Drawer.Screen 
        name="Profile" 
        component={ProfileScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="person-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Ideas" 
        component={IdeasScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="bulb-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Backlog" 
        component={BacklogScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="archive-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="ActivityLogs" 
        component={ActivityLogsScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="receipt-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Transfers" 
        component={TransfersScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="swap-horizontal-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Team" 
        component={TeamScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="people-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Subscription" 
        component={SubscriptionScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="card-outline" size={size} color={color} />
          ),
        }}
      />
      <Drawer.Screen 
        name="Fees" 
        component={FeesScreen} 
        options={{
          drawerIcon: ({ color, size }) => (
            <Ionicons name="pricetag-outline" size={size} color={color} />
          ),
        }}
      />
    </Drawer.Navigator>
  );
}

export default function Navigation() {
  const { colors, mode } = useTheme();
  const { isAuthenticated, isLoading } = useAuth();
  const [isSplashVisible, setIsSplashVisible] = useState(true);
  
  const navTheme = mode === 'dark'
    ? {
        ...DarkTheme,
        colors: {
          ...DarkTheme.colors,
          primary: colors.primary,
          background: colors.background,
          card: colors.surface,
          text: colors.text,
          border: colors.border,
          notification: colors.primary,
        }
      }
    : {
        ...DefaultTheme,
        colors: {
          ...DefaultTheme.colors,
          primary: colors.primary,
          background: colors.background,
          card: colors.surface,
          text: colors.text,
          border: colors.border,
          notification: colors.primary,
        }
      };

  if (isSplashVisible || isLoading) {
    return <SplashScreen onFinish={() => setIsSplashVisible(false)} />;
  }

  return (
    <NavigationContainer theme={navTheme}>
      <Stack.Navigator screenOptions={{ headerShown: false }}>
        {isAuthenticated ? (
          <>
            <Stack.Screen name="Main" component={MainDrawer} />
            <Stack.Screen name="BusinessKyc" component={BusinessKycScreen} />
            <Stack.Screen name="FundWallet" component={FundWalletScreen} />
            <Stack.Screen name="CreateBusinessWallet" component={CreateBusinessWalletScreen} />
            <Stack.Screen name="BulkTransfer" component={BulkTransferScreen} />
            <Stack.Screen name="CreateTask" component={CreateTaskScreen} />
            <Stack.Screen name="TaskDetail" component={TaskDetailScreen} />
            <Stack.Screen name="Ideas" component={IdeasScreen} />
            <Stack.Screen name="Backlog" component={BacklogScreen} />
            <Stack.Screen name="ActivityLogs" component={ActivityLogsScreen} />
            <Stack.Screen name="Subscription" component={SubscriptionScreen} />
            <Stack.Screen name="Fees" component={FeesScreen} />
          </>
        ) : (
          <>
            <Stack.Screen name="Onboarding1" component={OnboardingScreen1} />
            <Stack.Screen name="Onboarding2" component={OnboardingScreen2} />
            <Stack.Screen name="Onboarding3" component={OnboardingScreen3} />
            <Stack.Screen name="Login" component={LoginScreen} />
            <Stack.Screen name="Register" component={RegisterScreen} />
            <Stack.Screen name="VerifyOtp" component={VerifyOtpScreen} />
            <Stack.Screen name="ForgotPassword" component={ForgotPasswordScreen} />
            <Stack.Screen name="VerifyResetOtp" component={VerifyResetOtpScreen} />
            <Stack.Screen name="ResetPassword" component={ResetPasswordScreen} />
            <Stack.Screen name="KycPrompt" component={KycPromptScreen} />
            <Stack.Screen name="KycInitiate" component={KycInitiateScreen} />
            <Stack.Screen name="KycOtp" component={KycOtpScreen} />
          </>
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  drawerHeader: {
    padding: 24,
    paddingTop: 48,
    alignItems: 'center',
  },
  drawerLogo: {
    width: 60,
    height: 60,
    marginBottom: 12,
  },
  drawerTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
  },
  drawerSection: {
    marginTop: 24,
    borderTopWidth: 1,
    paddingTop: 16,
    paddingHorizontal: 8,
  },
  drawerItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginHorizontal: 8,
    marginVertical: 4,
    borderRadius: 12,
    borderBottomWidth: 0,
  },
  drawerItemContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    flex: 1,
  },
  drawerItemText: {
    fontSize: 15,
    fontWeight: '500',
  },
  drawerLogout: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 16,
    paddingHorizontal: 24,
    gap: 12,
    marginTop: 24,
    marginHorizontal: 8,
    marginBottom: 16,
    borderRadius: 12,
    backgroundColor: '#F4433610',
  },
  drawerLogoutText: {
    fontSize: 15,
    fontWeight: '600',
    color: '#F44336',
  },
});
