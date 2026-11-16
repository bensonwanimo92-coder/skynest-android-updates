import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'rent_ledger.dart';
import 'mpesa_service.dart';
import 'mpesa_rent_payment_screen.dart';

class TenantRentOverviewScreen extends StatelessWidget {
  const TenantRentOverviewScreen({super.key});

  static final NumberFormat _kes = NumberFormat.currency(
    locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0,
  );

  String _periodFor(Map<String, dynamic> data) {
    final explicit = data['period']?.toString();
    if (explicit != null && RegExp(r'^\d{4}-\d{2}$').hasMatch(explicit)) return explicit;
    final stamp = data['createdAt'];
    if (stamp is Timestamp) return DateFormat('yyyy-MM').format(stamp.toDate());
    return 'Undated';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Sign in again to view your rent account.')));
    }
    final db = FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('My rent & balance')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('rentInvoices').where('tenantId', isEqualTo: uid).snapshots(),
        builder: (context, invoiceSnapshot) {
          if (invoiceSnapshot.hasError) {
            return const Center(child: Text('Your rent statements could not be loaded.'));
          }
          if (!invoiceSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('payments').where('tenantId', isEqualTo: uid).snapshots(),
            builder: (context, paymentSnapshot) {
              if (paymentSnapshot.hasError) {
                return const Center(child: Text('Your payment history could not be loaded.'));
              }
              if (!paymentSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final paymentDocs = paymentSnapshot.data!.docs;
              final invoices = <RentInvoiceLedger>[];
              for (final doc in invoiceSnapshot.data!.docs) {
                final data = doc.data();
                final houseId = data['houseId']?.toString() ?? '';
                final period = data['period']?.toString() ?? 'Undated';
                final payments = <RentPaymentRecord>[];
                for (final paymentDoc in paymentDocs) {
                  final payment = paymentDoc.data();
                  if ((payment['houseId']?.toString() ?? '') != houseId ||
                      _periodFor(payment) != period) continue;
                  final amount = (payment['amount'] as num?)?.round() ?? 0;
                  if (amount <= 0) continue;
                  payments.add(RentPaymentRecord(
                    transactionId: payment['transactionCode']?.toString().isNotEmpty == true
                        ? payment['transactionCode'].toString() : paymentDoc.id,
                    amountKes: amount,
                    state: rentTransactionStateFromStatus(payment['status']),
                    mpesaReceipt: payment['transactionCode']?.toString(),
                    receivedAt: payment['createdAt'] is Timestamp
                        ? (payment['createdAt'] as Timestamp).toDate() : null,
                  ));
                }
                invoices.add(RentInvoiceLedger(
                  invoiceId: doc.id,
                  landlordId: data['landlordId']?.toString() ?? '',
                  tenantId: uid,
                  houseId: houseId,
                  houseNo: data['houseNo']?.toString(),
                  tenantName: data['tenantName']?.toString(),
                  period: period,
                  amountDueKes: (data['amountDueKes'] as num?)?.round() ?? 0,
                  payments: payments,
                ));
              }
              invoices.sort((a, b) => b.period.compareTo(a.period));
              final due = invoices.fold<int>(0, (sum, invoice) => sum + invoice.amountDueKes);
              final received = invoices.fold<int>(0, (sum, invoice) => sum + invoice.totalConfirmedKes);
              final balance = invoices.fold<int>(0, (sum, invoice) => sum + invoice.balanceKes);
              final credit = invoices.fold<int>(0, (sum, invoice) => sum + invoice.creditKes);
              return RefreshIndicator(
                onRefresh: () async {
                  // Firestore streams refresh automatically; this gesture gives
                  // the user a predictable pull-to-refresh affordance.
                  await Future<void>.delayed(const Duration(milliseconds: 250));
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('MY RENT SUMMARY',
                              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                            const SizedBox(height: 12),
                            _summary('Total rent billed', due, Colors.blue),
                            _summary('Verified payments', received, Colors.green),
                            _summary('Balance outstanding', balance, balance > 0 ? Colors.red : Colors.green),
                            if (credit > 0) _summary('Available rent credit', credit, Colors.teal),
                            const SizedBox(height: 8),
                            const Text('Only payments verified by your landlord count as received. Pending and reversed payments are excluded.',
                              style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    if (balance > 0) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MpesaRentPaymentScreen())),
                        icon: const Icon(Icons.phone_android_rounded),
                        label: const Text('Pay rent with M-Pesa'),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You can pay all or part of your outstanding balance. Payment goes to your linked landlord’s verified PayBill or Till.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('RENT STATEMENTS',
                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                    if (invoices.isEmpty)
                      const Card(child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No rent statement has been issued to your account yet. Your landlord’s saved monthly statements will appear here.'),
                      )),
                    ...invoices.map((invoice) {
                      final color = switch (invoice.state) {
                        RentInvoiceState.paid => Colors.green,
                        RentInvoiceState.partiallyPaid => Colors.orange,
                        RentInvoiceState.overpaid => Colors.teal,
                        RentInvoiceState.unpaid => Colors.red,
                        RentInvoiceState.unknown => Colors.grey,
                      };
                      final label = switch (invoice.state) {
                        RentInvoiceState.paid => 'PAID',
                        RentInvoiceState.partiallyPaid => 'PARTIAL',
                        RentInvoiceState.overpaid => 'CREDIT',
                        RentInvoiceState.unpaid => 'UNPAID',
                        RentInvoiceState.unknown => 'DUE UNKNOWN',
                      };
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          leading: Icon(Icons.receipt_long_outlined, color: color),
                          title: Text('House ${invoice.houseNo ?? invoice.houseId} • ${invoice.period}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Rent due: ${_kes.format(invoice.amountDueKes)}'),
                          trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            _summary('Verified paid', invoice.totalConfirmedKes, Colors.green),
                            _summary('Remaining balance', invoice.balanceKes, invoice.balanceKes > 0 ? Colors.red : Colors.green),
                            if (invoice.creditKes > 0) _summary('Credit', invoice.creditKes, Colors.teal),
                            const SizedBox(height: 8),
                            if (invoice.payments.isEmpty)
                              const Align(alignment: Alignment.centerLeft,
                                child: Text('No payment records are linked to this statement yet.'))
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
                                trailing: payment.receivedAt == null ? null
                                  : Text(DateFormat('dd MMM').format(payment.receivedAt!),
                                      style: const TextStyle(fontSize: 11)),
                              )),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _startMpesaPayment(BuildContext context, int outstandingBalance) async {
    final amountController = TextEditingController(
      text: (outstandingBalance > 150000 ? 150000 : outstandingBalance).toString(),
    );
    final phoneController = TextEditingController();
    try {
      final details = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pay rent with M-Pesa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Outstanding balance: KSh ' + outstandingBalance.toString()),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (KES)',
                  helperText: 'Full or partial payment',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'M-Pesa phone number',
                  hintText: '07XXXXXXXX or 2547XXXXXXXX',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your linked landlord is selected securely by SkyNest. You cannot change the receiving account.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'amount': amountController.text.trim(),
                'phone': phoneController.text.trim(),
              }),
              child: const Text('CONTINUE'),
            ),
          ],
        ),
      );
      if (details == null || !context.mounted) return;
      final amount = int.tryParse(details['amount'] ?? '');
      final phone = details['phone'] ?? '';
      if (amount == null || amount < 1 || amount > outstandingBalance || amount > 150000) {
        final maximum = outstandingBalance > 150000 ? 150000 : outstandingBalance;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter an amount between KSh 1 and KSh ' + maximum.toString() + '.')),
        );
        return;
      }
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final validPhone = (digits.length == 10 && (digits.startsWith('07') || digits.startsWith('01'))) ||
          (digits.length == 12 && (digits.startsWith('2547') || digits.startsWith('2541')));
      if (!validPhone) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid Kenyan M-Pesa phone number.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Requesting a secure M-Pesa prompt…')),
      );
      final message = await SkyNestMpesaService.requestStkPush(
        amountKes: amount,
        phone: digits,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('M-Pesa prompt requested'),
          content: Text(message + '\n\nYour balance updates after Safaricom confirms the payment.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      amountController.dispose();
      phoneController.dispose();
    }
  }

  Widget _summary(String label, int amount, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(_kes.format(amount), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    ]),
  );
}
