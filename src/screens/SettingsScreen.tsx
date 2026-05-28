import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, ActivityIndicator, Alert, TextInput, Switch, Modal, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeContext';
import { settingsApi, subscriptionApi, kycApi, storage } from '../services/api';
import { BusinessProfile, Subscription, KYCStatus } from '../types';
import Ionicons from '@expo/vector-icons/Ionicons';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { useAuth } from '../contexts/AuthContext';
import BiometricService from '../services/biometrics';

const BUSINESS_INDUSTRIES = [
  'Technology',
  'Healthcare',
  'Finance',
  'Education',
  'Retail',
  'Manufacturing',
  'Agriculture',
  'Energy',
  'Transportation',
  'Telecommunications',
  'Media & Entertainment',
  'Real Estate',
  'Construction',
  'Hospitality',
  'Professional Services',
  'Non-Profit',
  'Government',
  'E-commerce',
  'Fintech',
  'Healthtech',
  'Edtech',
  'Biotechnology',
  'Aerospace',
  'Automotive',
  'Chemicals',
  'Pharmaceuticals',
  'Logistics',
  'Marketing',
  'Advertising',
  'Consulting',
  'Legal Services',
  'Accounting',
  'Insurance',
  'Banking',
  'Venture Capital',
  'Cryptocurrency',
  'Gaming',
  'Fashion',
  'Food & Beverage',
  'Sports',
  'Tourism',
  'Art & Design',
  'Music',
  'Film & Television',
  'Publishing',
  'Architecture',
  'Engineering',
  'Research & Development',
  'Customer Service',
  'Human Resources',
  'IT Services',
  'Software Development',
  'Hardware',
  'Networking',
  'Cybersecurity',
  'Cloud Computing',
  'Artificial Intelligence',
  'Machine Learning',
  'Data Science',
  'Big Data',
  'Internet of Things',
  'Blockchain',
  'Virtual Reality',
  'Augmented Reality',
  'Renewable Energy',
  'Sustainability',
  'Environmental Services',
  'Waste Management',
  'Water Treatment',
  'Mining',
  'Oil & Gas',
  'Forestry',
  'Fishing',
  'Textiles',
  'Footwear',
  'Furniture',
  'Electronics',
  'Appliances',
  'Toys',
  'Gifts',
  'Jewelry',
  'Beauty',
  'Personal Care',
  'Fitness',
  'Wellness',
  'Nutrition',
  'Pet Care',
  'Childcare',
  'Elder Care',
  'Home Services',
  'Cleaning',
  'Gardening',
  'Moving & Storage',
  'Packaging',
  'Printing',
  'Photography',
  'Videography',
  'Event Planning',
  'Catering',
  'Bakery',
  'Coffee Shops',
  'Restaurants',
  'Bars',
  'Nightclubs',
  'Hotels',
  'Resorts',
  'Travel Agencies',
  'Airlines',
  'Railways',
  'Shipping',
  'Warehousing',
  'Courier',
  'Delivery',
  'Rental Services',
  'Leasing',
  'Lending',
  'Investing',
  'Trading',
  'Brokering',
  'Auctions',
  'Marketplaces',
  'Classifieds',
  'Social Media',
  'Dating Apps',
  'Messaging',
  'Collaboration Tools',
  'Project Management',
  'Productivity',
  'Accounting Software',
  'HR Software',
  'CRM',
  'ERP',
  'CMS',
  'E-commerce Platforms',
  'Payment Processing',
  'Point of Sale',
  'Inventory Management',
  'Supply Chain',
  'Quality Control',
  'Safety & Compliance',
  'Legal Tech',
  'RegTech',
  'InsurTech',
  'PropTech',
  'AgriTech',
  'FoodTech',
  'CleanTech',
  'SpaceTech',
  'Defense',
  'Security',
  'Surveillance',
  'Emergency Services',
  'Public Administration',
  'International Organizations',
  'Religious Organizations',
  'Charities',
  'Foundations',
  'Associations',
  'Clubs',
  'Sports Teams',
  'Fitness Centers',
  'Yoga Studios',
  'Dance Studios',
  'Music Schools',
  'Art Galleries',
  'Museums',
  'Libraries',
  'Theaters',
  'Concert Halls',
  'Stadiums',
  'Theme Parks',
  'Zoos',
  'Aquariums',
  'Botanical Gardens',
  'Nature Reserves',
  'National Parks',
  'Tour Operators',
  'Travel Guides',
  'Language Schools',
  'Tutoring',
  'Online Courses',
  'Universities',
  'Colleges',
  'High Schools',
  'Primary Schools',
  'Preschools',
  'Vocational Training',
  'Corporate Training',
  'Executive Coaching',
  'Mentoring',
  'Career Services',
  'Recruitment',
  'Staffing',
  'Outsourcing',
  'Freelance Platforms',
  'Gig Economy',
  'Shared Economy',
  'Co-working Spaces',
  'Business Centers',
  'Virtual Offices',
  'Meeting Spaces',
  'Event Venues',
  'Conference Centers',
  'Exhibition Halls',
  'Trade Shows',
  'Conventions',
  'Summits',
  'Workshops',
  'Webinars',
  'Podcasts',
  'Blogs',
  'Vlogs',
  'Influencer Marketing',
  'Affiliate Marketing',
  'Email Marketing',
  'SEO',
  'SEM',
  'Content Marketing',
  'Social Media Marketing',
  'Digital Advertising',
  'Traditional Advertising',
  'Public Relations',
  'Media Relations',
  'Crisis Management',
  'Brand Strategy',
  'Design',
  'UX/UI',
  'Graphic Design',
  'Web Design',
  'App Design',
  'Industrial Design',
  'Interior Design',
  'Landscape Design',
  'Fashion Design',
  'Game Design',
  'Sound Design',
  'Video Editing',
  'Animation',
  'Special Effects',
  'Post-production',
  'Film Production',
  'Music Production',
  'Publishing',
  'Print Media',
  'Digital Media',
  'Streaming Services',
  'Video On Demand',
  'Music Streaming',
  'Podcast Hosting',
  'Cloud Storage',
  'File Sharing',
  'Backup Services',
  'Domain Registration',
  'Web Hosting',
  'CDN',
  'DNS',
  'SSL Certificates',
  'Email Hosting',
  'Collaboration',
  'Video Conferencing',
  'Voice Over IP',
  'Messaging Apps',
  'Project Management',
  'Task Management',
  'Time Tracking',
  'Invoicing',
  'Expense Management',
  'Tax Preparation',
  'Financial Planning',
  'Wealth Management',
  'Retirement Planning',
  'Estate Planning',
  'Insurance',
  'Health Insurance',
  'Life Insurance',
  'Property Insurance',
  'Casualty Insurance',
  'Liability Insurance',
  'Travel Insurance',
  'Pet Insurance',
  'Auto Insurance',
  'Home Insurance',
  'Business Insurance',
  'Reinsurance',
  'Underwriting',
  'Claims Processing',
  'Risk Management',
  'Compliance',
  'Audit',
  'Accounting',
  'Bookkeeping',
  'Financial Reporting',
  'Management Accounting',
  'Cost Accounting',
  'Tax Accounting',
  'Forensic Accounting',
  'Government Accounting',
  'Non-profit Accounting',
  'International Accounting',
  'Auditing',
  'Internal Audit',
  'External Audit',
  'Tax',
  'Corporate Tax',
  'Personal Tax',
  'International Tax',
  'Transfer Pricing',
  'Tax Planning',
  'Tax Compliance',
  'Legal',
  'Corporate Law',
  'Commercial Law',
  'Contract Law',
  'Employment Law',
  'Intellectual Property',
  'Patents',
  'Trademarks',
  'Copyrights',
  'Trade Secrets',
  'Privacy Law',
  'Data Protection',
  'Cybersecurity Law',
  'Competition Law',
  'Antitrust',
  'Regulatory Law',
  'Administrative Law',
  'Environmental Law',
  'Healthcare Law',
  'Education Law',
  'Real Estate Law',
  'Construction Law',
  'Banking Law',
  'Securities Law',
  'Insurance Law',
  'Tax Law',
  'Immigration Law',
  'Family Law',
  'Criminal Law',
  'Civil Litigation',
  'Arbitration',
  'Mediation',
  'Alternative Dispute Resolution',
  'Notary',
  'Legal Tech',
  'Document Management',
  'Contract Management',
  'E-discovery',
  'Legal Research',
  'Case Management',
  'Billing',
  'Timekeeping',
  'Client Relationship Management',
  'Practice Management',
];

type Props = NativeStackScreenProps<RootStackParamList, 'Profile'>;

export default function SettingsScreen({ navigation }: Props) {
  const { colors, mode, setMode } = useTheme();
  const { logout, biometricsEnabled, enableBiometrics, disableBiometrics } = useAuth();
  const [isLoading, setIsLoading] = useState(true);
  const [settings, setSettings] = useState<BusinessProfile | null>(null);
  const [subscription, setSubscription] = useState<Subscription | null>(null);
  const [kycStatus, setKycStatus] = useState<KYCStatus | null>(null);
  const [showEditProfile, setShowEditProfile] = useState(false);
  const [showUpdateContact, setShowUpdateContact] = useState<{ type: 'email' | 'phone'; value: string } | null>(null);
  const [showOtpModal, setShowOtpModal] = useState(false);
  const [otp, setOtp] = useState('');
  const [editName, setEditName] = useState('');
  const [editIndustry, setEditIndustry] = useState('');
  const [industrySearchQuery, setIndustrySearchQuery] = useState('');
  const [showIndustryDropdown, setShowIndustryDropdown] = useState(false);
  const [editCurrency, setEditCurrency] = useState<'NGN' | 'USD'>('NGN');
  const [otpPreference, setOtpPreference] = useState<'email' | 'sms' | 'both'>('email');
  const [biometricsAvailable, setBiometricsAvailable] = useState(false);
  const [hasBiometricHardware, setHasBiometricHardware] = useState(false);

  const filteredIndustries = BUSINESS_INDUSTRIES.filter(
    (industry) =>
      industry.toLowerCase().includes(industrySearchQuery.toLowerCase())
  );

  const isDarkMode = mode === 'dark';

  useEffect(() => {
    checkBiometricAvailability();
  }, []);

  const checkBiometricAvailability = async () => {
    const hasHardware = await BiometricService.hasHardware();
    const enrolled = await BiometricService.isEnrolled();
    setHasBiometricHardware(hasHardware);
    setBiometricsAvailable(enrolled);
  };

  const handleBiometricToggle = async (value: boolean) => {
    if (value) {
      const enrolled = await BiometricService.isEnrolled();
      if (!enrolled) {
        Alert.alert(
          'Biometrics Not Set Up',
          'Please set up fingerprint or face recognition in your device settings first.',
          [{ text: 'OK' }]
        );
        return;
      }
      const success = await enableBiometrics();
      if (!success) {
        Alert.alert('Error', 'Failed to enable biometric login');
      }
    } else {
      await disableBiometrics();
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [settingsRes, subscriptionRes, kycRes, otpPrefRes] = await Promise.all([
        settingsApi.getSettings(),
        subscriptionApi.getCurrent(),
        kycApi.getStatus(),
        settingsApi.getOtpPreference(),
      ]);

      if (settingsRes.data.success) {
        setSettings(settingsRes.data.settings);
        setEditName(settingsRes.data.settings?.name || '');
        setEditIndustry(settingsRes.data.settings?.industry || '');
        setEditCurrency(settingsRes.data.settings?.currency || 'NGN');
      }
      if (subscriptionRes.data.success) {
        setSubscription(subscriptionRes.data.subscription);
      }
      if (otpPrefRes.data.success) {
        setOtpPreference(otpPrefRes.data.preference);
      }
      setKycStatus(kycRes.data);
    } catch (error) {
      console.error('Failed to fetch settings:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleUpdateProfile = async () => {
    try {
      await settingsApi.updateSettings({ 
        name: editName, 
        industry: editIndustry,
        currency: editCurrency 
      });
      Alert.alert('Success', 'Profile updated successfully');
      setShowEditProfile(false);
      fetchData();
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Failed to update profile');
    }
  };

  const handleRequestContactUpdate = async (type: 'email' | 'phone', value: string) => {
    if (!value) {
      Alert.alert('Error', `Please enter a valid ${type}`);
      return;
    }
    setIsLoading(true);
    try {
      await settingsApi.requestContactUpdateOtp(type, value);
      setShowOtpModal(true);
    } catch (error) {
      // Toast handles it
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyContactUpdate = async () => {
    if (otp.length !== 6) {
      Alert.alert('Error', 'Please enter a valid 6-digit OTP');
      return;
    }
    setIsLoading(true);
    try {
      await settingsApi.verifyContactUpdateOtp(otp);
      setShowOtpModal(false);
      setShowUpdateContact(null);
      setOtp('');
      fetchData();
    } catch (error) {
      // Toast handles it
    } finally {
      setIsLoading(false);
    }
  };

  const handleUpdateOtpPreference = async (pref: 'email' | 'sms' | 'both') => {
    try {
      await settingsApi.updateOtpPreference(pref);
      setOtpPreference(pref);
    } catch (error) {
      // Toast handles it
    }
  };

  const handleThemeToggle = () => {
    const newMode = isDarkMode ? 'light' : 'dark';
    setMode(newMode as any);
  };

  const handleLogout = () => {
    Alert.alert(
      'Logout',
      'Are you sure you want to logout?',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Logout', style: 'destructive', onPress: logout },
      ]
    );
  };

  const renderSettingItem = (
    icon: string,
    title: string,
    subtitle?: string,
    onPress?: () => void,
    rightElement?: React.ReactNode
  ) => (
    <TouchableOpacity
      style={styles.settingItem}
      onPress={onPress}
      disabled={!onPress}
    >
      <View style={styles.settingIcon}>
        <Ionicons name={icon as any} size={22} color={colors.primary} />
      </View>
      <View style={styles.settingContent}>
        <Text style={styles.settingTitle}>{title}</Text>
        {subtitle && <Text style={styles.settingSubtitle}>{subtitle}</Text>}
      </View>
      {rightElement || (onPress && <Ionicons name="chevron-forward" size={20} color={colors.textSecondary} />)}
    </TouchableOpacity>
  );

  const styles = createStyles(colors);

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, styles.center]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  const getKycTier = () => {
    if (!kycStatus) return 'Tier 0';
    const { user } = kycStatus as any;
    const bvn = user.bvnStatus === 'verified';
    const nin = user.ninStatus === 'verified';
    // Assuming Tier 3 is business/address which we'll check from kycStatus.business
    const tier3 = (kycStatus as any).business?.status === 'verified';

    if (tier3) return 'Tier 3';
    if (bvn && nin) return 'Tier 2';
    if (bvn || nin) return 'Tier 1';
    return 'Tier 0';
  };

  const getKycUpgradeLabel = () => {
    const tier = getKycTier();
    if (tier === 'Tier 0') return 'Upgrade to Tier 1 (Verify BVN/NIN)';
    if (tier === 'Tier 1') return 'Upgrade to Tier 2 (Verify both)';
    if (tier === 'Tier 2') return 'Upgrade to Tier 3 (Business KYC)';
    return 'Fully Verified';
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={[styles.header, { backgroundColor: colors.surface }]}>
        <TouchableOpacity 
          style={styles.backButton}
          onPress={() => navigation.goBack()}
        >
          <Ionicons name="arrow-back" size={24} color={colors.text} />
        </TouchableOpacity>
        <Text style={styles.title}>Settings</Text>
        <View style={{ width: 40 }} />
      </View>
      <ScrollView style={styles.scrollView}>

        <View style={styles.profileSection}>
          <View style={styles.profileHeader}>
            <View style={styles.avatar}>
              <Text style={styles.avatarText}>{settings?.name?.charAt(0).toUpperCase() || 'B'}</Text>
            </View>
            <View style={styles.profileInfo}>
              <Text style={styles.profileName}>{settings?.name || 'Business'}</Text>
              <Text style={styles.profileEmail}>{settings?.email || ''}</Text>
            </View>
            <TouchableOpacity style={styles.editButton} onPress={() => setShowEditProfile(true)}>
              <Ionicons name="pencil" size={20} color={colors.primary} />
            </TouchableOpacity>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Verification & KYC</Text>
          <View style={styles.kycCard}>
            <View style={styles.kycHeader}>
              <View style={styles.kycBadge}>
                <Text style={styles.kycBadgeText}>{getKycTier()}</Text>
              </View>
              <Text style={styles.kycStatusText}>
                {(kycStatus as any)?.user?.bvnStatus === 'verified' && (kycStatus as any)?.user?.ninStatus === 'verified' 
                  ? 'Fully Verified' 
                  : 'Verification Pending'}
              </Text>
            </View>
            
            <View style={styles.kycDetails}>
              <View style={styles.kycRow}>
                <Text style={styles.kycLabel}>BVN Status</Text>
                <View style={[styles.statusIndicator, (kycStatus as any)?.user?.bvnStatus === 'verified' ? styles.statusSuccess : styles.statusPending]}>
                  <Text style={styles.statusIndicatorText}>{(kycStatus as any)?.user?.bvnStatus || 'none'}</Text>
                </View>
              </View>
              <View style={styles.kycRow}>
                <Text style={styles.kycLabel}>NIN Status</Text>
                <View style={[styles.statusIndicator, (kycStatus as any)?.user?.ninStatus === 'verified' ? styles.statusSuccess : styles.statusPending]}>
                  <Text style={styles.statusIndicatorText}>{(kycStatus as any)?.user?.ninStatus || 'none'}</Text>
                </View>
              </View>
              <View style={styles.kycRow}>
                <Text style={styles.kycLabel}>Business KYC</Text>
                <View style={[styles.statusIndicator, (kycStatus as any)?.business?.status === 'verified' ? styles.statusSuccess : styles.statusPending]}>
                  <Text style={styles.statusIndicatorText}>{(kycStatus as any)?.business?.status || 'none'}</Text>
                </View>
              </View>
            </View>

            {getKycTier() !== 'Tier 3' && (
              <TouchableOpacity 
                style={styles.upgradeButton}
                onPress={() => navigation.navigate(getKycTier() === 'Tier 2' ? 'BusinessKyc' : 'KycPrompt')}
              >
                <Text style={styles.upgradeButtonText}>{getKycUpgradeLabel()}</Text>
                <Ionicons name="arrow-forward" size={18} color="#fff" />
              </TouchableOpacity>
            )}
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Business</Text>
          {renderSettingItem(
            'business-outline',
            'Business Profile',
            settings?.industry,
            () => setShowEditProfile(true)
          )}
          {renderSettingItem(
            'mail-outline',
            'Update Email',
            settings?.email,
            () => setShowUpdateContact({ type: 'email', value: settings?.email || '' })
          )}
          {renderSettingItem(
            'call-outline',
            'Update Phone',
            settings?.phone_number,
            () => setShowUpdateContact({ type: 'phone', value: settings?.phone_number || '' })
          )}
          {(() => {
            const hasPendingKyc = 
              (kycStatus as any)?.user?.bvnStatus !== 'verified' ||
              (kycStatus as any)?.user?.ninStatus !== 'verified' ||
              (kycStatus as any)?.business?.status !== 'verified';

            return renderSettingItem(
              'shield-checkmark-outline',
              'KYC Status',
              kycStatus?.business?.status ? `${kycStatus.business.status.charAt(0).toUpperCase()}${kycStatus.business.status.slice(1)}` : 'None',
              hasPendingKyc ? () => {
                const tier = getKycTier();
                if (tier === 'Tier 0' || tier === 'Tier 1') {
                  navigation.navigate('KycPrompt');
                } else if (tier === 'Tier 2') {
                  navigation.navigate('BusinessKyc');
                }
              } : undefined
            );
          })()}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Transaction Security</Text>
          <View style={styles.otpPreferenceContainer}>
            <Text style={styles.otpPreferenceLabel}>Receive Transaction OTP via:</Text>
            <View style={styles.otpPreferenceOptions}>
              {(['email', 'sms', 'both'] as const).map((pref) => (
                <TouchableOpacity
                  key={pref}
                  style={[styles.otpOption, otpPreference === pref && styles.otpOptionActive]}
                  onPress={() => handleUpdateOtpPreference(pref)}
                >
                  <Text style={[styles.otpOptionText, otpPreference === pref && styles.otpOptionTextActive]}>
                    {pref.toUpperCase()}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Subscription</Text>
          {renderSettingItem(
            'card-outline',
            subscription?.plan_name || 'Free Plan',
            subscription?.subscription_status === 'active' ? 'Active' : 'Inactive',
            () => navigation.navigate('Subscription')
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Appearance</Text>
          {renderSettingItem(
            isDarkMode ? 'moon-outline' : 'sunny-outline',
            'Dark Mode',
            `Currently ${isDarkMode ? 'enabled' : 'disabled'}`,
            undefined,
            <Switch
              value={isDarkMode}
              onValueChange={handleThemeToggle}
              trackColor={{ false: colors.border, true: colors.primary + '80' }}
              thumbColor={isDarkMode ? colors.primary : colors.textSecondary}
            />
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Security</Text>
          {renderSettingItem(
            'finger-print-outline',
            'Biometric Login',
            !biometricsAvailable && !hasBiometricHardware ? 'Not available on this device' : (!biometricsAvailable ? 'Not enrolled on device' : (biometricsEnabled ? 'Enabled' : 'Disabled')),
            undefined,
            <Switch
              value={biometricsEnabled}
              onValueChange={handleBiometricToggle}
              trackColor={{ false: colors.border, true: colors.primary + '80' }}
              thumbColor={biometricsEnabled ? colors.primary : colors.textSecondary}
              disabled={!biometricsAvailable && !biometricsEnabled}
            />
          )}
          {renderSettingItem(
            'lock-closed-outline',
            'Change Password',
            undefined,
            () => navigation.navigate('ForgotPassword')
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Support</Text>
          {renderSettingItem(
            'help-circle-outline',
            'Help Center',
            undefined,
            () => Alert.alert('Coming Soon', 'Help Center will be available soon!')
          )}
          {renderSettingItem(
            'chatbubble-outline',
            'Contact Support',
            undefined,
            () => Alert.alert('Coming Soon', 'Contact Support will be available soon!')
          )}
        </View>

        <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
          <Ionicons name="log-out-outline" size={20} color={colors.error} />
          <Text style={styles.logoutText}>Logout</Text>
        </TouchableOpacity>
      </ScrollView>

      {showEditProfile && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Edit Profile</Text>
              <TouchableOpacity onPress={() => setShowEditProfile(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Business Name</Text>
              <TextInput
                style={styles.input}
                value={editName}
                onChangeText={setEditName}
              />
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Industry</Text>
              <TouchableOpacity
                style={styles.input}
                onPress={() => setShowIndustryDropdown(true)}
              >
                <Text style={[editIndustry ? {} : styles.placeholderText]}>
                  {editIndustry || 'Select Industry'}
                </Text>
              </TouchableOpacity>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>Default Currency</Text>
              <View style={styles.currencyRow}>
                {(['NGN', 'USD'] as const).map((curr) => (
                  <TouchableOpacity
                    key={curr}
                    style={[styles.currencyOption, editCurrency === curr && styles.currencyOptionActive]}
                    onPress={() => setEditCurrency(curr)}
                  >
                    <Text style={[styles.currencyOptionText, editCurrency === curr && styles.currencyOptionTextActive]}>
                      {curr}
                    </Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            <TouchableOpacity style={styles.saveButton} onPress={handleUpdateProfile}>
              <Text style={styles.saveButtonText}>Save Changes</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {showUpdateContact && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Update {showUpdateContact.type === 'email' ? 'Email' : 'Phone'}</Text>
              <TouchableOpacity onPress={() => setShowUpdateContact(null)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.field}>
              <Text style={styles.label}>New {showUpdateContact.type === 'email' ? 'Email Address' : 'Phone Number'}</Text>
              <TextInput
                style={styles.input}
                value={showUpdateContact.value}
                onChangeText={(val) => setShowUpdateContact({ ...showUpdateContact, value: val })}
                keyboardType={showUpdateContact.type === 'email' ? 'email-address' : 'phone-pad'}
                autoCapitalize="none"
              />
            </View>

            <TouchableOpacity 
              style={styles.saveButton} 
              onPress={() => handleRequestContactUpdate(showUpdateContact.type, showUpdateContact.value)}
            >
              <Text style={styles.saveButtonText}>Send OTP</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {showOtpModal && (
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Verify OTP</Text>
              <TouchableOpacity onPress={() => setShowOtpModal(false)}>
                <Ionicons name="close" size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <Text style={styles.modalSubtitle}>Enter the 6-digit code sent to your new {showUpdateContact?.type}</Text>

            <TextInput
              style={[styles.input, styles.otpInput]}
              value={otp}
              onChangeText={setOtp}
              keyboardType="numeric"
              maxLength={6}
              placeholder="000000"
            />

            <TouchableOpacity style={styles.saveButton} onPress={handleVerifyContactUpdate}>
              <Text style={styles.saveButtonText}>Verify & Update</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {showIndustryDropdown && (
        <Modal
          visible={showIndustryDropdown}
          animationType="slide"
          transparent={true}
          onRequestClose={() => setShowIndustryDropdown(false)}
        >
          <View style={styles.modalOverlay}>
            <View style={[styles.modalContent, { backgroundColor: colors.surface }]}>
              <View style={styles.modalHeader}>
                <Text style={[styles.modalTitle, { color: colors.text }]}>Select Industry</Text>
                <TouchableOpacity onPress={() => setShowIndustryDropdown(false)}>
                  <Ionicons name="close" size={24} color={colors.text} />
                </TouchableOpacity>
              </View>
              <View style={[styles.searchContainer, { backgroundColor: colors.background }]}>
                <Ionicons name="search-outline" size={20} color={colors.textSecondary} style={styles.searchIcon} />
                <TextInput
                  style={[styles.searchInput, { 
                    backgroundColor: colors.background, 
                    borderColor: colors.border, 
                    color: colors.text 
                  }]}
                  placeholder="Search industries..."
                  placeholderTextColor={colors.textSecondary}
                  value={industrySearchQuery}
                  onChangeText={setIndustrySearchQuery}
                  autoFocus
                />
              </View>
              <FlatList
                data={filteredIndustries}
                keyExtractor={(item) => item}
                renderItem={({ item }) => (
                  <TouchableOpacity
                    style={[styles.industryItem, { backgroundColor: colors.background }]}
                    onPress={() => {
                      setEditIndustry(item);
                      setIndustrySearchQuery('');
                      setShowIndustryDropdown(false);
                    }}
                  >
                    <Text style={[styles.industryItemText, { color: colors.text }]}>{item}</Text>
                  </TouchableOpacity>
                )}
                showsVerticalScrollIndicator={false}
                contentContainerStyle={styles.industryList}
              />
            </View>
          </View>
        </Modal>
      )}
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    padding: 24,
    paddingTop: 16,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: 1,
    borderBottomColor: 'transparent',
  },
  backButton: {
    padding: 8,
    width: 40,
    alignItems: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: colors.text,
  },
  profileSection: {
    padding: 24,
  },
  profileHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  avatarText: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  profileInfo: {
    flex: 1,
  },
  profileName: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
  },
  profileEmail: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 4,
  },
  editButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.surface,
    justifyContent: 'center',
    alignItems: 'center',
  },
  section: {
    paddingHorizontal: 24,
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.textSecondary,
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  settingItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
    marginBottom: 8,
  },
  settingIcon: {
    width: 40,
    height: 40,
    borderRadius: 10,
    backgroundColor: colors.primary + '10',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  settingContent: {
    flex: 1,
  },
  settingTitle: {
    fontSize: 16,
    fontWeight: '500',
    color: colors.text,
  },
  settingSubtitle: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: 2,
  },
  logoutButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.error + '10',
    borderRadius: 12,
    padding: 16,
    margin: 24,
    gap: 8,
  },
  logoutText: {
    color: colors.error,
    fontSize: 16,
    fontWeight: '600',
  },
  modalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    width: '100%',
    maxWidth: 400,
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 24,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: colors.text,
  },
  field: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '500',
    color: colors.text,
    marginBottom: 8,
  },
  input: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 12,
    fontSize: 16,
    color: colors.text,
  },
  saveButton: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  currencyRow: {
    flexDirection: 'row',
    gap: 12,
  },
  currencyOption: {
    flex: 1,
    padding: 12,
    borderRadius: 12,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
  },
  currencyOptionActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  currencyOptionText: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  currencyOptionTextActive: {
    color: colors.primary,
  },
  otpPreferenceContainer: {
    backgroundColor: colors.surface,
    borderRadius: 12,
    padding: 16,
  },
  otpPreferenceLabel: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 12,
  },
  otpPreferenceOptions: {
    flexDirection: 'row',
    gap: 8,
  },
  otpOption: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 8,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.border,
    alignItems: 'center',
  },
  otpOptionActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primary + '10',
  },
  otpOptionText: {
    fontSize: 12,
    fontWeight: 'bold',
    color: colors.textSecondary,
  },
  otpOptionTextActive: {
    color: colors.primary,
  },
  modalSubtitle: {
    fontSize: 14,
    color: colors.textSecondary,
    marginBottom: 20,
    textAlign: 'center',
  },
  otpInput: {
    fontSize: 24,
    textAlign: 'center',
    letterSpacing: 8,
    marginBottom: 24,
  },
  kycCard: {
    backgroundColor: colors.surface,
    borderRadius: 20,
    padding: 20,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
  kycHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 20,
    gap: 12,
  },
  kycBadge: {
    backgroundColor: colors.primary,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  kycBadgeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  kycStatusText: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text,
  },
  kycDetails: {
    gap: 12,
    marginBottom: 24,
  },
  kycRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  kycLabel: {
    fontSize: 14,
    color: colors.textSecondary,
  },
  statusIndicator: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  statusIndicatorText: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  statusSuccess: {
    backgroundColor: '#4CAF5020',
  },
  statusPending: {
    backgroundColor: '#FF980020',
  },
  upgradeButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
    padding: 16,
    borderRadius: 12,
    gap: 8,
  },
  upgradeButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: 'bold',
  },
  placeholderText: {
    color: colors.textSecondary,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.background,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    paddingHorizontal: 16,
    marginBottom: 16,
  },
  searchIcon: {
    marginRight: 12,
  },
  searchInput: {
    flex: 1,
    paddingVertical: 14,
    fontSize: 16,
    borderWidth: 0,
    borderRadius: 0,
    paddingHorizontal: 0,
  },
  industryList: {
    gap: 8,
  },
  industryItem: {
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: colors.border,
  },
  industryItemText: {
    fontSize: 16,
  },
});
