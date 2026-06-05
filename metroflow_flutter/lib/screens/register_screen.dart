import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metroflow_flutter/providers/auth_provider.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';

const List<String> businessIndustries = [
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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController businessNameController = TextEditingController();
  final TextEditingController businessEmailController = TextEditingController();
  final TextEditingController adminNameController = TextEditingController();
  final TextEditingController adminEmailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController industrySearchController = TextEditingController();

  String? selectedIndustry;
  String industrySearchQuery = '';
  bool showPassword = false;
  bool isLoading = false;
  bool showIndustryModal = false;

  List<String> get filteredIndustries {
    return businessIndustries
        .where((industry) =>
            industry.toLowerCase().contains(industrySearchQuery.toLowerCase()))
        .toList();
  }

  @override
  void dispose() {
    businessNameController.dispose();
    businessEmailController.dispose();
    adminNameController.dispose();
    adminEmailController.dispose();
    passwordController.dispose();
    industrySearchController.dispose();
    super.dispose();
  }

  Future<void> handleRegister() async {
    if (businessNameController.text.isEmpty ||
        businessEmailController.text.isEmpty ||
        adminNameController.text.isEmpty ||
        adminEmailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')),
        );
      }
      return;
    }

    setState(() => isLoading = true);
    try {
      final result = await ref.read(authProvider.notifier).register({
        'businessName': businessNameController.text,
        'businessEmail': businessEmailController.text,
        'businessIndustry': selectedIndustry,
        'adminName': adminNameController.text,
        'adminEmail': adminEmailController.text,
        'password': passwordController.text,
      });

      if (result['requiresOtp'] == true) {
        if (mounted) {
          context.go('/verify-otp', extra: result['email'] ?? adminEmailController.text);
        }
      } else {
        if (mounted) {
          context.go('/main');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha:0.3),
                            offset: const Offset(0, 8),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.person_add_outlined, size: 48, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join Metroflow today',
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Business Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.business_outlined, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: businessNameController,
                            decoration: InputDecoration(
                              hintText: 'Business Name',
                              hintStyle: TextStyle(color: colors.textSecondary),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.mail_outlined, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: businessEmailController,
                            decoration: InputDecoration(
                              hintText: 'Business Email',
                              hintStyle: TextStyle(color: colors.textSecondary),
                              border: InputBorder.none,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.work_outline, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => showIndustryModal = true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                selectedIndustry ?? 'Business Industry (Optional)',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: selectedIndustry != null
                                      ? colors.text
                                      : colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (selectedIndustry != null)
                          GestureDetector(
                            onTap: () => setState(() => selectedIndustry = null),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Icon(Icons.close_outlined, color: colors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Admin Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.person_outlined, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: adminNameController,
                            decoration: InputDecoration(
                              hintText: 'Admin Full Name',
                              hintStyle: TextStyle(color: colors.textSecondary),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.mail_outlined, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: adminEmailController,
                            decoration: InputDecoration(
                              hintText: 'Admin Email',
                              hintStyle: TextStyle(color: colors.textSecondary),
                              border: InputBorder.none,
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.lock_outlined, color: colors.textSecondary),
                        ),
                        Expanded(
                          child: TextField(
                            controller: passwordController,
                            obscureText: !showPassword,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              hintStyle: TextStyle(color: colors.textSecondary),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => showPassword = !showPassword),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(
                              showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha:0.3),
                          offset: const Offset(0, 8),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.primary, colors.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: TextButton(
                          onPressed: isLoading ? null : handleRegister,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: Colors.white),
                                )
                              : const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(fontSize: 15, color: colors.textSecondary),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/login'),
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (showIndustryModal)
              Stack(
                children: [
                  ModalBarrier(
                    color: Colors.black.withValues(alpha:0.5),
                  ),
                  DraggableScrollableSheet(
                    initialChildSize: 0.7,
                    minChildSize: 0.5,
                    maxChildSize: 0.9,
                    builder: (context, scrollController) => Container(
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Select Industry',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colors.text,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, color: colors.text),
                                  onPressed: () {
                                    setState(() {
                                      industrySearchQuery = '';
                                      industrySearchController.text = '';
                                      showIndustryModal = false;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Container(
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border.all(color: colors.border, width: 1.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Icon(Icons.search_outlined, color: colors.textSecondary),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: industrySearchController,
                                      onChanged: (value) => setState(() => industrySearchQuery = value),
                                      decoration: InputDecoration(
                                        hintText: 'Search industries...',
                                        hintStyle: TextStyle(color: colors.textSecondary),
                                        border: InputBorder.none,
                                      ),
                                      style: TextStyle(color: colors.text, fontSize: 16),
                                      autofocus: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: filteredIndustries.length,
                                itemBuilder: (context, index) {
                                  final industry = filteredIndustries[index];
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        selectedIndustry = industry;
                                        industrySearchQuery = '';
                                        industrySearchController.text = '';
                                        showIndustryModal = false;
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        border: Border.all(color: colors.border),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        industry,
                                        style: TextStyle(fontSize: 16, color: colors.text),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
