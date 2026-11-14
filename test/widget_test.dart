import 'dart:io';

import 'package:chuka/main.dart';
import 'package:chuka/reading/reading_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory documentsDirectory;
  late Directory offlineDirectory;

  setUp(() {
    documentsDirectory = Directory.systemTemp.createTempSync('skynest-reading-hub-');
    offlineDirectory = Directory('${documentsDirectory.path}${Platform.pathSeparator}SkyNest Reading');
    offlineDirectory.createSync(recursive: true);
  });

  tearDown(() {
    if (documentsDirectory.existsSync()) documentsDirectory.deleteSync(recursive: true);
  });

  Widget readingHub() => MaterialApp(
    home: ReadingHubScreen(offlineDirectoryProvider: () async => offlineDirectory),
  );

  testWidgets('SkyNest root widget builds the application shell', (tester) async {
    // Remote photo backdrops are a production enhancement, not a dependency
    // of the application shell. Keep this smoke test fully offline.
    await tester.pumpWidget(const SkynestApp(enableRemoteBackdrops: false));
    await tester.pump();
    expect(find.byType(SkynestApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(StartupGate), findsOneWidget);
  });

  testWidgets('Reading Hub exposes original booklets and an empty offline shelf', (tester) async {
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reading & Media Hub'), findsOneWidget);
    expect(find.text('The Lighthouse Garden'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('My offline downloads'), findsOneWidget);
    expect(find.text('No offline booklets yet'), findsOneWidget);
  });

  testWidgets('Reading Hub lists a saved booklet for offline reading', (tester) async {
    File('${offlineDirectory.path}${Platform.pathSeparator}the_lighthouse_garden.pdf').writeAsBytesSync(<int>[37, 80, 68, 70]);
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(find.byType(ListView).first, const Offset(0, -2200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ListTile, 'The Lighthouse Garden'), findsOneWidget);
    expect(find.text('Saved on this device · PDF'), findsOneWidget);
  });

  testWidgets('Reading Hub category chips filter the booklet shelf', (tester) async {
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, 'History'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('History: Reading the Past'), findsOneWidget);
    expect(find.text('The Lighthouse Garden'), findsNothing);
  });
}
