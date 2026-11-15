import 'dart:convert';
import 'dart:io';

/// Read-only browser for Internet Archive audio carrying a reuse-friendly
/// Creative Commons Attribution/Attribution-ShareAlike 4.0 or public-domain
/// declaration. The app displays the item and licence details before use.
class InternetArchiveAudioTrack {
  const InternetArchiveAudioTrack({
    required this.identifier,
    required this.title,
    required this.creator,
    required this.licenseUrl,
    required this.fileName,
    required this.downloadUrl,
    this.fileSizeBytes = 0,
    this.bitrateKbps = 0,
    this.format = '',
  });

  final String identifier;
  final String title;
  final String creator;
  final String licenseUrl;
  final String fileName;
  final Uri downloadUrl;
  final int fileSizeBytes;
  final int bitrateKbps;
  final String format;

  String get qualityLabel {
    if (bitrateKbps > 0) return '${bitrateKbps} kbps';
    if (format.toLowerCase() == 'flac' || format.toLowerCase() == 'wav') {
      return 'Lossless ${format.toUpperCase()}';
    }
    return format.isEmpty ? 'Original quality' : format.toUpperCase();
  }

  String get fileSizeLabel {
    if (fileSizeBytes <= 0) return 'Size not supplied';
    if (fileSizeBytes >= 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (fileSizeBytes >= 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  String get detailsUrl => 'https://archive.org/details/$identifier';

  String get licenseLabel {
    final value = licenseUrl.toLowerCase();
    if (value.contains('publicdomain/zero') || value.contains('publicdomain/mark')) {
      return 'Public domain / CC0';
    }
    if (value.contains('/by-sa/4.0')) return 'Creative Commons BY-SA 4.0';
    return 'Creative Commons BY 4.0';
  }
}

/// Uses Internet Archive's public Advanced Search and Metadata read APIs.
/// It never scrapes provider pages or attempts to bypass DRM/access controls.
class InternetArchiveAudioService {
  Future<List<InternetArchiveAudioTrack>> search(String query, {int limit = 12}) async {
    final term = query.trim();
    final licenceQuery =
        '(licenseurl:http*publicdomain* OR licenseurl:http*by/4.0* OR licenseurl:http*by-sa/4.0*)';
    final safeTerm = term.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final searchQuery = term.isEmpty
        ? 'mediatype:audio AND $licenceQuery'
        : 'mediatype:audio AND $licenceQuery AND (title:"$safeTerm" OR creator:"$safeTerm" OR subject:"$safeTerm")';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': searchQuery,
      'fl[]': 'identifier,title,creator,licenseurl',
      'rows': limit.toString(),
      'page': '1',
      'output': 'json',
      'sort[]': 'downloads desc',
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final searchData = await _getJson(client, uri);
      final response = searchData['response'] as Map<String, dynamic>?;
      final docs = response?['docs'] as List<dynamic>? ?? const [];
      final tracks = await Future.wait(docs.map((entry) async {
        if (entry is! Map<String, dynamic>) return null;
        return _readTrack(client, entry);
      }));
      return tracks.whereType<InternetArchiveAudioTrack>().toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<InternetArchiveAudioTrack?> _readTrack(
    HttpClient client,
    Map<String, dynamic> document,
  ) async {
    final identifier = document['identifier']?.toString() ?? '';
    if (identifier.isEmpty) return null;
    try {
      final metadataData = await _getJson(
        client,
        Uri.https('archive.org', '/metadata/$identifier'),
      );
      final metadata = metadataData['metadata'] as Map<String, dynamic>? ?? {};
      final license = (metadata['licenseurl'] ?? document['licenseurl'])?.toString() ?? '';
      if (!_isReusableLicence(license)) return null;
      final files = metadataData['files'] as List<dynamic>? ?? const [];
      final candidates = files.whereType<Map<String, dynamic>>().where((file) {
        final name = file['name']?.toString().toLowerCase() ?? '';
        final format = file['format']?.toString().toLowerCase() ?? '';
        return !name.contains('/') &&
            (name.endsWith('.mp3') || name.endsWith('.m4a') ||
             name.endsWith('.ogg') || name.endsWith('.flac') || name.endsWith('.wav')) &&
            !format.contains('metadata');
      }).toList();
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) {
        final bitrateOrder = _number(b['bitrate']).compareTo(_number(a['bitrate']));
        if (bitrateOrder != 0) return bitrateOrder;
        int qualityRank(Map<String, dynamic> file) {
          final name = file['name']?.toString().toLowerCase() ?? '';
          if (name.endsWith('.flac') || name.endsWith('.wav')) return 0;
          if (name.endsWith('.m4a')) return 1;
          if (name.endsWith('.ogg')) return 2;
          return 3;
        }
        final formatOrder = qualityRank(a).compareTo(qualityRank(b));
        if (formatOrder != 0) return formatOrder;
        return _number(b['size']).compareTo(_number(a['size']));
      });
      final fileName = candidates.first['name']?.toString() ?? '';
      if (fileName.isEmpty) return null;
      return InternetArchiveAudioTrack(
        identifier: identifier,
        title: (metadata['title'] ?? document['title'] ?? fileName).toString(),
        creator: (metadata['creator'] ?? document['creator'] ?? 'Unknown creator').toString(),
        licenseUrl: license,
        fileName: fileName,
        downloadUrl: Uri.parse(
          'https://archive.org/download/$identifier/${Uri.encodeComponent(fileName)}',
        ),
        fileSizeBytes: _number(candidates.first['size']),
        bitrateKbps: _number(candidates.first['bitrate']),
        format: fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '',
      );
    } catch (_) {
      // A malformed, unavailable, or unlicensed item is skipped, not exposed.
      return null;
    }
  }

  int _number(dynamic value) {
    final match = RegExp(r'\\d+').firstMatch(value?.toString() ?? '');
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  bool _isReusableLicence(String value) {
    final licence = value.toLowerCase();
    if (licence.contains('publicdomain/zero') || licence.contains('publicdomain/mark')) {
      return true;
    }
    if (licence.contains('/licenses/by/4.0')) return true;
    if (licence.contains('/licenses/by-sa/4.0')) return true;
    return false;
  }

  Future<Map<String, dynamic>> _getJson(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Internet Archive returned HTTP ${response.statusCode}.', uri: uri);
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Internet Archive returned an invalid response.');
    }
    return decoded;
  }
}
