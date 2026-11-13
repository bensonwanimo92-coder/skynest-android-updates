import 'package:chuka/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SkyNest root widget builds the application shell', (tester) async {
    // Remote photo backdrops are a production enhancement, not a dependency
    // of the application shell. Keep this smoke test fully offline.
    await tester.pumpWidget(const SkynestApp(enableRemoteBackdrops: false));
    await tester.pump();

    expect(find.byType(SkynestApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
