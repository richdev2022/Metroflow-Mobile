import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// Dispute Transaction bottom sheet.
///
/// End-to-end flow: customer picks a category, describes the issue, attaches
/// evidence (image/PDF) and submits — the dispute (reference, details,
/// message, attachment) lands on the admin desk, which can reverse (guarded),
/// recheck with the provider, or close it. The customer is notified at every
/// lifecycle step by the backend (push + email + in-app).
/// ---------------------------------------------------------------------------
class DisputeSheet extends StatefulWidget {
  final String reference;
  final double amount;
  final String currency;

  /// Optional pre-selected category (e.g. 'failed_transfer' when opened from
  /// a failed transfer's receipt).
  final String? initialCategory;

  const DisputeSheet({
    super.key,
    required this.reference,
    required this.amount,
    required this.currency,
    this.initialCategory,
  });

  /// Convenience opener.
  static Future<void> show(
    BuildContext context, {
    required String reference,
    required double amount,
    required String currency,
    String? initialCategory,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => DisputeSheet(
        reference: reference,
        amount: amount,
        currency: currency,
        initialCategory: initialCategory,
      ),
    );
  }

  @override
  State<DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<DisputeSheet> {
  static const brand = Color(0xFF2563EB);

  static const _categories = <(String, String)>[
    ('failed_transfer', 'Failed transfer'),
    ('not_received', 'Recipient not credited'),
    ('double_debit', 'Debited twice'),
    ('unauthorized', 'Unauthorized'),
    ('amount_mismatch', 'Wrong amount'),
    ('other', 'Something else'),
  ];

  String _category = 'failed_transfer';
  final _messageController = TextEditingController();
  String? _attachmentPath;
  String? _attachmentName;
  bool _submitting = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final valid = widget.initialCategory;
    if (valid != null && _categories.any((c) => c.$1 == valid)) {
      _category = valid;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: false,
      );
      final file = result?.files.single;
      if (file == null) return;
      if ((file.size ?? 0) > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attachment must be 10MB or smaller')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _attachmentPath = file.path;
        _attachmentName = file.name;
      });
    } catch (_) {
      // Picker dismissed or unavailable — non-fatal.
    }
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please describe the issue (at least 10 characters)')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await ApiService().createDispute(
        reference: widget.reference,
        category: _category,
        message: message,
        attachmentPath: _attachmentPath,
        attachmentName: _attachmentName,
      );
      final ok = response.data is Map && response.data['success'] == true;
      if (!mounted) return;
      if (ok) {
        setState(() => _done = true);
      } else {
        final data = response.data;
        final error = data is Map
            ? (data['error'] ?? data['message'])?.toString()
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Could not file the dispute — try again')),
        );
      }
    } catch (e) {
      String msg = 'Could not file the dispute — try again';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) {
          msg = (data['error'] ?? data['message'] ?? msg).toString();
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _done ? _buildDone(colors) : _buildForm(colors),
        ),
      ),
    );
  }

  Widget _buildDone(ThemeColors colors) {
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.check_circle_rounded, color: colors.success, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Dispute received',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Our team will investigate and keep you updated via notifications and email at every step.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: colors.textSecondary),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [brand, Color(0xFF3B82F6)],
                ),
              ),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(ThemeColors colors) {
    return Padding(
      key: const ValueKey('form'),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom * 0.4),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Dispute this transaction',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.currency} ${widget.amount.toStringAsFixed(2)} • ${widget.reference}',
                    style: TextStyle(
                        fontSize: 12.5, color: colors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((entry) {
                final selected = _category == entry.$1;
                return ChoiceChip(
                  label: Text(entry.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = entry.$1),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : colors.textSecondary,
                  ),
                  selectedColor: brand,
                  backgroundColor: colors.textSecondary.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: selected ? brand : colors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Tell us what happened — include any details that help us investigate.',
                hintStyle: TextStyle(fontSize: 13.5, color: colors.textSecondary),
                filled: true,
                fillColor: colors.textSecondary.withValues(alpha: 0.06),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _attachmentPath == null
                      ? OutlinedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Attach evidence (image / PDF)'),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: brand.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_rounded,
                                  size: 18, color: brand),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _attachmentName ?? 'attachment',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _attachmentPath = null;
                                  _attachmentName = null;
                                }),
                                child: const Icon(Icons.close_rounded,
                                    size: 18),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [brand, Color(0xFF3B82F6)],
                  ),
                ),
                child: TextButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Submit dispute',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
