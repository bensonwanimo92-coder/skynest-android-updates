import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// App-private storage for original SkyNest reading PDFs.
///
/// Inject [directoryProvider] in tests so storage can be verified without
/// depending on Android's application documents directory.
class ReadingHubStorage {
  const ReadingHubStorage({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  Future<Directory> directory() async {
    final provider = directoryProvider;
    final target = provider != null
        ? await provider()
        : Directory(
            '${(await getApplicationDocumentsDirectory()).path}'
            '${Platform.pathSeparator}SkyNest Reading',
          );
    // Directory setup and listing are deliberately synchronous: the app
    // stores only a small number of PDFs, and this keeps the shelf refresh
    // deterministic while the actual PDF write remains asynchronous.
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    return target;
  }

  Future<List<File>> listPdfs() async {
    final root = await directory();
    final files = root
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.pdf'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<File> savePdf(String name, Uint8List bytes) async {
    final safeName = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (safeName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A valid PDF file name is required.');
    }

    final root = await directory();
    final file = File(
      '${root.path}${Platform.pathSeparator}$safeName.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
