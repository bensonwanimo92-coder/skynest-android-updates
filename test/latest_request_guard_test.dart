import 'package:chuka/reading/latest_request_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the newest request can publish a result', () {
    final guard = LatestRequestGuard();
    final first = guard.begin();
    final second = guard.begin();

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
  });

  test('clearing a query invalidates an in-flight request', () {
    final guard = LatestRequestGuard();
    final pending = guard.begin();

    guard.invalidate();

    expect(guard.isCurrent(pending), isFalse);
  });

  test('a new request after invalidation becomes current', () {
    final guard = LatestRequestGuard();
    final pending = guard.begin();
    guard.invalidate();
    final retry = guard.begin();

    expect(guard.isCurrent(pending), isFalse);
    expect(guard.isCurrent(retry), isTrue);
  });
}
