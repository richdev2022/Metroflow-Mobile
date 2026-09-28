import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'modern_ui.dart';

/// Shared avatar used everywhere a person (or conversation) is shown.
///
/// Renders the network picture when available (graceful fallback while
/// loading / on error) and otherwise a deterministic gradient circle with
/// the person's initials — the same palette as [AvatarInitials], so avatars
/// look consistent across chat, dashboard, profile and board screens.
class AvatarWithInitials extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final Widget? badge;

  const AvatarWithInitials({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 22,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final url = ApiService.resolveMediaUrl(imageUrl);
    final size = radius * 2;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: avatarGradientFor(name),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initialsForName(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.72,
          ),
        ),
      ),
    );

    Widget avatar;
    if (url == null || url.isEmpty) {
      avatar = fallback;
    } else {
      avatar = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          ),
        ),
      );
    }

    if (badge == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(right: -2, bottom: -2, child: badge!),
      ],
    );
  }
}

/// Small circular badge with a [Icons.group_rounded] glyph — used on group
/// conversation avatars.
class GroupAvatarBadge extends StatelessWidget {
  final double size;

  const GroupAvatarBadge({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: Icon(Icons.group_rounded, size: size * 0.6, color: colors.textSecondary),
    );
  }
}
