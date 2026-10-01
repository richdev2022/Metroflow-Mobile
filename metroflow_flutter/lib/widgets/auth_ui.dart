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
        // Logo inside a glowing halo — layered rings give the mark a
        // floating, 3D feel that matches the web landing page.
        SizedBox(
          width: logoSize + 44,
          height: logoSize + 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: logoSize + 44,
                height: logoSize + 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.primary.withValues(alpha: 0.14),
                      colors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Container(
                width: logoSize + 20,
                height: logoSize + 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.18),
                    width: 1.4,
                  ),
                ),
              ),
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(logoSize * 0.28),
                  color: colors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.30),
                      offset: const Offset(0, 12),
                      blurRadius: 30,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      offset: const Offset(0, 4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(logoSize * 0.06),
                  child: Image.asset(
                    'assets/images/logo-mark.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ShaderMask(
          shaderCallback: (bounds) => BrandSplashGradient.buttonGradient.createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          child: Text(
            'Metricorex',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
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
class AuthTextField extends StatefulWidget {
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
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: _focused ? colors.primary : colors.border,
          width: _focused ? 1.8 : 1.4,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (_focused)
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.14),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              widget.icon,
              color: _focused ? colors.primary : colors.textSecondary,
              size: 21,
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              maxLength: widget.maxLength,
              textAlign: widget.textAlign,
              autofocus: widget.autofocus,
              autocorrect: false,
              enableSuggestions: widget.keyboardType != TextInputType.number,
              style: widget.style ?? TextStyle(color: colors.text, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 15),
                border: InputBorder.none,
                counterText: widget.counterText,
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
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: _focused ? colors.primary : colors.border,
          width: _focused ? 1.8 : 1.4,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (_focused)
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.14),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.lock_outline_rounded,
              color: _focused ? colors.primary : colors.textSecondary,
              size: 21,
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
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

/// Prominent full-width gradient CTA with a loading spinner state and a
/// springy press-down animation.
class AuthGradientButton extends StatefulWidget {
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
  State<AuthGradientButton> createState() => _AuthGradientButtonState();
}

class _AuthGradientButtonState extends State<AuthGradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final loading = widget.loading;
    return GestureDetector(
      onTapDown: loading ? null : (_) => _press.forward(),
      onTapUp: (_) => _press.reverse(),
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: BrandSplashGradient.buttonGradient,
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.34),
                offset: const Offset(0, 10),
                blurRadius: 22,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: loading ? null : widget.onPressed,
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
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
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
