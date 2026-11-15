import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/recycle_bin_service.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});
  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  String _query = '';

  Future<bool> _confirm(String title, String message, {String action = 'Continue'}) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
          ],
        ),
      ) == true;

  Future<void> _restore(QueryDocumentSnapshot<Map<String, dynamic>> item, String uid) async {
    try {
      await SkyNestRecycleBinService.restore(ownerId: uid, item: item);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record restored successfully.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not restore record: $error')));
    }
  }

  Future<void> _delete(QueryDocumentSnapshot<Map<String, dynamic>> item, String uid) async {
    if (!await _confirm('Delete permanently?', 'This record will be permanently removed and cannot be restored.', action: 'Delete permanently')) return;
    try {
      await SkyNestRecycleBinService.deletePermanently(ownerId: uid, item: item);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete record: $error')));
    }
  }

  Future<void> _empty(List<QueryDocumentSnapshot<Map<String, dynamic>>> items, String uid) async {
    if (items.isEmpty || !await _confirm('Empty Recycle Bin?', 'Permanently delete all ${items.length} records? This cannot be undone.', action: 'Empty Recycle Bin')) return;
    try {
      await SkyNestRecycleBinService.empty(ownerId: uid, items: items);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not empty Recycle Bin: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in to view Recycle Bin.')));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('recycleBin').where('ownerId', isEqualTo: uid).snapshots(),
            builder: (context, snapshot) => IconButton(
              tooltip: 'Empty Recycle Bin',
              onPressed: snapshot.hasData && snapshot.data!.docs.isNotEmpty
                ? () => _empty(snapshot.data!.docs, uid)
                : null,
              icon: const Icon(Icons.delete_forever_outlined),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('recycleBin').where('ownerId', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Recycle Bin could not load. Check your connection and permissions.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final query = _query.trim().toLowerCase();
            return query.isEmpty ||
              (data['title']?.toString().toLowerCase().contains(query) ?? false) ||
              (data['recordType']?.toString().toLowerCase().contains(query) ?? false);
          }).toList()
            ..sort((a, b) {
              final at = (a.data()['deletedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              final bt = (b.data()['deletedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              return bt.compareTo(at);
            });
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search deleted records',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(child: docs.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_sweep_outlined, size: 48),
                  SizedBox(height: 10),
                  Text('Your Recycle Bin is empty.'),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = docs[index];
                    final data = item.data();
                    final deleted = (data['deletedAt'] as Timestamp?)?.toDate();
                    final date = deleted == null ? 'Recently deleted' : DateFormat('dd MMM yyyy · hh:mm a').format(deleted);
                    return Card(child: ListTile(
                      leading: CircleAvatar(child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error)),
                      title: Text(data['title']?.toString() ?? 'Deleted record'),
                      subtitle: Text('${data['recordType'] ?? 'Record'} · Deleted $date'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'restore') _restore(item, uid);
                          if (action == 'delete') _delete(item, uid);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'restore', child: Text('Restore')),
                          PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
                        ],
                      ),
                    ));
                  },
                )),
          ]);
        },
      ),
    );
  }
}
