import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// Shared building blocks for the auth flow (splash → onboarding → login /
/// register / forgot / verify / reset).
///
/// Everything reads [AppTheme.colors] so dark mode works, centers content
/// with a max width of 480 (tablet/landscape) inside a
/// SingleChildScrollView (keyboard-safe), and fades+slides content in for a
/// subtle entrance.
/// ---------------------------------------------------------------------------

/// Brand indigo → violet wash used behind auth screens and the splash.
class BrandSplashGradient {
  BrandSplashGradient._();

  static const List<Color> colors = <Color>[
    Color(0xFF2563EB), // indigo-600 primary
    Color(0xFF4F46E5), // indigo-600
    Color(0xFF7C3AED), // violet-600
  ];

  static const LinearGradient gradient = LinearGradient(
    colors: colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: <Color>[Color(0xFF2563EB), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Scrollable, centered page shell with a fade + slide entrance.
class AuthScreenShell extends StatefulWidget {
  final List<Widget> children;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry padding;

  const AuthScreenShell({
    super.key,
    required this.children,
    this.onBack,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
  });

  @override
  State<AuthScreenShell> createState() => _AuthScreenShellState();
}

class _AuthScreenShellState extends State<AuthScreenShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: widget.padding.vertical / 2,
              bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.onBack != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _PillBackButton(onTap: widget.onBack!),
                      ),
                    ...widget.children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PillBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Material(
      color: colors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
    );
  }
}

/// Logo asset + wordmark + headline/subtitle block.
class AuthBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double logoSize;

  const AuthBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.logoSize = 84,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Column(
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.28),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.22),
                offset: const Offset(0, 10),
                blurRadius: 24,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.28),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Metricorex',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: colors.text,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

/// Rounded, icon-led input field used across the auth screens.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final String? counterText;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.maxLength,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.counterText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
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
            child: Icon(icon, color: colors.textSecondary, size: 21),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              maxLength: maxLength,
              textAlign: textAlign,
              autofocus: autofocus,
              autocorrect: false,
              enableSuggestions: keyboardType != TextInputType.number,
              style: style ?? TextStyle(color: colors.text, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 15),
                border: InputBorder.none,
                counterText: counterText,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Input with a trailing password-visibility toggle.
class AuthPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
  });

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
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
            child: Icon(Icons.lock_outline_rounded, color: colors.textSecondary, size: 21),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: !_visible,
              textInputAction: TextInputAction.done,
              onSubmitted: widget.onSubmitted,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: colors.text, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
          IconButton(
            tooltip: _visible ? 'Hide password' : 'Show password',
            icon: Icon(
              _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: colors.textSecondary,
              size: 21,
            ),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ],
      ),
    );
  }
}

/// Prominent full-width gradient CTA with a loading spinner state.
class AuthGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const AuthGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: BrandSplashGradient.buttonGradient,
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.30),
            offset: const Offset(0, 8),
            blurRadius: 18,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                  )
                else ...[
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Muted bottom prompt: "Don't have an account? Sign Up".
class AuthSwitchPrompt extends StatelessWidget {
  final String question;
  final String actionLabel;
  final VoidCallback onTap;

  const AuthSwitchPrompt({
    super.key,
    required this.question,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        Text(
          question,
          style: TextStyle(color: colors.textSecondary, fontSize: 14.5),
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            actionLabel,
            style: TextStyle(
              color: colors.primary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
