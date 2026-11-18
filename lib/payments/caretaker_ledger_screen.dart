import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CaretakerLedgerScreen extends StatefulWidget {
  const CaretakerLedgerScreen({super.key});
  @override
  State<CaretakerLedgerScreen> createState() => _CaretakerLedgerScreenState();
}

class _CaretakerLedgerScreenState extends State<CaretakerLedgerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _tenant = TextEditingController();
  final _labour = TextEditingController();
  final _materials = TextEditingController();
  final _notes = TextEditingController();
  final _reference = TextEditingController();
  String _category = 'Maintenance';
  String _priority = 'Normal';
  String _status = 'Open';
  String? _houseId;
  String _houseNo = '';
  DateTime _workDate = DateTime.now();
  DateTime? _followUp;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose(); _details.dispose(); _tenant.dispose();
    _labour.dispose(); _materials.dispose(); _notes.dispose(); _reference.dispose();
    super.dispose();
  }

  Future<void> _save(String landlordId, String caretakerId) async {
    if (!_formKey.currentState!.validate()) return;
    if (_houseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select the property this entry belongs to.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('caretakerWorkLedger').add({
        'landlordId': landlordId, 'caretakerId': caretakerId,
        'houseId': _houseId, 'houseNo': _houseNo,
        'category': _category, 'title': _title.text.trim(),
        'details': _details.text.trim(), 'tenantName': _tenant.text.trim(),
        'priority': _priority, 'status': _status,
        'workDate': Timestamp.fromDate(_workDate),
        'followUpDate': _followUp == null ? null : Timestamp.fromDate(_followUp!),
        'labourCost': double.tryParse(_labour.text.trim()) ?? 0,
        'materialsCost': double.tryParse(_materials.text.trim()) ?? 0,
        'reference': _reference.text.trim(), 'notes': _notes.text.trim(),
        'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      });
      _title.clear(); _details.clear(); _tenant.clear(); _labour.clear();
      _materials.clear(); _notes.clear(); _reference.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Detailed ledger entry saved.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save ledger entry: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, TextInputType? keyboard, bool required = false}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
      controller: c, minLines: lines, maxLines: lines, keyboardType: keyboard,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
    ));

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in to open the caretaker ledger.')));
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, profile) {
        if (!profile.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final user = profile.data?.data() ?? {};
        final landlordId = user['landlordId']?.toString() ?? '';
        if (landlordId.isEmpty) return const Scaffold(body: Center(child: Text('This caretaker account is not linked to a landlord.')));
        return Scaffold(
          appBar: AppBar(title: const Text('Caretaker Work Ledger')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('houses').where('caretakerIds', arrayContains: uid).snapshots(),
            builder: (context, houses) {
              if (houses.hasError) return Center(child: Text('Assigned properties could not load: ${houses.error}'));
              if (!houses.hasData) return const Center(child: CircularProgressIndicator());
              final docs = houses.data!.docs;
              return ListView(padding: const EdgeInsets.all(16), children: [
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CREATE A FULL WORK RECORD', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5)),
                  const SizedBox(height: 8),
                  const Text('Record inspections, repairs, incidents, tenant requests, purchases, follow-ups and supporting references. Entries are time-stamped and linked to the assigned property.'),
                  const SizedBox(height: 14),
                  Form(key: _formKey, child: Column(children: [
                    DropdownButtonFormField<String>(
                      value: docs.any((d) => d.id == _houseId) ? _houseId : null,
                      decoration: const InputDecoration(labelText: 'Assigned house / property', border: OutlineInputBorder()),
                      items: docs.map((d) => DropdownMenuItem(value: d.id, child: Text('House ${d.data()['houseNo'] ?? d.id} · ${d.data()['isOccupied'] == true ? 'Occupied' : 'Vacant'}'))).toList(),
                      onChanged: (v) => setState(() { _houseId = v; final match = docs.where((d) => d.id == v); _houseNo = match.isEmpty ? '' : (match.first.data()['houseNo'] ?? '').toString(); }),
                    ),
                    const SizedBox(height: 12),
                    _field(_title, 'Entry title / task', required: true),
                    _field(_details, 'Detailed description of work, inspection or incident', lines: 4, required: true),
                    _field(_tenant, 'Tenant / person involved (if applicable)'),
                    DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Record category', border: OutlineInputBorder()),
                      items: const ['Maintenance','Inspection','Repair','Cleaning','Security / Incident','Tenant Request','Utilities','Purchase / Materials','Rent Follow-up','Handover','Other'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) => setState(() => _category = v ?? 'Maintenance')),
                    const SizedBox(height: 12),
                    Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _priority, decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                      items: const ['Low','Normal','High','Urgent'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _priority = v ?? 'Normal'))),
                      const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(value: _status, decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: const ['Open','In progress','Completed','Awaiting materials','Escalated'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _status = v ?? 'Open')))]),
                    const SizedBox(height: 12),
                    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Work / inspection date'), subtitle: Text(DateFormat('EEE, dd MMM yyyy').format(_workDate)),
                      trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: _workDate, firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => _workDate = d); }),
                    ListTile(contentPadding: EdgeInsets.zero, title: const Text('Follow-up date'), subtitle: Text(_followUp == null ? 'Not scheduled' : DateFormat('EEE, dd MMM yyyy').format(_followUp!)),
                      trailing: Wrap(children: [if (_followUp != null) IconButton(onPressed: () => setState(() => _followUp = null), icon: const Icon(Icons.clear)), const Icon(Icons.event_available)]),
                      onTap: () async { final d = await showDatePicker(context: context, initialDate: _followUp ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if (d != null) setState(() => _followUp = d); }),
                    _field(_labour, 'Labour cost (KSh)', keyboard: TextInputType.number),
                    _field(_materials, 'Materials / purchases cost (KSh)', keyboard: TextInputType.number),
                    _field(_reference, 'Receipt, job card or reference number'),
                    _field(_notes, 'Additional notes / outcome / handover details', lines: 3),
                    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : () => _save(landlordId, uid),
                      icon: _saving ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving record…' : 'SAVE FULL LEDGER ENTRY'))),
                  ])),
                ]))),
                const SizedBox(height: 12),
                const Text('LEDGER HISTORY', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5)),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('caretakerWorkLedger').where('caretakerId', isEqualTo: uid).snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text('Ledger history unavailable: ${snap.error}'));
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final rows = snap.data!.docs.toList()..sort((a,b) {
                      final ad=a.data()['createdAt'], bd=b.data()['createdAt'];
                      final at=ad is Timestamp ? ad.toDate() : DateTime(1970);
                      final bt=bd is Timestamp ? bd.toDate() : DateTime(1970);
                      return bt.compareTo(at);
                    });
                    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Your saved work records will appear here.'));
                    return Column(children: rows.map((doc) {
                      final d=doc.data(); final created=d['createdAt'];
                      final date=created is Timestamp ? DateFormat('dd MMM yyyy · HH:mm').format(created.toDate()) : 'Saving…';
                      final cost=((d['labourCost'] as num?)?.toDouble() ?? 0)+((d['materialsCost'] as num?)?.toDouble() ?? 0);
                      return Card(child: ExpansionTile(
                        leading: Icon(d['status']=='Completed' ? Icons.task_alt : Icons.assignment_outlined),
                        title: Text(d['title']?.toString() ?? 'Work record', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('House ${d['houseNo'] ?? '—'} · ${d['category'] ?? 'Other'} · $date'),
                        childrenPadding: const EdgeInsets.fromLTRB(16,0,16,16),
                        children: [Align(alignment: Alignment.centerLeft, child: Text([
                          'Tenant: ${d['tenantName'] ?? '—'}','Details: ${d['details'] ?? '—'}',
                          'Priority / status: ${d['priority'] ?? 'Normal'} / ${d['status'] ?? 'Open'}',
                          'Labour: KSh ${d['labourCost'] ?? 0} · Materials: KSh ${d['materialsCost'] ?? 0} · Total: KSh $cost',
                          'Follow-up: ${d['followUpDate'] is Timestamp ? DateFormat('dd MMM yyyy').format((d['followUpDate'] as Timestamp).toDate()) : '—'}',
                          'Reference: ${d['reference'] ?? '—'}','Notes: ${d['notes'] ?? '—'}',
                        ].join('\n')))],
                      ));
                    }).toList());
                  },
                ),
              ]);
            },
          ),
        );
      },
    );
  }
}
