import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../components/google_sign_in_button.dart';
import '../providers/auth_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_ui.dart';

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

  /// Google SSO sign-up/sign-in: reuses loginWithGoogle (isNewUser accounts
  /// get a trial from the backend), then routes like the login screen does —
  /// KYC check decides between /kyc-prompt and /main.
  Future<void> _handleGoogleSignIn() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      final success = await ref.read(authProvider.notifier).loginWithGoogle();
      if (!success) return; // user cancelled — stay on screen
      if (!mounted) return;
      await _routeAfterGoogleAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  /// Mirrors the login screen's post-login routing: KYC tier 1 not verified
  /// → /kyc-prompt, otherwise /main.
  Future<void> _routeAfterGoogleAuth() async {
    try {
      final response = await ApiService().getKycStatus();
      final data = response.data;
      final user = data['user'] as Map<String, dynamic>?;

      if (user == null && data['bvn_verified'] == null && data['nin_verified'] == null) {
        if (mounted) context.go('/main');
        return;
      }

      final bvnVerified = user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          data['bvn_verified'] == true;
      final ninVerified = user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          data['nin_verified'] == true;
      final isTier1Verified = bvnVerified || ninVerified;

      if (mounted) context.go(isTier1Verified ? '/main' : '/kyc-prompt');
    } catch (_) {
      if (mounted) context.go('/main');
    }
  }
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      body: Stack(
        children: [
          // Gradient accent band behind the header (clipped with a curve).
          ClipPath(
            clipper: _AuthHeaderCurve(),
            child: Container(
              height: 170,
              decoration: const BoxDecoration(
                gradient: BrandSplashGradient.buttonGradient,
              ),
            ),
          ),
          AuthScreenShell(
            children: [
              const SizedBox(height: 6),
              const AuthBrandHeader(
                title: 'Create your workspace',
                subtitle: 'Join Metricorex and run your business in one place.',
              ),
              const SizedBox(height: 30),
              _SectionLabel(label: 'Business Information', colors: colors),
              const SizedBox(height: 12),
              AuthTextField(
                controller: businessNameController,
                hint: 'Business Name',
                icon: Icons.business_outlined,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: businessEmailController,
                hint: 'Business Email',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _IndustryField(
                selectedIndustry: selectedIndustry,
                onOpen: () => setState(() => showIndustryModal = true),
                onClear: () => setState(() => selectedIndustry = null),
              ),
              const SizedBox(height: 22),
              _SectionLabel(label: 'Admin Information', colors: colors),
              const SizedBox(height: 12),
              AuthTextField(
                controller: adminNameController,
                hint: 'Admin Full Name',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: adminEmailController,
                hint: 'Admin Email',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AuthPasswordField(
                controller: passwordController,
                hint: 'Password',
              ),
              const SizedBox(height: 24),
              AuthGradientButton(
                label: 'Create Account',
                loading: isLoading,
                onPressed: handleRegister,
                icon: Icons.rocket_launch_rounded,
              ),
              const SizedBox(height: 22),
              const OrDivider(),
              const SizedBox(height: 16),
              GoogleSignInButton(
                onPressed: _handleGoogleSignIn,
                isLoading: isLoading,
              ),
              const SizedBox(height: 22),
              AuthSwitchPrompt(
                question: 'Already have an account?',
                actionLabel: 'Sign In',
                onTap: () => context.go('/login'),
              ),
            ],
          ),
          if (showIndustryModal)
            Stack(
              children: [
                ModalBarrier(
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                DraggableScrollableSheet(
                  initialChildSize: 0.7,
                  minChildSize: 0.5,
                  maxChildSize: 0.9,
                  builder: (context, scrollController) => Container(
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
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
                                  fontWeight: FontWeight.w800,
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
                              border:
                                  Border.all(color: colors.border, width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Icon(Icons.search_outlined,
                                      color: colors.textSecondary),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: industrySearchController,
                                    onChanged: (value) => setState(
                                        () => industrySearchQuery = value),
                                    decoration: InputDecoration(
                                      hintText: 'Search industries...',
                                      hintStyle: TextStyle(
                                          color: colors.textSecondary),
                                      border: InputBorder.none,
                                    ),
                                    style:
                                        TextStyle(color: colors.text, fontSize: 16),
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
                                final selected = industry == selectedIndustry;
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  leading: Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.category_outlined,
                                    color: selected
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                  title: Text(
                                    industry,
                                    style: TextStyle(
                                      color: colors.text,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      selectedIndustry = industry;
                                      industrySearchQuery = '';
                                      industrySearchController.text = '';
                                      showIndustryModal = false;
                                    });
                                  },
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
    );
  }
}

/// Small uppercase section label between form groups.
class _SectionLabel extends StatelessWidget {
  final String label;
  final ThemeColors colors;

  const _SectionLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: colors.textSecondary,
      ),
    );
  }
}

/// Tappable field that opens the industry picker sheet.
class _IndustryField extends StatelessWidget {
  final String? selectedIndustry;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  const _IndustryField({
    required this.selectedIndustry,
    required this.onOpen,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final hasValue = (selectedIndustry ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.work_outline, color: colors.textSecondary, size: 21),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  selectedIndustry ?? 'Business Industry',
                  style: TextStyle(
                    fontSize: 15,
                    color:
                        hasValue ? colors.text : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          if (hasValue)
            IconButton(
              tooltip: 'Clear industry',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded,
                  color: colors.textSecondary, size: 19),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  color: colors.textSecondary, size: 22),
            ),
        ],
      ),
    );
  }
}

/// Soft curved bottom edge for the gradient header band.
class _AuthHeaderCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height - 40)
      ..quadraticBezierTo(
          size.width / 2, size.height + 30, size.width, size.height - 40)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}
