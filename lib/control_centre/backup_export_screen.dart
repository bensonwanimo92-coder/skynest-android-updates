import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key});

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  bool _exporting = false;

  dynamic _jsonSafe(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is GeoPoint) return {'latitude': value.latitude, 'longitude': value.longitude};
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _jsonSafe(item)));
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value;
  }

  Future<void> _export() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in before exporting your data.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final db = FirebaseFirestore.instance;
      final specifications = <(String, String)>[
        ('houses', 'createdBy'),
        ('tenants', 'landlordId'),
        ('payments', 'createdBy'),
        ('plans', 'createdBy'),
        ('calendarEvents', 'landlordId'),
        ('pamphlets', 'landlordId'),
        ('activityLogs', 'landlordId'),
        ('automations', 'ownerId'),
        ('invitations', 'landlordId'),
        ('complaints', 'landlordId'),
        ('meters', 'landlordId'),
        ('electricityAllocations', 'landlordId'),
        ('paymentConfirmations', 'landlordId'),
        ('groups', 'landlordId'),
        ('paymentSubmissions', 'landlordId'),
        ('savedCalculations', 'createdBy'),
        ('notices', 'landlordId'),
      ];
      final exported = <String, dynamic>{};
      for (final spec in specifications) {
        final snapshot = await db.collection(spec.$1)
          .where(spec.$2, isEqualTo: user.uid)
          .get();
        exported[spec.$1] = snapshot.docs.map((doc) => {
          'id': doc.id,
          ..._jsonSafe(doc.data() as Map<String, dynamic>),
        }).toList();
      }

      final profile = await db.collection('users').doc(user.uid).get();
      final payload = <String, dynamic>{
        'format': 'skynest-json-backup-v1',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'accountId': user.uid,
        'profile': profile.exists ? _jsonSafe(profile.data()) : null,
        'collections': exported,
        'limitations': [
          'This export contains structured Firestore records owned by this Landlord account.',
          'Uploaded photos, PDFs, voice notes, encrypted chat messages and device tokens are not included.',
          'This JSON file is an export copy; it does not automatically restore or overwrite live records.',
        ],
      };
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your SkyNest backup',
        fileName: 'skynest-backup-$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup export cancelled.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup saved: $path')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed. No partial file was offered: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & export')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .55)!],
              ),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_download_outlined, color: Colors.white, size: 32),
              SizedBox(height: 12),
              Text('Keep a copy of your records',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Export your SkyNest business records into a portable JSON file you can store securely.',
                style: TextStyle(color: Colors.white, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('Included in this export', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _IncludedRow('Properties, tenants and payment records'),
              _IncludedRow('Plans, calendar events and pamphlets'),
              _IncludedRow('Activity history and scheduled reminders'),
              _IncludedRow('Invitations, complaints and utilities'),
              _IncludedRow('Groups, payment submissions and reports data'),
            ]),
          )),
          const SizedBox(height: 12),
          Card(
            color: colors.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Important limitations', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Photos, uploaded documents, voice notes, encrypted chat messages and device tokens are not included. Export does not automatically restore or overwrite live records. Keep the backup in a private, secure location.'),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_rounded),
            label: Text(_exporting ? 'Preparing your backup…' : 'Export my SkyNest data'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          ),
        ],
      ),
    );
  }
}

class _IncludedRow extends StatelessWidget {
  const _IncludedRow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(Icons.check_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 9),
      Expanded(child: Text(label)),
    ]),
  );
}
