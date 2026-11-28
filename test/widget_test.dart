import 'dart:io';

import 'package:chuka/main.dart';
import 'package:chuka/reading/reading_hub.dart';
import 'package:chuka/reading/reading_hub_storage.dart';
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

  Widget readingHub({List<File> savedFiles = const <File>[], int? previewFileSize}) => MaterialApp(
    home: ReadingHubScreen(storage: _FakeReadingHubStorage(savedFiles, previewFileSize: previewFileSize)),
  );

  Future<void> pumpReadingHubAndWaitForShelf(WidgetTester tester, {List<File> savedFiles = const <File>[], int? previewFileSize}) async {
    // UI-state tests use a deterministic storage fake. Real filesystem behavior,
    // ordering, PDF validation and persistence are covered by storage tests.
    await tester.pumpWidget(readingHub(savedFiles: savedFiles, previewFileSize: previewFileSize));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

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
    await pumpReadingHubAndWaitForShelf(tester);
    expect(find.text('Reading & Media Hub'), findsOneWidget);

    // The offline shelf is intentionally above the catalogue and visible
    // without navigating to a separate downloads page.
    expect(find.text('My offline downloads'), findsOneWidget);
    expect(find.text('No offline booklets yet'), findsOneWidget);
  });

  testWidgets('Reading Hub lists a saved booklet for offline reading', (tester) async {
    final savedFile = File('${offlineDirectory.path}${Platform.pathSeparator}the_lighthouse_garden.pdf');
    savedFile.writeAsBytesSync(<int>[37, 80, 68, 70, 45, 49, 46, 55]);
    await pumpReadingHubAndWaitForShelf(tester, savedFiles: <File>[savedFile]);

    final savedBooklet = find.widgetWithText(ListTile, 'The Lighthouse Garden');
    expect(savedBooklet, findsOneWidget);
    expect(find.text('Saved on this device · PDF'), findsOneWidget);
  });

  testWidgets('Reading Hub refuses to preview offline PDFs larger than 32 MB', (tester) async {
    // A large logical size avoids creating a 32 MB fixture or depending on
    // filesystem allocation behavior on hosted runners. A tall viewport keeps
    // the shelf tile visible without scroll-loop timing.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = File('${offlineDirectory.path}${Platform.pathSeparator}large_booklet.pdf');
    file.writeAsBytesSync(<int>[37, 80, 68, 70, 45, 49, 46, 55]);

    await pumpReadingHubAndWaitForShelf(tester, savedFiles: <File>[file], previewFileSize: 32 * 1024 * 1024 + 1);
    final tile = find.widgetWithText(ListTile, 'large booklet');
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text('This PDF is larger than 32 MB and cannot be previewed in the offline shelf.'),
      findsOneWidget,
    );
  });

  testWidgets('Reading Hub category chips reveal the matching booklet shelf', (tester) async {
    await pumpReadingHubAndWaitForShelf(tester);

    final historyChip = find.widgetWithText(ChoiceChip, 'History');
    await tester.scrollUntilVisible(historyChip, 240, scrollable: find.byType(Scrollable).first);
    await tester.tap(historyChip);
    await tester.pump(const Duration(milliseconds: 200));

    final historyBooklet = find.text('History: Reading the Past');
    await tester.scrollUntilVisible(historyBooklet, 240, scrollable: find.byType(Scrollable).first);
    expect(historyBooklet, findsOneWidget);
  });
}

class _FakeReadingHubStorage extends ReadingHubStorage {
  _FakeReadingHubStorage(this.files, {this.previewFileSize}) : super();

  final List<File> files;
  final int? previewFileSize;

  @override
  Future<List<File>> listPdfs() async => files;

  @override
  Future<int> fileSize(File file) async => previewFileSize ?? file.length();
}
