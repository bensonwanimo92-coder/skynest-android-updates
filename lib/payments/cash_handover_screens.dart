import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CaretakerCashCollectionScreen extends StatefulWidget {
  const CaretakerCashCollectionScreen({super.key});

  @override
  State<CaretakerCashCollectionScreen> createState() => _CaretakerCashCollectionScreenState();
}

class _CaretakerCashCollectionScreenState extends State<CaretakerCashCollectionScreen> {
  final amount = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> houses = [];
  Map<String, String> tenantNames = {};
  String? landlordId;
  String? selectedHouseId;
  bool loading = true;
  bool saving = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() { loading = false; loadError = 'Sign in again to continue.'; });
      return;
    }
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = profile.data() ?? {};
      if (data['role'] != 'caretaker' || data['status'] != 'active') {
        throw StateError('Only an active caretaker can record cash rent.');
      }
      if (data['caretakerPermission'] != 'can_collect') {
        throw StateError('Your account is View Only. Ask the landlord to grant cash-collection permission.');
      }
      final owner = data['landlordId']?.toString();
      if (owner == null || owner.isEmpty) throw StateError('Your landlord link is missing.');
      final result = await FirebaseFirestore.instance.collection('houses')
          .where('landlordId', isEqualTo: owner)
          .where('caretakerIds', arrayContains: uid).get();
      final tenantIds = result.docs
          .map((house) => house.data()['assignedTenantId']?.toString() ?? '')
          .where((id) => id.isNotEmpty).toSet();
      final tenantProfiles = await Future.wait(tenantIds.map((id) async {
        try {
          return await FirebaseFirestore.instance.collection('users').doc(id).get();
        } catch (_) {
          return null;
        }
      }));
      final names = <String, String>{};
      for (final tenant in tenantProfiles) {
        if (tenant == null || !tenant.exists) continue;
        final tenantData = tenant.data() ?? {};
        names[tenant.id] = (tenantData['displayName'] ?? tenantData['name'] ?? 'Tenant').toString();
      }
      if (!mounted) return;
      setState(() {
        landlordId = owner;
        houses = result.docs;
        tenantNames = names;
        selectedHouseId = result.docs.isNotEmpty ? result.docs.first.id : null;
        loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { loading = false; loadError = error.toString().replaceFirst('Bad state: ', ''); });
    }
  }

  Future<void> _recordCollection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final owner = landlordId;
    final selectedHouses = houses.where((item) => item.id == selectedHouseId).toList();
    final house = selectedHouses.isEmpty ? null : selectedHouses.first;
    final value = double.tryParse(amount.text.trim());
    if (uid == null || owner == null || house == null || value == null || value <= 0) {
      _message('Select an assigned house and enter a valid amount greater than zero.');
      return;
    }
    final data = house.data();
    final tenantId = data['assignedTenantId']?.toString() ?? '';
    final houseNo = data['houseNo']?.toString() ?? '';
    if (tenantId.isEmpty || houseNo.isEmpty) {
      _message('This house has no verified assigned tenant. Ask the landlord to update the tenancy first.');
      return;
    }
    if (saving) return;
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('cashCollections').add({
        'landlordId': owner,
        'caretakerId': uid,
        'tenantId': tenantId,
        'tenantName': tenantNames[tenantId] ?? 'Tenant',
        'houseId': house.id,
        'houseNo': houseNo,
        'amountKes': value.round(),
        'method': 'CASH',
        'status': 'collected_pending_handover',
        'collectedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      amount.clear();
      _message('Cash collection recorded. Submit a handover when you give the cash to the landlord.');
    } catch (error) {
      _message('Cash collection could not be saved: $error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submitHandover(QueryDocumentSnapshot<Map<String, dynamic>> collectionDoc) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final data = collectionDoc.data();
    if (uid == null || data['caretakerId'] != uid || data['status'] != 'collected_pending_handover') return;
    try {
      await FirebaseFirestore.instance.collection('cashHandovers').doc(collectionDoc.id).set({
        'collectionId': collectionDoc.id,
        'landlordId': data['landlordId'],
        'caretakerId': uid,
        'tenantId': data['tenantId'],
        'tenantName': data['tenantName'],
        'houseId': data['houseId'],
        'houseNo': data['houseNo'],
        'amountKes': data['amountKes'],
        'status': 'submitted',
        'submittedAt': FieldValue.serverTimestamp(),
      });
      _message('Handover submitted to the landlord for acknowledgement.');
    } catch (error) {
      _message('Handover could not be submitted: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (loadError != null) return Scaffold(
      appBar: AppBar(title: const Text('Cash collections')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(loadError!, textAlign: TextAlign.center))),
    );
    if (uid == null || landlordId == null) return const Scaffold(body: Center(child: Text('Sign in again to continue.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Cash collections & handovers')),
      body: houses.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No assigned houses are available for cash collection.')))
        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('cashCollections')
                .where('caretakerId', isEqualTo: uid)
                .where('landlordId', isEqualTo: landlordId)
                .where('houseId', isEqualTo: selectedHouseId).snapshots(),
            builder: (context, collections) {
              if (collections.hasError) return Center(child: Text('Cash records could not load: ${collections.error}'));
              if (!collections.hasData) return const Center(child: CircularProgressIndicator());
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('cashHandovers')
                    .where('caretakerId', isEqualTo: uid)
                    .where('landlordId', isEqualTo: landlordId)
                    .where('houseId', isEqualTo: selectedHouseId).snapshots(),
                builder: (context, handovers) {
                  if (handovers.hasError) return Center(child: Text('Handover records could not load: ${handovers.error}'));
                  if (!handovers.hasData) return const Center(child: CircularProgressIndicator());
                  final handoverByCollection = <String, Map<String, dynamic>>{
                    for (final doc in handovers.data!.docs) doc.id: doc.data(),
                  };
                  final docs = collections.data!.docs.toList()
                    ..sort((a, b) {
                      final ad = a.data()['collectedAt'];
                      final bd = b.data()['collectedAt'];
                      final at = ad is Timestamp ? ad.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      final bt = bd is Timestamp ? bd.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      return bt.compareTo(at);
                    });
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('RECORD CASH RECEIVED', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedHouseId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Assigned house'),
                            items: houses.map((house) => DropdownMenuItem(
                              value: house.id,
                              child: Text('House ${house.data()['houseNo'] ?? house.id}'),
                            )).toList(),
                            onChanged: saving ? null : (value) => setState(() => selectedHouseId = value),
                          ),
                          const SizedBox(height: 10),
                          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: false),
                            decoration: const InputDecoration(labelText: 'Cash received (KSh)')),
                          const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: FilledButton.icon(
                            onPressed: saving ? null : _recordCollection,
                            icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.payments_outlined),
                            label: Text(saving ? 'SAVING...' : 'RECORD CASH COLLECTION'),
                          )),
                          const Text('This records cash physically received by you. It does not mark the landlord as paid until the landlord acknowledges handover.',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                      )),
                      const SizedBox(height: 14),
                      Text('COLLECTION HISTORY • HOUSE ${houses.firstWhere((house) => house.id == selectedHouseId).data()['houseNo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
                      if (docs.isEmpty) const Padding(
                        padding: EdgeInsets.all(18), child: Text('No cash collections recorded yet.')),
                      ...docs.map((doc) {
                        final d = doc.data();
                        final handover = handoverByCollection[doc.id];
                        final handoverStatus = handover?['status']?.toString();
                        final acknowledged = handoverStatus == 'acknowledged';
                        final submitted = handoverStatus == 'submitted';
                        final status = acknowledged ? 'HANDED OVER' : submitted ? 'AWAITING LANDLORD' : 'AWAITING HANDOVER';
                        final stamp = d['collectedAt'];
                        final date = stamp is Timestamp ? stamp.toDate().toLocal().toString().split('.').first : 'Date pending';
                        return Card(child: ListTile(
                          leading: Icon(acknowledged ? Icons.verified : Icons.payments_outlined,
                            color: acknowledged ? Colors.green : Colors.orange),
                          title: Text('KSh ${d['amountKes'] ?? 0} • House ${d['houseNo'] ?? ''}'),
                          subtitle: Text('${d['tenantName'] ?? 'Tenant'} • $date\n$status'),
                          isThreeLine: true,
                          trailing: !submitted && !acknowledged
                            ? IconButton(tooltip: 'Submit cash handover', icon: const Icon(Icons.outbox_outlined),
                                onPressed: () => _submitHandover(doc))
                            : null,
                        ));
                      }),
                    ],
                  );
                },
              );
            },
          ),
    );
  }
}

class LandlordCashHandoverScreen extends StatelessWidget {
  const LandlordCashHandoverScreen({super.key});

  Future<void> _acknowledge(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Acknowledge cash handover?'),
        content: Text('Confirm that you physically received KSh ${doc.data()['amountKes'] ?? 0} from the caretaker for House ${doc.data()['houseNo'] ?? ''}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ACKNOWLEDGE RECEIPT')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await doc.reference.update({
        'status': 'acknowledged',
        'acknowledgedBy': uid,
        'acknowledgedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cash handover acknowledged.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not acknowledge handover: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in again to continue.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Caretaker cash handovers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('cashHandovers')
            .where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, handoverSnapshot) {
          if (handoverSnapshot.hasError) {
            return Center(child: Text('Cash handovers could not load: ${handoverSnapshot.error}'));
          }
          if (!handoverSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = handoverSnapshot.data!.docs.toList()
            ..sort((a, b) {
              final ad = a.data()['submittedAt'];
              final bd = b.data()['submittedAt'];
              final at = ad is Timestamp ? ad.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              final bt = bd is Timestamp ? bd.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });
          final handoverByCollection = <String, Map<String, dynamic>>{
            for (final doc in docs) doc.id: doc.data(),
          };
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('cashCollections')
                .where('landlordId', isEqualTo: uid).snapshots(),
            builder: (context, collectionSnapshot) {
              if (collectionSnapshot.hasError) {
                return Center(child: Text('Cash collection totals could not load: ${collectionSnapshot.error}'));
              }
              if (!collectionSnapshot.hasData) return const Center(child: CircularProgressIndicator());
              final collections = collectionSnapshot.data!.docs;
              final totalCollected = collections.fold<int>(0, (sum, item) =>
                  sum + ((item.data()['amountKes'] as num?)?.round() ?? 0));
              final totalAcknowledged = docs.where((doc) => doc.data()['status'] == 'acknowledged')
                  .fold<int>(0, (sum, item) =>
                      sum + ((item.data()['amountKes'] as num?)?.round() ?? 0));
              final awaitingHandover = collections.where((item) =>
                  !handoverByCollection.containsKey(item.id))
                  .fold<int>(0, (sum, item) =>
                      sum + ((item.data()['amountKes'] as num?)?.round() ?? 0));
              final awaitingAcknowledgement = docs.where((doc) =>
                  doc.data()['status'] == 'submitted')
                  .fold<int>(0, (sum, item) =>
                      sum + ((item.data()['amountKes'] as num?)?.round() ?? 0));
              final outstanding = (totalCollected - totalAcknowledged).clamp(0, totalCollected);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('CASH RECONCILIATION', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                      const SizedBox(height: 10),
                      _summaryRow('Total collected by caretakers', totalCollected, Colors.blueGrey),
                      _summaryRow('Cash handovers acknowledged', totalAcknowledged, Colors.green),
                      _summaryRow('Awaiting physical handover', awaitingHandover, Colors.orange),
                      _summaryRow('Awaiting your acknowledgement', awaitingAcknowledgement, Colors.orange),
                      const Divider(),
                      _summaryRow('Outstanding cash to reconcile', outstanding, outstanding > 0 ? Colors.red : Colors.green),
                    ]),
                  )),
                  const SizedBox(height: 16),
                  const Text('COLLECTIONS AWAITING PHYSICAL HANDOVER',
                    style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
                  if (collections.where((item) => !handoverByCollection.containsKey(item.id)).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('All recorded collections have been submitted for handover.'),
                    ),
                  ...collections.where((item) => !handoverByCollection.containsKey(item.id)).map((item) {
                    final data = item.data();
                    final stamp = data['collectedAt'];
                    final date = stamp is Timestamp
                        ? stamp.toDate().toLocal().toString().split('.').first
                        : 'Date pending';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.pending_actions, color: Colors.orange),
                        title: Text('KSh ${data['amountKes'] ?? 0} • House ${data['houseNo'] ?? ''}'),
                        subtitle: Text('${data['tenantName'] ?? 'Tenant'} • Caretaker ${data['caretakerId'] ?? ''}\\n$date • NOT YET HANDED OVER'),
                        isThreeLine: true,
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const Text('HANDOVER HISTORY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                  if (docs.isEmpty) const Padding(
                    padding: EdgeInsets.all(18), child: Text('No caretaker cash handovers have been submitted.')),
                  ...docs.map((doc) {
                    final d = doc.data();
                    final acknowledged = d['status'] == 'acknowledged';
                    final stamp = d['submittedAt'];
                    final date = stamp is Timestamp ? stamp.toDate().toLocal().toString().split('.').first : 'Date pending';
                    return Card(child: ListTile(
                      leading: Icon(acknowledged ? Icons.verified : Icons.pending_actions,
                        color: acknowledged ? Colors.green : Colors.orange),
                      title: Text('KSh ${d['amountKes'] ?? 0} • House ${d['houseNo'] ?? ''}'),
                      subtitle: Text('${d['tenantName'] ?? 'Tenant'} • Caretaker ${d['caretakerId'] ?? ''}\\n$date • ${acknowledged ? 'ACKNOWLEDGED' : 'AWAITING RECEIPT'}'),
                      isThreeLine: true,
                      trailing: acknowledged ? const Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(tooltip: 'Acknowledge receipt', icon: const Icon(Icons.check_circle_outline),
                            onPressed: () => _acknowledge(context, doc)),
                    ));
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _summaryRow(String label, int amount, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text('KSh $amount', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    ]),
  );
}
