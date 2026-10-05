// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ev/main.dart'; // keep your actual package name here

void main() {
  testWidgets('Home screen shows both navigation buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const EvChargeApp());

    expect(find.text('Plan a Trip'), findsOneWidget);
    expect(find.text('Nearby Stations'), findsOneWidget);
  });
}