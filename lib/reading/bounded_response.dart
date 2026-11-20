import 'dart:async';
import 'dart:typed_data';

class ResponseSizeLimitException implements Exception {
  const ResponseSizeLimitException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Response exceeded the $maxBytes byte limit.';
}

/// Collects a streamed response without allowing it to exceed [maxBytes].
/// The stream is cancelled as soon as an oversized chunk is detected.
Future<Uint8List> readBoundedBytes(
  Stream<List<int>> stream, {
  required int maxBytes,
}) async {
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }

  final builder = BytesBuilder(copy: false);
  var totalBytes = 0;
  await for (final chunk in stream) {
    if (chunk.length > maxBytes - totalBytes) {
      throw ResponseSizeLimitException(maxBytes);
    }
    totalBytes += chunk.length;
    builder.add(chunk);
  }
  return builder.takeBytes();
}
