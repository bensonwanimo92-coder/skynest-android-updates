import 'dart:async';

import 'package:chuka/reading/bounded_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects streamed chunks in order', () async {
    final bytes = await readBoundedBytes(
      Stream<List<int>>.fromIterable(<List<int>>[
        <int>[1, 2],
        <int>[3],
        <int>[4, 5],
      ]),
      maxBytes: 5,
    );

    expect(bytes, <int>[1, 2, 3, 4, 5]);
  });

  test('accepts a response exactly at the limit', () async {
    final bytes = await readBoundedBytes(
      Stream<List<int>>.fromIterable(<List<int>>[<int>[1, 2, 3]]),
      maxBytes: 3,
    );

    expect(bytes, <int>[1, 2, 3]);
  });

  test('rejects a response that exceeds the limit', () async {
    await expectLater(
      readBoundedBytes(
        Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ]),
        maxBytes: 3,
      ),
      throwsA(isA<ResponseSizeLimitException>()),
    );
  });

  test('requires a positive byte limit', () async {
    await expectLater(
      readBoundedBytes(Stream<List<int>>.empty(), maxBytes: 0),
      throwsArgumentError,
    );
  });
}
