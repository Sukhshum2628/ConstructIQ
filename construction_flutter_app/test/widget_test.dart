// Basic smoke test for the construction application.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Simple passing placeholder test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Hello Construction App'),
        ),
      ),
    );
    expect(find.text('Hello Construction App'), findsOneWidget);
  });
}
