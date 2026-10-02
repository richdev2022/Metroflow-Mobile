import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable 4-box numeric Transaction PIN input.
///
/// Implementation: a transparent TextField stacked over a Row of 4 styled
/// boxes. The invisible field keeps native keyboard handling AND paste
/// support for free, while only the boxes are visible. Digits are masked
/// with a big '•' once a box is filled.
///
/// Self-contained styling via [Theme.of(context)] (Material 3 color roles:
/// primary / outline / error) so it renders correctly on every screen and
/// theme without importing a specific screen's palette.
class PinInputBoxes extends StatefulWidget {
  const PinInputBoxes({
    super.key,
    this.controller,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.boxSize = 52,
    this.errorText,
  });

  /// Optional external controller — when provided the caller owns it (and
  /// reads `.text` for the PIN). Otherwise an internal one is used and the
  /// value is reported through [onChanged].
  final TextEditingController? controller;

  /// Called with the current digits (0–4) on every change.
  final ValueChanged<String>? onChanged;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Width of each box; height is [boxSize] + 4 (~52x56 default).
  final double boxSize;

  /// Optional validation message rendered below the boxes.
  final String? errorText;

  @override
  State<PinInputBoxes> createState() => _PinInputBoxesState();
}

class _PinInputBoxesState extends State<PinInputBoxes> {
  TextEditingController? _internalController;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  bool get _hasError => (widget.errorText ?? '').trim().isNotEmpty;

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _handleChanged(String raw) {
    // Hard-strip anything non-numeric (paste safety; the formatters above
    // already guard the keyboard path).
    final digits = raw.replaceAll(RegExp('[^0-9]'), '');
    if (digits != raw) {
      _effectiveController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    setState(() {}); // repaint the boxes
    widget.onChanged?.call(digits);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = _effectiveController.text;
    final hasError = _hasError;

    final stack = Stack(
      alignment: Alignment.center,
      children: [
        // The visible boxes. IgnorePointer so taps reach the TextField below.
        IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isLast = index == 3;
              return Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 10),
                child: _pinBox(index, text.length, scheme),
              );
            }),
          ),
        ),
        // Invisible field: owns focus, keyboard and paste.
        Positioned.fill(
          child: TextField(
            controller: _effectiveController,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.transparent,
              fontSize: 1,
              height: 1,
            ),
            cursorColor: Colors.transparent,
            cursorWidth: 0,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _handleChanged,
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stack,
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pinBox(int index, int length, ColorScheme scheme) {
    final filled = index < length;
    final size = widget.boxSize;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size + 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: filled ? 1.5 : 1.2,
          color: _hasError
              ? scheme.error.withValues(alpha: 0.8)
              : filled
                  ? scheme.primary
                  : scheme.outline,
        ),
      ),
      child: filled
          ? Text(
              '•',
              style: TextStyle(
                fontSize: size * 0.52,
                height: 1,
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
