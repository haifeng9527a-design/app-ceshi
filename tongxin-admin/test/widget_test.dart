import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tongxin_admin/main.dart';

void main() {
  testWidgets('Admin app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TongxinAdminApp());
    expect(find.text('后台管理'), findsOneWidget);
  });
}
