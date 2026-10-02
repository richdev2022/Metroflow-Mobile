import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      // Primary-blue app bar + transparent status bar so the network/battery
      // icons stay readable — consistent with the main shell and the other
      // money screens (transfers, fund wallet).
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        elevation: 0,
        title: Text(
          'New Transfer',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: const SingleTransferSheet(asPage: true),
    );
  }
}
