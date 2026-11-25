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
    // Keep directory preparation asynchronous so shelf refreshes do not block
    // the UI thread on filesystem metadata or directory creation.
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<List<File>> listPdfs() async {
    final root = await directory();
    final entities = await root.list(followLinks: false).toList();
    final candidates = entities
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.pdf'))
        .toList();

    // A .pdf extension alone is not enough: legacy, externally copied or
    // interrupted files may be malformed. Verify the signature asynchronously
    // before presenting an entry, and tolerate files disappearing mid-refresh.
    final entries = <(File, DateTime)>[];
    for (final file in candidates) {
      try {
        if (!await _hasPdfFileHeader(file)) continue;
        entries.add((file, await file.lastModified()));
      } catch (_) {
        // Skip an entry that became unreadable or was removed during listing.
      }
    }
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    return entries.map((entry) => entry.$1).toList();
  }

  Future<bool> _hasPdfFileHeader(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final header = await handle.read(8);
      return _hasPdfHeader(Uint8List.fromList(header));
    } finally {
      if (handle != null) await handle.close();
    }
  }

  bool _hasPdfHeader(Uint8List bytes) {
    // SkyNest creates these PDFs locally. Generated PDF files begin with the
    // five-byte "%PDF-" signature; reject empty or unrelated data before it
    // can be shown as a downloadable booklet.
    const header = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
    if (bytes.length < 8) return false;
    for (var index = 0; index < header.length; index++) {
      if (bytes[index] != header[index]) return false;
    }
    return true;
  }

  Future<File> savePdf(String name, Uint8List bytes) async {
    final safeName = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (safeName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A valid PDF file name is required.');
    }
    if (!_hasPdfHeader(bytes)) {
      throw FormatException('Only valid PDF content can be saved to the offline shelf.');
    }

    final root = await directory();
    final file = File(
      '${root.path}${Platform.pathSeparator}$safeName.pdf',
    );
    // Write beside the destination, flush the complete contents, then rename
    // into place. A process interruption cannot leave a truncated .pdf entry
    // in the offline shelf.
    final temporary = File(
      '${root.path}${Platform.pathSeparator}.$safeName.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      return await temporary.rename(file.path);
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }
}
