import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

class SkyNestBackupSerializer {
  static Object? normalize(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is GeoPoint) return {'latitude': value.latitude, 'longitude': value.longitude};
    if (value is DocumentReference) return {'documentPath': value.path};
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), normalize(item)));
    }
    if (value is Iterable) return value.map(normalize).toList();
    if (value == null || value is String || value is num || value is bool) return value;
    return value.toString();
  }

  static String encode(Map<String, dynamic> value) =>
      const JsonEncoder.withIndent('  ').convert(normalize(value));
}

class BackupExportCentreScreen extends StatefulWidget {
  const BackupExportCentreScreen({super.key});

  @override
  State<BackupExportCentreScreen> createState() => _BackupExportCentreScreenState();
}

class _BackupExportCentreScreenState extends State<BackupExportCentreScreen> {
  bool _exporting = false;
  String? _lastResult;

  static const _collections = <List<String>>[
    ['houses', 'createdBy'],
    ['tenants', 'landlordId'],
    ['payments', 'createdBy'],
    ['paymentSubmissions', 'landlordId'],
    ['houseRequests', 'landlordId'],
    ['invitations', 'landlordId'],
    ['complaints', 'landlordId'],
    ['notices', 'landlordId'],
    ['pamphlets', 'landlordId'],
    ['meters', 'landlordId'],
    ['electricityAllocations', 'landlordId'],
    ['calendarEvents', 'landlordId'],
    ['plans', 'createdBy'],
    ['automations', 'ownerId'],
    ['activityLogs', 'landlordId'],
    ['groups', 'landlordId'],
  ];

  Future<void> _createBackup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _exporting) return;
    setState(() { _exporting = true; _lastResult = null; });
    try {
      final db = FirebaseFirestore.instance;
      final profile = await db.collection('users').doc(user.uid).get();
      if (profile.data()?['role'] != 'landlord') {
        throw StateError('The full property backup is currently available to Landlord accounts.');
      }

      final snapshots = await Future.wait(_collections.map((spec) =>
        db.collection(spec[0]).where(spec[1], isEqualTo: user.uid).limit(5000).get(),
      ));
      final exported = <String, dynamic>{};
      var totalRecords = 0;
      var truncatedCollections = 0;

      for (var i = 0; i < _collections.length; i++) {
        final name = _collections[i][0];
        final snapshot = snapshots[i];
        totalRecords += snapshot.size;
        if (snapshot.size == 5000) truncatedCollections++;
        exported[name] = {
          'count': snapshot.size,
          'limitReached': snapshot.size == 5000,
          'records': snapshot.docs.map((doc) => {
            'id': doc.id,
            'data': SkyNestBackupSerializer.normalize(doc.data()),
          }).toList(),
        };
      }

      final now = DateTime.now().toUtc();
      final backup = <String, dynamic>{
        'format': 'skynest-backup',
        'schemaVersion': 1,
        'applicationId': 'com.hello22_.chuka',
        'ownerId': user.uid,
        'exportedAt': now.toIso8601String(),
        'profile': SkyNestBackupSerializer.normalize(profile.data() ?? <String, dynamic>{}),
        'collections': exported,
        'summary': {
          'collectionCount': _collections.length,
          'recordCount': totalRecords,
          'collectionsAtLimit': truncatedCollections,
          'note': 'Private keys, device push tokens and direct-message contents are intentionally excluded.',
        },
      };
      final bytes = Uint8List.fromList(utf8.encode(SkyNestBackupSerializer.encode(backup)));
      final stamp = now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      await FileSaver.instance.saveToDownloads(
        name: 'skynest-backup-$stamp',
        bytes: bytes,
        fileExtension: 'json',
        mimeType: MimeType.custom,
        customMimeType: 'application/json',
        subfolder: 'SkyNest Backups',
      );
      if (!mounted) return;
      setState(() {
        _lastResult = truncatedCollections == 0
          ? 'Backup saved: $totalRecords records across ${_collections.length} collections.'
          : 'Backup saved, but $truncatedCollections collection(s) reached the 5,000-record export limit.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _lastResult = 'Backup could not be created: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in to create a backup.')));
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.cloud_download_outlined, color: colors.primary, size: 27),
                ),
                const SizedBox(height: 14),
                Text('Your property data, in your hands',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Text('Create a portable JSON backup of records owned by your Landlord account. The file is saved in Downloads / SkyNest Backups.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _exporting ? null : _createBackup,
                  icon: _exporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.backup_outlined),
                  label: Text(_exporting ? 'Preparing backup…' : 'Create full JSON backup'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
                if (_lastResult != null) ...[
                  const SizedBox(height: 12),
                  Text(_lastResult!, style: TextStyle(
                    color: _lastResult!.startsWith('Backup saved') ? colors.primary : colors.error,
                    fontWeight: FontWeight.w600,
                  )),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Text('INCLUDED DATA', style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(child: Column(children: [
            for (var i = 0; i < _collections.length; i++) ...[
              ListTile(
                dense: true,
                leading: Icon(Icons.check_circle_outline, color: colors.primary, size: 19),
                title: Text(_collections[i][0]),
              ),
              if (i != _collections.length - 1) const Divider(height: 1, indent: 52),
            ],
          ])),
          const SizedBox(height: 12),
          Text('Security and completeness',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text('The export is restricted to records belonging to your signed-in Landlord account. Device tokens, private security keys and direct-message contents are excluded. Each collection is capped at 5,000 records; the backup reports if a cap is reached. This creates a backup file but does not automatically restore or upload it to cloud storage.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.45)),
        ],
      ),
    );
  }
}
