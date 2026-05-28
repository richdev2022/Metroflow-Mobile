import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator, ScrollView, KeyboardAvoidingView, Platform, Modal, FlatList } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation';
import { useAuth } from '../contexts/AuthContext';
import { useTheme } from '../theme/ThemeContext';
import Ionicons from '@expo/vector-icons/Ionicons';
import { LinearGradient } from 'expo-linear-gradient';

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

type RegisterScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Register'>;

export default function RegisterScreen() {
  const navigation = useNavigation<RegisterScreenNavigationProp>();
  const { register } = useAuth();
  const { colors } = useTheme();
  const [loading, setLoading] = useState(false);

  const [businessName, setBusinessName] = useState('');
  const [businessEmail, setBusinessEmail] = useState('');
  const [businessIndustry, setBusinessIndustry] = useState('');
  const [industrySearchQuery, setIndustrySearchQuery] = useState('');
  const [showIndustryDropdown, setShowIndustryDropdown] = useState(false);
  const [adminName, setAdminName] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const filteredIndustries = BUSINESS_INDUSTRIES.filter(
    (industry) =>
      industry.toLowerCase().includes(industrySearchQuery.toLowerCase())
  );

  const handleRegister = async () => {
    if (!businessName || !businessEmail || !adminName || !adminEmail || !password) {
      Alert.alert('Error', 'Please fill in all required fields');
      return;
    }

    setLoading(true);
    try {
      const result = await register({
        businessName,
        businessEmail,
        businessIndustry,
        adminName,
        adminEmail,
        password,
      });

      if (result?.requiresOtp) {
        navigation.navigate('VerifyOtp', { email: result.email || adminEmail });
      } else {
        navigation.reset({
          index: 0,
          routes: [{ name: 'Main' }],
        });
      }
    } catch (error: any) {
      Alert.alert('Error', error.response?.data?.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  const styles = createStyles(colors);

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <View style={styles.header}>
          <View style={styles.authIconContainer}>
            <LinearGradient
              colors={[colors.primary, colors.primaryLight]}
              style={styles.authIconGradient}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
            >
              <Ionicons name="person-add-outline" size={48} color="#fff" />
            </LinearGradient>
          </View>
          <Text style={styles.title}>Create Account</Text>
          <Text style={styles.subtitle}>Join Metroflow today</Text>
        </View>
        
        <Text style={styles.sectionTitle}>Business Information</Text>
        
        <View style={styles.inputContainer}>
          <Ionicons name="business-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TextInput
            style={styles.input}
            placeholder="Business Name"
            value={businessName}
            onChangeText={setBusinessName}
            placeholderTextColor={colors.textSecondary}
          />
        </View>
        
        <View style={styles.inputContainer}>
          <Ionicons name="mail-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TextInput
            style={styles.input}
            placeholder="Business Email"
            value={businessEmail}
            onChangeText={setBusinessEmail}
            keyboardType="email-address"
            autoCapitalize="none"
            placeholderTextColor={colors.textSecondary}
          />
        </View>
        
        <View style={styles.inputContainer}>
          <Ionicons name="briefcase-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TouchableOpacity
            style={styles.industryPicker}
            onPress={() => setShowIndustryDropdown(true)}
          >
            <Text style={[styles.input, businessIndustry ? {} : styles.placeholderText]}>
              {businessIndustry || 'Business Industry (Optional)'}
            </Text>
          </TouchableOpacity>
          {businessIndustry ? (
            <TouchableOpacity
              onPress={() => setBusinessIndustry('')}
              style={styles.clearIcon}
            >
              <Ionicons name="close-circle" size={20} color={colors.textSecondary} />
            </TouchableOpacity>
          ) : null}
        </View>

        <Modal
          visible={showIndustryDropdown}
          animationType="slide"
          transparent={true}
          onRequestClose={() => setShowIndustryDropdown(false)}
        >
          <View style={styles.modalOverlay}>
            <View style={[styles.modalContent, { backgroundColor: colors.background }]}>
              <View style={styles.modalHeader}>
                <Text style={[styles.modalTitle, { color: colors.text }]}>Select Industry</Text>
                <TouchableOpacity onPress={() => setShowIndustryDropdown(false)}>
                  <Ionicons name="close" size={24} color={colors.text} />
                </TouchableOpacity>
              </View>
              <View style={styles.searchContainer}>
                <Ionicons name="search-outline" size={20} color={colors.textSecondary} style={styles.searchIcon} />
                <TextInput
                  style={[styles.searchInput, { 
                    backgroundColor: colors.surface, 
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
                    style={[styles.industryItem, { backgroundColor: colors.surface }]}
                    onPress={() => {
                      setBusinessIndustry(item);
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
        
        <Text style={styles.sectionTitle}>Admin Information</Text>
        
        <View style={styles.inputContainer}>
          <Ionicons name="person-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TextInput
            style={styles.input}
            placeholder="Admin Full Name"
            value={adminName}
            onChangeText={setAdminName}
            placeholderTextColor={colors.textSecondary}
          />
        </View>
        
        <View style={styles.inputContainer}>
          <Ionicons name="mail-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TextInput
            style={styles.input}
            placeholder="Admin Email"
            value={adminEmail}
            onChangeText={setAdminEmail}
            keyboardType="email-address"
            autoCapitalize="none"
            placeholderTextColor={colors.textSecondary}
          />
        </View>
        
        <View style={styles.inputContainer}>
          <Ionicons name="lock-closed-outline" size={20} color={colors.textSecondary} style={styles.inputIcon} />
          <TextInput
            style={styles.input}
            placeholder="Password"
            value={password}
            onChangeText={setPassword}
            secureTextEntry={!showPassword}
            placeholderTextColor={colors.textSecondary}
          />
          <TouchableOpacity
            style={styles.eyeIcon}
            onPress={() => setShowPassword(!showPassword)}
          >
            <Ionicons
              name={showPassword ? 'eye-off-outline' : 'eye-outline'}
              size={20}
              color={colors.textSecondary}
            />
          </TouchableOpacity>
        </View>
        
        <TouchableOpacity 
          style={styles.buttonContainer}
          onPress={handleRegister}
          disabled={loading}
          activeOpacity={0.9}
        >
          <LinearGradient
            colors={[colors.primary, colors.primaryLight]}
            style={styles.button}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Create Account</Text>
            )}
          </LinearGradient>
        </TouchableOpacity>
        
        <View style={styles.signinContainer}>
          <Text style={styles.signinText}>Already have an account? </Text>
          <TouchableOpacity onPress={() => navigation.navigate('Login')}>
            <Text style={styles.signinLink}>Sign In</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const createStyles = (colors: any) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    paddingHorizontal: 24,
    paddingBottom: 40,
  },
  header: {
    alignItems: 'center',
    paddingTop: 32,
    paddingBottom: 28,
  },
  authIconContainer: {
    width: 100,
    height: 100,
    borderRadius: 28,
    marginBottom: 24,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 12,
    overflow: 'hidden',
  },
  authIconGradient: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    marginBottom: 8,
    color: colors.primary,
  },
  subtitle: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.text,
    marginBottom: 16,
    marginTop: 8,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: 16,
    paddingHorizontal: 16,
    marginBottom: 16,
  },
  inputIcon: {
    marginRight: 12,
  },
  input: {
    flex: 1,
    paddingVertical: 16,
    fontSize: 16,
    color: colors.text,
  },
  placeholderText: {
    color: colors.textSecondary,
  },
  industryPicker: {
    flex: 1,
  },
  clearIcon: {
    padding: 4,
    marginLeft: 8,
  },
  eyeIcon: {
    padding: 4,
    marginLeft: 8,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  modalContent: {
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    padding: 24,
    maxHeight: '70%',
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20,
  },
  modalTitle: {
    fontSize: 20,
    fontWeight: 'bold',
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
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
  buttonContainer: {
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 16,
    elevation: 12,
    marginTop: 24,
  },
  button: {
    padding: 18,
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  signinContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
  },
  signinText: {
    color: colors.textSecondary,
    fontSize: 15,
  },
  signinLink: {
    color: colors.primary,
    fontSize: 15,
    fontWeight: '600',
  },
});
