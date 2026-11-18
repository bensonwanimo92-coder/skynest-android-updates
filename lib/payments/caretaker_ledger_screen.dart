import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CaretakerLedgerScreen extends StatelessWidget {
  const CaretakerLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in to view the caretaker ledger.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Caretaker ledger')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('paymentConfirmations')
            .where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Caretaker ledger could not load: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final records = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final ad = a.data()['createdAt'], bd = b.data()['createdAt'];
              final at = ad is Timestamp ? ad.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              final bt = bd is Timestamp ? bd.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });
          final confirmed = records.where((doc) => doc.data()['status'] == 'confirmed_by_caretaker').length;
          final pending = records.length - confirmed;
          if (records.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('Caretaker payment confirmations will appear here when you assign payment submissions for verification.',
                textAlign: TextAlign.center),
            ));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: _summary('Confirmed', confirmed, Colors.green)),
                  Expanded(child: _summary('Pending', pending, Colors.orange)),
                  Expanded(child: _summary('Total', records.length, Theme.of(context).colorScheme.primary)),
                ]),
              )),
              const SizedBox(height: 12),
              ...records.map((doc) {
                final data = doc.data();
                final isConfirmed = data['status'] == 'confirmed_by_caretaker';
                final created = data['createdAt'];
                final date = created is Timestamp ? DateFormat('dd MMM yyyy · HH:mm').format(created.toDate()) : 'Date not recorded';
                return Card(
                  margin: const EdgeInsets.only(bottom: 9),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (isConfirmed ? Colors.green : Colors.orange).withOpacity(.13),
                      child: Icon(isConfirmed ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                        color: isConfirmed ? Colors.green : Colors.orange),
                    ),
                    title: Text(data['tenantName']?.toString() ?? 'Tenant',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('House ${data['houseNo'] ?? '—'} · ${data['status'] ?? 'pending'}\n$date'),
                    isThreeLine: true,
                    trailing: Text(isConfirmed ? 'CONFIRMED' : 'PENDING',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                        color: isConfirmed ? Colors.green : Colors.orange)),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(String label, int value, Color color) => Column(children: [
    Text(value.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
  ]);
}
