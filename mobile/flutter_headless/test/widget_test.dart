import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sillytavern_headless/main.dart';

void main() {
  testWidgets('renders the mobile navigation destinations', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
