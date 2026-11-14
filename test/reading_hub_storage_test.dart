import 'dart:io';
import 'dart:typed_data';

import 'package:chuka/reading/reading_hub_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved PDFs persist and only PDF files appear in the offline shelf', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-storage-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final storage = ReadingHubStorage(directoryProvider: () async => root);
    final pdfBytes = Uint8List.fromList('%PDF-1.4\nSkyNest offline booklet\n'.codeUnits);

    final saved = await storage.savePdf('The Lighthouse Garden', pdfBytes);
    expect(saved.uri.pathSegments.last, 'the_lighthouse_garden.pdf');
    expect(await saved.readAsBytes(), pdfBytes);

    await File('${root.path}${Platform.pathSeparator}notes.txt')
        .writeAsString('This is not a PDF.');
    final offlineFiles = await storage.listPdfs();

    expect(
      offlineFiles.map((file) => file.uri.pathSegments.last).toList(),
      <String>['the_lighthouse_garden.pdf'],
    );
  });

  test('storage creates a missing app-private folder', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-root-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final target = Directory('${root.path}${Platform.pathSeparator}SkyNest Reading');
    final storage = ReadingHubStorage(directoryProvider: () async => target);

    final saved = await storage.savePdf(
      'history notes',
      Uint8List.fromList('%PDF-test'.codeUnits),
    );

    expect(await target.exists(), isTrue);
    expect(await saved.exists(), isTrue);
  });

  test('storage rejects an empty file name', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-name-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = ReadingHubStorage(directoryProvider: () async => root);

    await expectLater(
      storage.savePdf('   ', Uint8List.fromList(<int>[37, 80, 68, 70])),
      throwsArgumentError,
    );
  });
}
