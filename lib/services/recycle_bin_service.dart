import 'package:cloud_firestore/cloud_firestore.dart';

class SkyNestRecycleBinService {
  SkyNestRecycleBinService._();

  static const Map<String, String> _ownerFields = {
    'houses': 'createdBy',
    'tenants': 'landlordId',
    'calendarEvents': 'landlordId',
    'plans': 'createdBy',
    'pamphlets': 'landlordId',
  };

  static const Map<String, String> _recordTypes = {
    'houses': 'House',
    'tenants': 'Tenant',
    'calendarEvents': 'Calendar event',
    'plans': 'Plan',
    'pamphlets': 'Pamphlet',
  };

  static String _titleFor(String collectionName, Map<String, dynamic> data) {
    switch (collectionName) {
      case 'houses':
        return 'House ${data['houseNo'] ?? data['name'] ?? ''}'.trim();
      case 'tenants':
        return data['name']?.toString() ?? 'Tenant';
      default:
        return data['title']?.toString() ?? _recordTypes[collectionName] ?? 'Record';
    }
  }

  static Future<void> moveToTrash({
    required String ownerId,
    required String collectionName,
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required String recordType,
  }) => moveManyToTrash(
    ownerId: ownerId,
    collectionName: collectionName,
    docs: [doc],
    recordType: recordType,
  );

  static Future<void> moveManyToTrash({
    required String ownerId,
    required String collectionName,
    required List<DocumentSnapshot<Map<String, dynamic>>> docs,
    required String recordType,
  }) async {
    final ownerField = _ownerFields[collectionName];
    if (ownerField == null) throw ArgumentError.value(collectionName, 'collectionName', 'This record type cannot be moved to Recycle Bin.');
    if (ownerId.isEmpty) throw StateError('A signed-in owner is required.');
    final db = FirebaseFirestore.instance;

    for (var start = 0; start < docs.length; start += 200) {
      final batch = db.batch();
      for (final doc in docs.skip(start).take(200)) {
        final data = doc.data();
        if (!doc.exists || data == null) continue;
        if (doc.reference.parent.id != collectionName || data[ownerField] != ownerId) {
          throw StateError('You can only move records owned by your account to Recycle Bin.');
        }
        final binRef = db.collection('recycleBin').doc();
        batch.set(binRef, {
          'ownerId': ownerId,
          'originalCollection': collectionName,
          'originalId': doc.id,
          'recordType': recordType,
          'title': _titleFor(collectionName, data),
          'originalData': data,
          'deletedAt': FieldValue.serverTimestamp(),
        });
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  static Future<void> restore({
    required String ownerId,
    required DocumentSnapshot<Map<String, dynamic>> item,
  }) async {
    final data = item.data();
    if (!item.exists || data == null || data['ownerId'] != ownerId) {
      throw StateError('This Recycle Bin item does not belong to your account.');
    }
    final collectionName = data['originalCollection']?.toString() ?? '';
    if (!_ownerFields.containsKey(collectionName)) {
      throw StateError('This record type cannot be restored.');
    }
    final originalId = data['originalId']?.toString() ?? '';
    final originalData = data['originalData'];
    if (originalId.isEmpty || originalData is! Map) {
      throw StateError('The backup data for this record is incomplete.');
    }
    final originalRef = FirebaseFirestore.instance.collection(collectionName).doc(originalId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final binSnapshot = await transaction.get(item.reference);
      if (!binSnapshot.exists || binSnapshot.data()?['ownerId'] != ownerId) {
        throw StateError('This Recycle Bin item no longer exists.');
      }
      final originalSnapshot = await transaction.get(originalRef);
      if (originalSnapshot.exists) {
        throw StateError('A record with this ID already exists. Nothing was overwritten.');
      }
      transaction.set(originalRef, Map<String, dynamic>.from(originalData));
      transaction.delete(item.reference);
    });
  }

  static Future<void> deletePermanently({
    required String ownerId,
    required DocumentSnapshot<Map<String, dynamic>> item,
  }) async {
    if (item.data()?['ownerId'] != ownerId) {
      throw StateError('This Recycle Bin item does not belong to your account.');
    }
    await item.reference.delete();
  }

  static Future<void> empty({
    required String ownerId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  }) async {
    for (var start = 0; start < items.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in items.skip(start).take(400)) {
        if (item.data()['ownerId'] != ownerId) {
          throw StateError('The Recycle Bin contains an item that does not belong to your account.');
        }
        batch.delete(item.reference);
      }
      await batch.commit();
    }
  }
}
