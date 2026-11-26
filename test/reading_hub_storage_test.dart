import 'dart:io';
import 'dart:typed_data';

import 'package:chuka/reading/reading_hub_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline shelf lists PDFs newest first without including other files', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-order-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final older = File('${root.path}${Platform.pathSeparator}older.pdf');
    final newer = File('${root.path}${Platform.pathSeparator}newer.pdf');
    await older.writeAsBytes(Uint8List.fromList('%PDF-1.4 older'.codeUnits));
    await newer.writeAsBytes(Uint8List.fromList('%PDF-1.7 newer'.codeUnits));
    final olderTime = DateTime.utc(2020, 1, 1);
    final newerTime = DateTime.utc(2021, 1, 1);
    await older.setLastModified(olderTime);
    await newer.setLastModified(newerTime);
    await File('${root.path}${Platform.pathSeparator}notes.txt').writeAsString('not a PDF');

    final storage = ReadingHubStorage(directoryProvider: () async => root);
    final files = await storage.listPdfs();

    expect(files.map((file) => file.uri.pathSegments.last).toList(),
        <String>['newer.pdf', 'older.pdf']);
  });


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

  test('offline shelf skips malformed PDF files and unsupported versions', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-corrupt-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final valid = File('${root.path}${Platform.pathSeparator}valid.pdf');
    final validV2 = File('${root.path}${Platform.pathSeparator}valid_v2.pdf');
    final short = File('${root.path}${Platform.pathSeparator}short.pdf');
    final malformed = File('${root.path}${Platform.pathSeparator}malformed.pdf');
    final invalidVersion = File('${root.path}${Platform.pathSeparator}invalid_version.pdf');
    final unsupportedVersion = File('${root.path}${Platform.pathSeparator}unsupported_version.pdf');
    await valid.writeAsBytes(Uint8List.fromList('%PDF-1.4\\\\nvalid'.codeUnits));
    await validV2.writeAsBytes(Uint8List.fromList('%PDF-2.0\\\\nvalid'.codeUnits));
    await short.writeAsBytes(Uint8List.fromList('%PDF'.codeUnits));
    await malformed.writeAsBytes(Uint8List.fromList('plain text'.codeUnits));
    await invalidVersion.writeAsBytes(Uint8List.fromList('%PDF-1.x'.codeUnits));
    await unsupportedVersion.writeAsBytes(Uint8List.fromList('%PDF-3.0'.codeUnits));

    final storage = ReadingHubStorage(directoryProvider: () async => root);
    final files = await storage.listPdfs();

    expect(files.map((file) => file.uri.pathSegments.last).toSet(),
        <String>{'valid.pdf', 'valid_v2.pdf'});
  });

  test('save rejects malformed or unsupported PDF version headers', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-version-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = ReadingHubStorage(directoryProvider: () async => root);

    await expectLater(
      storage.savePdf('invalid version', Uint8List.fromList('%PDF-1.x'.codeUnits)),
      throwsFormatException,
    );
    await expectLater(
      storage.savePdf('unsupported version', Uint8List.fromList('%PDF-3.0'.codeUnits)),
      throwsFormatException,
    );
    expect(await storage.listPdfs(), isEmpty);
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
      Uint8List.fromList('%PDF-1.4 test'.codeUnits),
    );

    expect(await target.exists(), isTrue);
    expect(await saved.exists(), isTrue);
  });

  test('rejects non-PDF content without creating an offline entry', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-invalid-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = ReadingHubStorage(directoryProvider: () async => root);

    await expectLater(
      storage.savePdf('not a booklet', Uint8List.fromList('not a PDF'.codeUnits)),
      throwsFormatException,
    );

    expect(await storage.listPdfs(), isEmpty);
  });

  test('invalid replacement leaves the previously saved PDF intact', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-replace-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = ReadingHubStorage(directoryProvider: () async => root);
    final original = Uint8List.fromList('%PDF-1.4\noriginal booklet\n'.codeUnits);
    final saved = await storage.savePdf('welcome guide', original);

    await expectLater(
      storage.savePdf('welcome guide', Uint8List.fromList('broken data'.codeUnits)),
      throwsFormatException,
    );

    expect(await saved.readAsBytes(), original);
    expect((await storage.listPdfs()).length, 1);
  });

  test('replacement writes a complete PDF and leaves no temporary files', () async {
    final root = await Directory.systemTemp.createTemp('skynest-reading-atomic-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = ReadingHubStorage(directoryProvider: () async => root);
    final replacement = Uint8List.fromList('%PDF-1.7\nupdated booklet\n'.codeUnits);

    final saved = await storage.savePdf('history notes', replacement);

    expect(await saved.readAsBytes(), replacement);
    expect(
      root.listSync().whereType<File>().where((file) => file.path.endsWith('.part')),
      isEmpty,
    );
    expect((await storage.listPdfs()).length, 1);
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
