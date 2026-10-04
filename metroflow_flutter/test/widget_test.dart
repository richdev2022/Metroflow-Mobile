import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('Basic widget test', (WidgetTester tester) async {
    // Build a simple test widget
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Hello'),
            ),
          ),
        ),
      ),
    );

    // Verify the text is present
    expect(find.text('Hello'), findsOneWidget);
  });
}
// ignore_for_file: prefer_const_constructors
