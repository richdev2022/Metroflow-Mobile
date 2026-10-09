import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/modern_ui.dart';

/// Business KYC upgrade — moves a Non-Registered business to Registered
/// ("Verified") so the higher transaction limits unlock.
///
/// Loads GET /business-kyc/config (registration types + required documents)
/// and GET /business-kyc/status (current category, pending submission,
/// limits) and renders one of three views:
///   1. latestSubmission.status == 'pending' → review card (no wizard).
///   2. business.isRegistered == true → verified card.
///   3. otherwise → 3-step wizard:
///        step 1  pick a registration type from the server config,
///        step 2  business description (>= 20 chars) + limits explainer,
///        step 3  one upload slot per required document of the chosen type
///                (file_picker — images/PDF, <= 10 MB each),
///      then POST /business-kyc/submit as multipart FormData (docKinds JSON
///      aligned by index with the `documents` files).
///
/// Error codes handled: SUBMISSION_PENDING (switches to the review card),
/// DOCUMENTS_MISSING (+ data.missing list), FILE_TOO_LARGE,
/// DESCRIPTION_TOO_SHORT, INVALID_REGISTRATION_TYPE.
class BusinessKycUpgradeScreen extends StatefulWidget {
  const BusinessKycUpgradeScreen({super.key});

  @override
  State<BusinessKycUpgradeScreen> createState() =>
      _BusinessKycUpgradeScreenState();
}

class _BusinessKycUpgradeScreenState extends State<BusinessKycUpgradeScreen> {
  static const int _maxFileBytes = 10 * 1024 * 1024; // 10 MB per document
  static const int _minDescriptionChars = 20;

  Map<String, dynamic>? _config;
  Map<String, dynamic>? _status;
  bool _loading = true;

  // Wizard state.
  int _step = 0;
  String? _selectedTypeId;
  final TextEditingController _descriptionController = TextEditingController();
  final Map<String, PlatformFile> _picked = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Fetches config + status concurrently; each failure degrades to an empty
  /// map (the wizard shows a retry card when config is unavailable).
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final api = ApiService();
    final results = await Future.wait([
      _safe(api.getBusinessKycConfig),
      _safe(api.getBusinessKycStatus),
    ]);
    if (!mounted) return;
    setState(() {
      _config = results[0];
      _status = results[1];
      _loading = false;
    });
  }

  Future<Map<String, dynamic>> _safe(
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ---- Derived view state (defensive — the API nulls nested fields) ----

  Map<dynamic, dynamic>? get _business {
    final b = _status?['business'];
    return b is Map ? b : null;
  }

  bool get _isRegistered => _business?['isRegistered'] == true;

  Map<dynamic, dynamic>? get _submission {
    final s = _status?['latestSubmission'];
    return s is Map ? s : null;
  }

  bool get _isPending => _submission?['status'] == 'pending';

  List<Map<String, dynamic>> get _registrationTypes {
    final list = _config?['registrationTypes'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
  }

  Map<String, dynamic>? get _selectedType {
    for (final t in _registrationTypes) {
      if (t['id']?.toString() == _selectedTypeId) return t;
    }
    return null;
  }

  /// Document slots for the chosen registration type (required + optional).
  List<Map<String, dynamic>> get _typeDocuments {
    final docs = _selectedType?['documents'];
    if (docs is! List) return [];
    return docs
        .whereType<Map>()
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
  }

  Map<String, dynamic>? get _statusLimits {
    final l = _status?['limits'];
    return l is Map ? Map<String, dynamic>.from(l) : null;
  }

  // ---- Formatting helpers ----

  static String _currencySymbol(String? currency) {
    switch ((currency ?? 'NGN').toUpperCase()) {
      case 'NGN':
        return '₦';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$currency ';
    }
  }

  /// 50000 -> "50,000" (#,## thousands separators, decimals dropped).
  static String _formatAmount(dynamic value) {
    final n = double.tryParse(value?.toString() ?? '') ?? 0;
    return n
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  static String _formatDate(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _friendly(Object e) {
    final message = e.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text(
          'Business Verification',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _isPending
                  ? _buildPendingCard(colors)
                  : (_isRegistered
                      ? _buildVerifiedCard(colors)
                      : _buildWizard(colors)),
            ),
    );
  }

  // ---- View 1: pending review ----

  Widget _buildPendingCard(ThemeColors colors) {
    final submittedAt =
        _formatDate(_submission?['createdAt'] ?? _submission?['reviewedAt']);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TintedCircleIcon(
              icon: Icons.hourglass_top_rounded,
              tint: colors.warning,
              size: 52,
              iconSize: 26,
            ),
            const SizedBox(height: 14),
            Text(
              'Business verification under review',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We'll notify you once your documents are approved — your upgraded Registered (Verified) limits unlock automatically.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
            if (submittedAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Submitted $submittedAt',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Refresh status'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _backToDashboard(),
                  child: const Text('Back to dashboard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- View 2: verified ----

  Widget _buildVerifiedCard(ThemeColors colors) {
    final limits = _statusLimits;
    final inner = limits?['limits'] is Map
        ? Map<String, dynamic>.from(limits!['limits'] as Map)
        : <String, dynamic>{};
    final symbol = _currencySymbol(limits?['currency']?.toString());
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.success.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TintedCircleIcon(
              icon: Icons.verified_rounded,
              tint: colors.success,
              size: 52,
              iconSize: 26,
            ),
            const SizedBox(height: 14),
            Text(
              'Business verified',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your business is registered and verified — the higher Registered limits are active on your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            _limitRow(
              colors,
              'Per transaction',
              '$symbol${_formatAmount(inner['singleTransactionLimit'])}',
            ),
            _limitRow(
              colors,
              'Daily',
              '$symbol${_formatAmount(inner['dailyLimit'])}',
            ),
            _limitRow(
              colors,
              'Monthly',
              '$symbol${_formatAmount(inner['monthlyLimit'])}',
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _backToDashboard(),
              child: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- View 3: wizard ----

  Widget _buildWizard(ThemeColors colors) {
    if (_registrationTypes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TintedCircleIcon(
                icon: Icons.cloud_off_rounded,
                tint: colors.warning,
                size: 52,
                iconSize: 26,
              ),
              const SizedBox(height: 14),
              Text(
                "Couldn't load registration options",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stepper(
      currentStep: _step,
      physics: const ClampingScrollPhysics(),
      onStepTapped: (s) {
        if (_submitting) return;
        setState(() => _step = s);
      },
      controlsBuilder: (context, details) {
        final isLast = _step == 2;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: _submitting ? null : details.onStepCancel,
                  child: const Text('Back'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitting ? null : _onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                ),
                child: _submitting && isLast
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isLast ? 'Submit for review' : 'Continue'),
              ),
            ],
          ),
        );
      },
      steps: [
        Step(
          title: Text(
            'Registration type',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          subtitle: Text(
            'How is your business registered?',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          isActive: _step >= 0,
          content: _buildTypeStep(colors),
        ),
        Step(
          title: Text(
            'About your business',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          subtitle: Text(
            'Describe what your business does',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          isActive: _step >= 1,
          content: _buildDescriptionStep(colors),
        ),
        Step(
          title: Text(
            'Documents',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          subtitle: Text(
            'Upload the required proof',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          isActive: _step >= 2,
          content: _buildDocsStep(colors),
        ),
      ],
    );
  }

  Widget _buildTypeStep(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in _registrationTypes) ...[
          _typeOptionCard(colors, t),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _typeOptionCard(ThemeColors colors, Map<String, dynamic> type) {
    final id = type['id']?.toString() ?? '';
    final selected = _selectedTypeId == id;
    final label = type['label']?.toString() ?? id;
    final authority = type['authority']?.toString() ?? '';
    final description = type['description']?.toString() ?? '';
    return InkWell(
      onTap: () {
        if (_selectedTypeId == id) return;
        // Switching type resets the document slots (different doc packs).
        setState(() {
          _selectedTypeId = id;
          _picked.clear();
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? colors.primaryBg : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.6 : 1.2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? colors.primary : colors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  if (authority.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        authority,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionStep(ThemeColors colors) {
    final limits = _statusLimits;
    final inner = limits?['limits'] is Map
        ? Map<String, dynamic>.from(limits!['limits'] as Map)
        : <String, dynamic>{};
    final registered = limits?['registeredLimits'] is Map
        ? Map<String, dynamic>.from(limits!['registeredLimits'] as Map)
        : <String, dynamic>{};
    final symbol = _currencySymbol(limits?['currency']?.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          maxLength: 1000,
          enabled: !_submitting,
          decoration: InputDecoration(
            hintText:
                'e.g. We sell groceries and household items in Surulere, Lagos…',
            hintStyle: TextStyle(color: colors.textSecondary, fontSize: 13.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Minimum $_minDescriptionChars characters — this helps our reviewers verify your business.',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed_rounded,
                      size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'What verification unlocks',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _limitRow(
                colors,
                'Per transaction',
                '$symbol${_formatAmount(inner['singleTransactionLimit'])} → $symbol${_formatAmount(registered['singleTransactionLimit'])}',
              ),
              _limitRow(
                colors,
                'Daily',
                '$symbol${_formatAmount(inner['dailyLimit'])} → $symbol${_formatAmount(registered['dailyLimit'])}',
              ),
              _limitRow(
                colors,
                'Monthly',
                '$symbol${_formatAmount(inner['monthlyLimit'])} → $symbol${_formatAmount(registered['monthlyLimit'])}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _limitRow(ThemeColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocsStep(ThemeColors colors) {
    final docs = _typeDocuments;
    if (docs.isEmpty) {
      return Text(
        'No documents are required for this registration type — continue to submit.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: colors.textSecondary,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload each document — images or PDF, up to 10 MB per file.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final doc in docs) ...[
          _docSlot(colors, doc),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _docSlot(ThemeColors colors, Map<String, dynamic> doc) {
    final id = doc['id']?.toString() ?? '';
    final required = doc['required'] == true;
    final picked = _picked[id];
    final label = doc['label']?.toString() ?? id;
    final description = doc['description']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: picked != null ? colors.success : colors.border,
          width: picked != null ? 1.4 : 1.2,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            picked != null
                ? Icons.check_circle_rounded
                : Icons.upload_file_rounded,
            size: 22,
            color: picked != null ? colors.success : colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    Text(
                      required ? 'Required' : 'Optional',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: required ? colors.error : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                if (picked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      picked.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: _submitting ? null : () => _pickDoc(id),
            child: Text(picked != null ? 'Change' : 'Choose file'),
          ),
        ],
      ),
    );
  }

  // ---- Actions ----

  Future<void> _pickDoc(String docId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.size > _maxFileBytes) {
        AppToast.show(
          '"${file.name}" is over the 10 MB limit — please pick a smaller file',
          type: AppToastType.warning,
        );
        return;
      }
      if (!mounted) return;
      setState(() => _picked[docId] = file);
    } catch (e) {
      AppToast.show('Could not open the file picker', type: AppToastType.error);
    }
  }

  bool _validateCurrentStep() {
    if (_step == 0 && _selectedTypeId == null) {
      AppToast.show(
        'Choose a registration type to continue',
        type: AppToastType.warning,
      );
      return false;
    }
    if (_step == 1 &&
        _descriptionController.text.trim().length < _minDescriptionChars) {
      AppToast.show(
        'Please describe your business in at least $_minDescriptionChars characters',
        type: AppToastType.warning,
      );
      return false;
    }
    if (_step == 2) {
      for (final doc in _typeDocuments) {
        if (doc['required'] != true) continue;
        final id = doc['id']?.toString() ?? '';
        if (!_picked.containsKey(id)) {
          AppToast.show(
            'Please upload "${doc['label']?.toString() ?? id}" to continue',
            type: AppToastType.warning,
          );
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _onContinue() async {
    if (!_validateCurrentStep()) return;
    if (_step < 2) {
      setState(() => _step = _step + 1);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final typeId = _selectedTypeId;
    if (typeId == null || _submitting) return;

    // docKinds (JSON array) is aligned BY INDEX with the files the API layer
    // posts under `documents` — both are built from this same ordered list.
    final docs = <Map<String, String>>[];
    for (final doc in _typeDocuments) {
      final id = doc['id']?.toString() ?? '';
      final file = _picked[id];
      if (file == null) continue; // optional slot (required ones validated)
      final path = file.path;
      if (path == null || path.isEmpty) {
        AppToast.show(
          '"${file.name}" needs to be picked again before submitting',
          type: AppToastType.error,
        );
        return;
      }
      docs.add({'path': path, 'kind': id});
    }

    setState(() => _submitting = true);
    try {
      await ApiService().submitBusinessKycUpgrade(
        registrationType: typeId,
        businessDescription: _descriptionController.text.trim(),
        documents: docs,
      );
      if (!mounted) return;
      await _showSuccessDialog();
    } on DioException catch (e) {
      if (!mounted) return;
      _handleSubmitError(e);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(_friendly(e), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleSubmitError(DioException e) {
    final data = e.response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    // Reuses the API layer's extractor (message/error keys, 413 handling) —
    // the interceptor has already decrypted any payload envelope by now.
    final message = ApiService.extractErrorMessage(e);

    switch (code) {
      case 'SUBMISSION_PENDING':
        // A submission is already under review — flip to the review card.
        AppToast.show(message, type: AppToastType.info);
        _load();
        return;
      case 'DOCUMENTS_MISSING':
        final payload = data is Map && data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : <String, dynamic>{};
        final missing = payload['missing'];
        final detail = missing is List && missing.isNotEmpty
            ? ' — missing: ${missing.join(', ')}'
            : '';
        AppToast.show('$message$detail', type: AppToastType.error);
        return;
      case 'FILE_TOO_LARGE':
      case 'DESCRIPTION_TOO_SHORT':
      case 'INVALID_REGISTRATION_TYPE':
        AppToast.show(message, type: AppToastType.error);
        return;
      default:
        AppToast.show(message, type: AppToastType.error);
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            const SizedBox(width: 8),
            const Expanded(child: Text('Submitted')),
          ],
        ),
        content: const Text(
          "Your business verification was submitted and is now under review. We'll notify you once it's approved.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _backToDashboard();
  }

  /// Back to the dashboard: pop (this screen is pushed over it) or, when
  /// there is nothing to pop, land on /main directly.
  void _backToDashboard() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }
}
