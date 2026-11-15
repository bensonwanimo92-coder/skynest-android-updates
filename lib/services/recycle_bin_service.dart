import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// Audit entries are best-effort: a logging outage must never undo a
  /// successful user-requested recycle-bin operation.
  static Future<void> _recordAuditEvent(String ownerId, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final db = FirebaseFirestore.instance;
      final profile = await db.collection('users').doc(user.uid).get();
      final profileData = profile.data() ?? <String, dynamic>{};
      await db.collection('activityLogs').add({
        'landlordId': ownerId,
        'actorId': user.uid,
        'actorName': profileData['displayName'] ?? user.displayName ?? 'Account',
        'actorRole': profileData['role'] ?? 'unknown',
        'action': action,
        'isSuspicious': action.toLowerCase().contains('permanently deleted') || action.toLowerCase().contains('emptied'),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Keep the primary operation successful even if audit logging is unavailable.
    }
  }
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
      final count = docs.skip(start).take(200).where((doc) => doc.exists && doc.data() != null).length;
      if (count > 0) await _recordAuditEvent(ownerId, 'Moved $count $recordType record(s) to Recycle Bin');
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
    await _recordAuditEvent(ownerId, 'Restored ' + (data['recordType']?.toString() ?? 'record') + ': ' + (data['title']?.toString() ?? originalId));
  }

  static Future<void> deletePermanently({
    required String ownerId,
    required DocumentSnapshot<Map<String, dynamic>> item,
  }) async {
    if (item.data()?['ownerId'] != ownerId) {
      throw StateError('This Recycle Bin item does not belong to your account.');
    }
    await item.reference.delete();
    final data = item.data() ?? <String, dynamic>{};
    await _recordAuditEvent(ownerId, 'Permanently deleted ' + (data['recordType']?.toString() ?? 'record') + ': ' + (data['title']?.toString() ?? item.id));
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
    if (items.isNotEmpty) await _recordAuditEvent(ownerId, 'Emptied Recycle Bin: permanently deleted ' + items.length.toString() + ' record(s)');
  }
}
