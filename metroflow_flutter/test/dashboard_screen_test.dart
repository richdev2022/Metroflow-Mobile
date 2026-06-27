import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:metricorex_flutter/theme/app_theme.dart';

void main() {
  testWidgets('Test basic widget rendering', (tester) async {
    // Build a simple test widget
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Test')),
          ),
          theme: AppTheme.lightTheme,
        ),
      ),
    );

    // Verify basic elements are present
    expect(find.text('Test'), findsOneWidget);
  });
}
