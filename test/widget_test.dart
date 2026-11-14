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

    // The offline shelf is deliberately placed before the catalogue so
    // previously saved PDFs are the first useful content after the intro.
    await tester.scrollUntilVisible(find.text('My offline downloads'), 240);
    await tester.scrollUntilVisible(find.text('No offline booklets yet'), 240);
    expect(find.text('No offline booklets yet'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('The Lighthouse Garden'), 240);
    expect(find.text('The Lighthouse Garden'), findsOneWidget);
  });

  testWidgets('Reading Hub lists a saved booklet for offline reading', (tester) async {
    File('${offlineDirectory.path}${Platform.pathSeparator}the_lighthouse_garden.pdf')
        .writeAsBytesSync(<int>[37, 80, 68, 70]);
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));

    final savedBooklet = find.widgetWithText(ListTile, 'The Lighthouse Garden');
    await tester.scrollUntilVisible(savedBooklet, 240);
    expect(savedBooklet, findsOneWidget);
    expect(find.text('Saved on this device · PDF'), findsOneWidget);
  });

  testWidgets('Downloading an original booklet creates a valid offline PDF', (tester) async {
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));

    final downloadButton = find.widgetWithText(FilledButton, 'Download').first;
    await tester.scrollUntilVisible(downloadButton, 300);
    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    final savedFile = File('${offlineDirectory.path}${Platform.pathSeparator}the_lighthouse_garden.pdf');
    expect(await savedFile.exists(), isTrue);
    final bytes = await savedFile.readAsBytes();
    expect(bytes.length, greaterThan(100));
    expect(bytes.take(4).toList(), '%PDF'.codeUnits);
  });

  testWidgets('Reading Hub category chips reveal the matching booklet shelf', (tester) async {
    await tester.pumpWidget(readingHub());
    await tester.pump(const Duration(milliseconds: 400));

    final historyChip = find.widgetWithText(ChoiceChip, 'History');
    await tester.scrollUntilVisible(historyChip, 240);
    await tester.tap(historyChip);
    await tester.pump(const Duration(milliseconds: 200));

    final historyBooklet = find.text('History: Reading the Past');
    await tester.scrollUntilVisible(historyBooklet, 240);
    expect(historyBooklet, findsOneWidget);
  });
}
