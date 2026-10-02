import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'pin_input_boxes.dart';

/// Transaction PIN setup gate (bottom sheet).
///
/// Shown from wallet / transfers / bulk-transfer when
/// GET /settings/otp-enabled reports `pinCreated == false`: explains why the
/// PIN is needed, collects a 4-digit PIN + confirmation with the shared
/// [PinInputBoxes] widget and creates it via POST /settings/pin.
///
/// Guarded by the caller (auto-prompt at most once per session per screen);
/// if the sheet is dismissed without creating a PIN it simply never loops.
Future<void> showPinSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _PinSetupSheet(),
  );
}

class _PinSetupSheet extends StatefulWidget {
  const _PinSetupSheet();

  @override
  State<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<_PinSetupSheet> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _creating = false;
  bool _checkedExisting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Double-check the PIN doesn't already exist before rendering the form.
    _verifyPinStatus();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyPinStatus() async {
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      final pinCreated = data is Map && data['pinCreated'] == true;
      if (!mounted) return;
      if (pinCreated) {
        // PIN already exists — close gracefully with an info toast.
        Navigator.of(context).pop();
        AppToast.show('Transaction PIN is already set up', type: AppToastType.info);
      }
    } catch (e) {
      debugPrint('PIN status check failed: $e');
    } finally {
      if (mounted) setState(() => _checkedExisting = true);
    }
  }

  Future<void> _createPin() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (pin.length != 4) {
      setState(() => _error = 'Enter your 4-digit PIN');
      return;
    }
    if (confirm.length != 4) {
      setState(() => _error = 'Confirm your 4-digit PIN');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match — try again');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ApiService().createPin(pin);
      AppToast.show('Transaction PIN created', type: AppToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final message = ApiService.extractErrorMessage(e).toLowerCase();
      final alreadyExists = message.contains('already') && message.contains('pin');
      if (mounted) Navigator.of(context).pop();
      AppToast.show(
        alreadyExists
            ? 'Transaction PIN is already set up'
            : ApiService.extractErrorMessage(e),
        type: alreadyExists ? AppToastType.info : AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryBg,
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(Icons.lock_outline_rounded, color: colors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Set up your Transaction PIN',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Your 4-digit Transaction PIN secures every transfer you send — '
                'keep it private and never share it.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 20),
              PinInputBoxes(
                controller: _pinController,
                autofocus: true,
                errorText: _error,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Confirm PIN',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              PinInputBoxes(
                controller: _confirmController,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _createPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create PIN',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              // Reserve a minimal height while the status check runs so the
              // sheet doesn't visibly jump when it resolves.
              if (!_checkedExisting) const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}
