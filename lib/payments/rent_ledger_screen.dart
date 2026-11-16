import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'rent_ledger.dart';

class RentLedgerScreen extends StatefulWidget {
  const RentLedgerScreen({super.key});

  @override
  State<RentLedgerScreen> createState() => _RentLedgerScreenState();
}

class _RentLedgerScreenState extends State<RentLedgerScreen> {
  late Future<List<RentInvoiceLedger>> _ledgerFuture;
  final NumberFormat _kes = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _ledgerFuture = _loadLedger();
  }

  Future<List<RentInvoiceLedger>> _loadLedger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in again to view the rent ledger.');
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('payments').where('createdBy', isEqualTo: uid).get(),
      db.collection('payments').where('landlordId', isEqualTo: uid).get(),
      db.collection('houses').where('createdBy', isEqualTo: uid).get(),
      db.collection('users').where('landlordId', isEqualTo: uid).get(),
    ]);

    final paymentDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final query in results.take(2)) {
      for (final doc in query.docs) {
        paymentDocs[doc.id] = doc;
      }
    }

    final houses = <String, Map<String, dynamic>>{};
    final houseByNumber = <String, Map<String, dynamic>>{};
    for (final doc in results[2].docs) {
      final data = doc.data();
      final record = <String, dynamic>{...data, '_id': doc.id};
      houses[doc.id] = record;
      final number = data['houseNo']?.toString();
      if (number != null && number.isNotEmpty) houseByNumber[number] = record;
    }

    final now = DateTime.now();
    final currentPeriod = DateFormat('yyyy-MM').format(now);
    final grouped = <String, Map<String, dynamic>>{};

    void ensureInvoice({
      required String tenantId,
      required String tenantName,
      required String houseId,
      required String houseNo,
      required String period,
      required int dueKes,
    }) {
      final key = '$tenantId|$houseId|$period';
      grouped.putIfAbsent(key, () => <String, dynamic>{
        'tenantId': tenantId,
        'tenantName': tenantName,
        'houseId': houseId,
        'houseNo': houseNo,
        'period': period,
        'dueKes': dueKes,
        'payments': <RentPaymentRecord>[],
      });
    }

    for (final tenantDoc in results[3].docs) {
      final tenant = tenantDoc.data();
      if (tenant['role'] != 'tenant' || tenant['status'] != 'active') continue;
      final houseId = tenant['houseId']?.toString() ?? '';
      final house = houses[houseId];
      if (house == null) continue;
      final rent = (house['rent'] as num?)?.round() ?? 0;
      if (rent <= 0) continue;
      ensureInvoice(
        tenantId: tenantDoc.id,
        tenantName: tenant['displayName']?.toString() ?? 'Tenant',
        houseId: houseId,
        houseNo: tenant['houseNo']?.toString() ?? house['houseNo']?.toString() ?? '',
        period: currentPeriod,
        dueKes: rent,
      );
    }

    for (final doc in paymentDocs.values) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final period = createdAt is Timestamp
          ? DateFormat('yyyy-MM').format(createdAt.toDate())
          : 'Undated';
      final houseNo = data['houseNo']?.toString() ?? '';
      final houseId = data['houseId']?.toString() ?? houseByNumber[houseNo]?['_id']?.toString() ?? '';
      final house = houses[houseId] ?? houseByNumber[houseNo];
      final dueKes = (house?['rent'] as num?)?.round() ?? 0;
      final tenantId = data['tenantId']?.toString() ?? data['tenantName']?.toString() ?? 'unknown';
      final tenantName = data['tenantName']?.toString() ?? 'Tenant';
      ensureInvoice(
        tenantId: tenantId,
        tenantName: tenantName,
        houseId: houseId,
        houseNo: houseNo,
        period: period,
        dueKes: dueKes,
      );
      final state = rentTransactionStateFromStatus(data['status']);
      final amount = (data['amount'] as num?)?.round() ?? 0;
      if (amount <= 0) continue;
      grouped['$tenantId|$houseId|$period']!['payments'].add(RentPaymentRecord(
        transactionId: data['transactionCode']?.toString().isNotEmpty == true
            ? data['transactionCode'].toString()
            : doc.id,
        amountKes: amount,
        state: state,
        mpesaReceipt: data['transactionCode']?.toString(),
        receivedAt: createdAt is Timestamp ? createdAt.toDate() : null,
      ));
    }

    final invoices = grouped.entries.map((entry) {
      final data = entry.value;
      return RentInvoiceLedger(
        invoiceId: entry.key,
        landlordId: uid,
        tenantId: data['tenantId'] as String,
        houseId: data['houseId'] as String,
        period: data['period'] as String,
        tenantName: data['tenantName'] as String?,
        houseNo: data['houseNo'] as String?,
        amountDueKes: data['dueKes'] as int,
        payments: List<RentPaymentRecord>.from(data['payments'] as List<RentPaymentRecord>),
      );
    }).toList()
      ..sort((a, b) => b.period.compareTo(a.period));
    return invoices;
  }

  Color _stateColor(RentInvoiceState state) {
    switch (state) {
      case RentInvoiceState.paid: return Colors.green;
      case RentInvoiceState.partiallyPaid: return Colors.orange;
      case RentInvoiceState.overpaid: return Colors.blue;
      case RentInvoiceState.unpaid: return Colors.red;
    }
  }

  String _stateLabel(RentInvoiceState state) {
    switch (state) {
      case RentInvoiceState.paid: return 'PAID';
      case RentInvoiceState.partiallyPaid: return 'PARTIAL';
      case RentInvoiceState.overpaid: return 'CREDIT';
      case RentInvoiceState.unpaid: return 'UNPAID';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rent ledger'),
      actions: [
        IconButton(
          tooltip: 'Refresh ledger',
          onPressed: () => setState(() => _ledgerFuture = _loadLedger()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<RentInvoiceLedger>>(
      future: _ledgerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('The rent ledger could not be loaded: ${snapshot.error}', textAlign: TextAlign.center),
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final invoices = snapshot.data!;
        if (invoices.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No tenant rent invoices or payment history are available yet.', textAlign: TextAlign.center),
        ));
        final due = invoices.fold<int>(0, (sum, item) => sum + item.amountDueKes);
        final received = invoices.fold<int>(0, (sum, item) => sum + item.totalConfirmedKes);
        final outstanding = invoices.fold<int>(0, (sum, item) => sum + item.balanceKes);
        final credit = invoices.fold<int>(0, (sum, item) => sum + item.creditKes);
        return RefreshIndicator(
          onRefresh: () async => setState(() => _ledgerFuture = _loadLedger()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('PORTFOLIO SUMMARY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 14),
                    _summaryRow('Rent due', due, Colors.blue),
                    _summaryRow('Verified received', received, Colors.green),
                    _summaryRow('Outstanding', outstanding, Colors.red),
                    if (credit > 0) _summaryRow('Tenant credit', credit, Colors.teal),
                    const SizedBox(height: 8),
                    const Text('Only verified payments reduce the balance. Pending and reversed transactions remain excluded.',
                      style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              ...invoices.map((invoice) {
                final color = _stateColor(invoice.state);
                final paid = invoice.totalConfirmedKes;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    leading: Container(
                      width: 5,
                      height: 54,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                    ),
                    title: Text(invoice.tenantName ?? invoice.tenantId, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('House ${invoice.houseNo ?? invoice.houseId} • ${invoice.period}'),
                    trailing: Text(_stateLabel(invoice.state), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _summaryRow('Rent due', invoice.amountDueKes, Colors.blue),
                      _summaryRow('Verified paid', paid, Colors.green),
                      _summaryRow('Balance', invoice.balanceKes, invoice.balanceKes > 0 ? Colors.red : Colors.green),
                      if (invoice.creditKes > 0) _summaryRow('Credit', invoice.creditKes, Colors.teal),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: invoice.paidFraction, minHeight: 7),
                      const SizedBox(height: 10),
                      if (invoice.payments.isEmpty)
                        const Align(alignment: Alignment.centerLeft, child: Text('No payment transactions recorded for this period.'))
                      else
                        ...invoice.payments.map((payment) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            payment.state == RentTransactionState.confirmed ? Icons.verified
                              : payment.state == RentTransactionState.reversed ? Icons.undo : Icons.hourglass_top,
                            color: payment.state == RentTransactionState.confirmed ? Colors.green
                              : payment.state == RentTransactionState.reversed ? Colors.red : Colors.orange,
                          ),
                          title: Text(_kes.format(payment.amountKes)),
                          subtitle: Text('${payment.transactionId} • ${payment.state.name.toUpperCase()}'),
                          trailing: payment.receivedAt == null
                              ? null
                              : Text(DateFormat('dd MMM').format(payment.receivedAt!), style: const TextStyle(fontSize: 11)),
                        )),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );

  Widget _summaryRow(String label, int amount, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(_kes.format(amount), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    ]),
  );
}
