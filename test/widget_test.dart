import 'dart:io';

import 'package:chuka/main.dart';
import 'package:chuka/reading/reading_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp('skynest-reading-hub-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProviderChannel,
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return documentsDirectory.path;
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _pathProviderChannel,
      null,
    );
    if (await documentsDirectory.exists()) await documentsDirectory.delete(recursive: true);
  });

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
    await tester.pumpWidget(const MaterialApp(home: ReadingHubScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Reading & Media Hub'), findsOneWidget);
    expect(find.text('The Lighthouse Garden'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('My offline downloads'), 400);
    await tester.pumpAndSettle();
    expect(find.text('My offline downloads'), findsOneWidget);
    expect(find.text('No offline booklets yet'), findsOneWidget);
  });

  testWidgets('Reading Hub lists a previously saved booklet for offline reading', (tester) async {
    final offlineDirectory = Directory('${documentsDirectory.path}${Platform.pathSeparator}SkyNest Reading');
    await offlineDirectory.create(recursive: true);
    await File('${offlineDirectory.path}${Platform.pathSeparator}the_lighthouse_garden.pdf').writeAsBytes(<int>[37, 80, 68, 70]);
    await tester.pumpWidget(const MaterialApp(home: ReadingHubScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('My offline downloads'), 400);
    await tester.pumpAndSettle();
    expect(find.text('The Lighthouse Garden'), findsOneWidget);
    expect(find.text('Saved on this device · PDF'), findsOneWidget);
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
