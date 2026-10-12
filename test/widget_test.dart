import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_vois/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build the VoisApp widget - this verifies the widget tree can be constructed
    await tester.pumpWidget(const VoisApp());
    // The bootstrap screen should show a loading indicator or error
    await tester.pump();
    // Verify the MaterialApp is present
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
