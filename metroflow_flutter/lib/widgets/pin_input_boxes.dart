import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable 4-box numeric Transaction PIN input.
///
/// SMART & FREE DESIGN (no stacking): four REAL TextFields laid out in a Row,
/// each with its own FocusNode. Focus travels forward as digits are typed and
/// backward on backspace; pasting a 4-digit code into ANY box distributes the
/// digits across all boxes. There is no invisible overlay field any more —
/// that old Stack design rendered transparent glyphs/selection handles on top
/// of the boxes and felt like the input was "overlapping".
///
/// Digits are masked with a big '•' (banking standard) and the active box
/// glows with the primary color. Each box exposes its own caret, so the
/// keyboard, cursor and text-selection toolbar behave exactly like a native
/// single-character field.
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

  /// Optional external focus node — attached to the FIRST box so callers can
  /// requestFocus() to open the keyboard (legacy API compatibility).
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
  late final List<FocusNode> _nodes;
  late final List<TextEditingController> _boxControllers;
  bool _syncing = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  bool get _hasError => (widget.errorText ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(4, (i) {
      if (i == 0 && widget.focusNode != null) {
        // Legacy external focus node goes on the FIRST box so external
        // requestFocus() keeps working.
        return widget.focusNode!;
      }
      // Backspace on an EMPTY box steps back and clears the previous digit.
      return FocusNode(
        onKeyEvent: (node, event) => _handleKey(i, node, event),
      );
    });
    _boxControllers = List.generate(4, (_) => TextEditingController());
    _hydrateBoxesFromMaster();
    _effectiveController.addListener(_masterChanged);
  }

  @override
  void didUpdateWidget(covariant PinInputBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _effectiveController.removeListener(_masterChanged);
      _internalController?.dispose();
      _internalController = null;
      _effectiveController.addListener(_masterChanged);
      _hydrateBoxesFromMaster();
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_masterChanged);
    _internalController?.dispose();
    for (final n in _nodes) {
      // Never dispose the caller-owned node.
      if (n != widget.focusNode) n.dispose();
    }
    for (final c in _boxControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rebuild the per-box controllers from the master controller's text.
  void _hydrateBoxesFromMaster() {
    _syncing = true;
    final digits = _effectiveController.text.replaceAll(RegExp('[^0-9]'), '');
    for (int i = 0; i < 4; i++) {
      final ch = i < digits.length ? digits[i] : '';
      if (_boxControllers[i].text != ch) {
        _boxControllers[i].text = ch;
      }
    }
    _syncing = false;
  }

  /// External/controller-level changes (clear() etc.) flow into the boxes.
  void _masterChanged() {
    if (_syncing) return;
    _hydrateBoxesFromMaster();
    if (mounted) setState(() {});
  }

  void _pushToMaster() {
    if (_syncing) return;
    _syncing = true;
    final digits = _boxControllers.map((c) => c.text).join();
    final digitsOnly = digits.replaceAll(RegExp('[^0-9]'), '');
    if (_effectiveController.text != digitsOnly) {
      _effectiveController.value = TextEditingValue(
        text: digitsOnly,
        selection: TextSelection.collapsed(offset: digitsOnly.length),
      );
    }
    _syncing = false;
    widget.onChanged?.call(digitsOnly);
    if (mounted) setState(() {});
  }

  void _handleBoxChanged(int index, String value) {
    if (_syncing) return;
    final digits = value.replaceAll(RegExp('[^0-9]'), '');

    // PASTE (or fast multi-char input) into this box: distribute the digits
    // from this box onward.
    if (digits.length > 1) {
      _syncing = true;
      for (int i = 0; i < 4; i++) {
        final ch = (index + i) < digits.length ? digits[index + i] : (i < index ? _boxControllers[i].text : '');
        if (i >= index) {
          _boxControllers[i].text = (index + i) < digits.length ? digits[index + i] : '';
        } else {
          _boxControllers[i].text = ch;
        }
      }
      _syncing = false;
      _pushToMaster();
      final filledUpTo = (index + digits.length).clamp(0, 4);
      final next = filledUpTo >= 4 ? 3 : filledUpTo;
      _nodes[next].requestFocus();
      return;
    }

    // Single digit typed: store it and move forward.
    _boxControllers[index].text = digits;
    if (digits.isNotEmpty && index < 3) {
      _nodes[index + 1].requestFocus();
    }
    _pushToMaster();
  }

  KeyEventResult _handleKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final box = _boxControllers[index];
      if (box.text.isEmpty && index > 0) {
        // Backspace on an empty box: step back AND clear the previous digit.
        _boxControllers[index - 1].clear();
        _pushToMaster();
        _nodes[index - 1].requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = _hasError;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == 3 ? 0 : 12),
              child: _pinBox(index, scheme),
            );
          }),
        ),
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

  Widget _pinBox(int index, ColorScheme scheme) {
    final size = widget.boxSize;

    return AnimatedBuilder(
      animation: Listenable.merge([_nodes[index], _boxControllers[index]]),
      builder: (context, _) {
        final isFilled = _boxControllers[index].text.isNotEmpty;
        final isFocused = _nodes[index].hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: size,
          height: size + 4,
          decoration: BoxDecoration(
            color: isFocused
                ? scheme.primary.withValues(alpha: 0.10)
                : isFilled
                    ? scheme.primary.withValues(alpha: 0.06)
                    : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: isFocused ? 2 : 1.2,
              color: _hasError
                  ? scheme.error.withValues(alpha: 0.85)
                  : isFocused
                      ? scheme.primary
                      : isFilled
                          ? scheme.primary.withValues(alpha: 0.55)
                          : scheme.outline.withValues(alpha: 0.7),
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: TextField(
            controller: _boxControllers[index],
            focusNode: _nodes[index],
            autofocus: widget.autofocus && index == 0,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4), // allow paste of the whole PIN
            ],
            obscureText: true,
            obscuringCharacter: '•',
            style: TextStyle(
              fontSize: size * 0.46,
              height: 1,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
            cursorColor: scheme.primary,
            cursorWidth: 1.6,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (value) => _handleBoxChanged(index, value),
          ),
        );
      },
    );
  }
}
