// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tongxin_frontend/app.dart';

void main() {
  testWidgets('App builds and shows navigation bar', (WidgetTester tester) async {
    await tester.pumpWidget(const TeacherHubApp());

    expect(find.text('主页'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
