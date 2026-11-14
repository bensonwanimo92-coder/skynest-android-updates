import 'package:chuka/main.dart';
import 'package:chuka/reading/reading_hub.dart';
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
    expect(find.byType(StartupGate), findsOneWidget);
  });

  testWidgets('Reading Hub exposes original booklets and offline downloads', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReadingHubScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Reading & Media Hub'), findsOneWidget);
    expect(find.text('The Lighthouse Garden'), findsOneWidget);
    expect(find.text('My offline downloads'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(7));
  });

  testWidgets('Reading Hub category chips filter the booklet shelf', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReadingHubScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'History'));
    await tester.pumpAndSettle();
    expect(find.text('History: Reading the Past'), findsOneWidget);
    expect(find.text('The Lighthouse Garden'), findsNothing);
  });
}
