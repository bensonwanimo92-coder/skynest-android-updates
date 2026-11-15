import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/control_centre/backup_export_centre.dart';

void main() {
  test('backup serializer converts Firestore values into portable JSON values', () {
    final normalized = SkyNestBackupSerializer.normalize({
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15, 8, 30)),
      'location': const GeoPoint(-1.28, 36.82),
      'nested': {'values': [1, true, 'ok']},
    }) as Map<String, dynamic>;

    expect(normalized['createdAt'], '2026-11-15T08:30:00.000Z');
    expect(normalized['location'], {'latitude': -1.28, 'longitude': 36.82});
    expect(normalized['nested'], {'values': [1, true, 'ok']});
  });

  test('backup encoder produces valid readable JSON', () {
    final encoded = SkyNestBackupSerializer.encode({
      'format': 'skynest-backup',
      'records': [{'id': 'house-1', 'data': {'houseNo': 'A1'}}],
    });

    expect(encoded, contains('\n'));
    expect(encoded, contains('"format": "skynest-backup"'));
    expect(() => jsonDecode(encoded), returnsNormally);
  });
}
