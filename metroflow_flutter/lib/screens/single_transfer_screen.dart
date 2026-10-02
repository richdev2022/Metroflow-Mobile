import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/single_transfer_sheet.dart';

/// Standalone "New Transfer" page hosting the shared [SingleTransferSheet]
/// form (same flow as the wallet's Send Money modal, but as a routed page —
/// reachable from the Transfers screen's "Make New Transfer" entry point).
class SingleTransferScreen extends StatelessWidget {
  const SingleTransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: colors.border,
        iconTheme: IconThemeData(color: colors.text),
        title: Text(
          'New Transfer',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
      ),
      body: const SingleTransferSheet(asPage: true),
    );
  }
}
