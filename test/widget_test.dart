import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Material app smoke test', (WidgetTester tester) async {
    // Basic smoke test that verifies the test framework works
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('OMR 答题卡阅卷')),
        ),
      ),
    );
    expect(find.text('OMR 答题卡阅卷'), findsOneWidget);
  });
}
