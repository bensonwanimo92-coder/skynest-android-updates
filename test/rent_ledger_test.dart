import 'package:flutter_test/flutter_test.dart';
import 'package:chuka/payments/rent_ledger.dart';

void main() {
  RentInvoiceLedger invoice({
    int due = 10000,
    List<RentPaymentRecord> payments = const <RentPaymentRecord>[],
  }) => RentInvoiceLedger(
    invoiceId: 'invoice-1',
    landlordId: 'landlord-1',
    tenantId: 'tenant-1',
    houseId: 'house-A1',
    period: '2026-11',
    amountDueKes: due,
    payments: payments,
  );

  test('a confirmed instalment reduces the outstanding balance', () {
    final ledger = invoice(payments: const <RentPaymentRecord>[
      RentPaymentRecord(
        transactionId: 'QAB123',
        amountKes: 4000,
        state: RentTransactionState.confirmed,
      ),
    ]);

    expect(ledger.totalConfirmedKes, 4000);
    expect(ledger.balanceKes, 6000);
    expect(ledger.creditKes, 0);
    expect(ledger.state, RentInvoiceState.partiallyPaid);
    expect(ledger.paidFraction, 0.4);
  });

  test('pending and reversed transactions do not count as received', () {
    final ledger = invoice(payments: const <RentPaymentRecord>[
      RentPaymentRecord(
        transactionId: 'PENDING1',
        amountKes: 3000,
        state: RentTransactionState.pending,
      ),
      RentPaymentRecord(
        transactionId: 'REVERSED1',
        amountKes: 2000,
        state: RentTransactionState.reversed,
      ),
    ]);

    expect(ledger.totalConfirmedKes, 0);
    expect(ledger.balanceKes, 10000);
    expect(ledger.state, RentInvoiceState.unpaid);
  });

  test('multiple confirmed instalments can complete an invoice', () {
    final ledger = invoice(payments: const <RentPaymentRecord>[
      RentPaymentRecord(
        transactionId: 'QAB001',
        amountKes: 3500,
        state: RentTransactionState.confirmed,
      ),
      RentPaymentRecord(
        transactionId: 'QAB002',
        amountKes: 2500,
        state: RentTransactionState.confirmed,
      ),
      RentPaymentRecord(
        transactionId: 'QAB003',
        amountKes: 4000,
        state: RentTransactionState.confirmed,
      ),
    ]);

    expect(ledger.totalConfirmedKes, 10000);
    expect(ledger.balanceKes, 0);
    expect(ledger.state, RentInvoiceState.paid);
    expect(ledger.paidFraction, 1);
  });

  test('an overpayment is shown as tenant credit, not a negative balance', () {
    final ledger = invoice(payments: const <RentPaymentRecord>[
      RentPaymentRecord(
        transactionId: 'QABOVER',
        amountKes: 12000,
        state: RentTransactionState.confirmed,
      ),
    ]);

    expect(ledger.balanceKes, 0);
    expect(ledger.creditKes, 2000);
    expect(ledger.state, RentInvoiceState.overpaid);
  });
  test('legacy invoice without a saved rent amount is marked unknown, not overpaid', () {
    final invoice = RentInvoiceLedger(
      invoiceId: 'legacy', landlordId: 'landlord', tenantId: 'tenant',
      houseId: 'house', period: '2025-04', amountDueKes: 0,
      dueAmountKnown: false,
      payments: const [RentPaymentRecord(
        transactionId: 'legacy-payment', amountKes: 12000,
        state: RentTransactionState.confirmed,
      )],
    );
    expect(invoice.state, RentInvoiceState.unknown);
    expect(invoice.balanceKes, 0);
    expect(invoice.creditKes, 0);
    expect(invoice.paidFraction, 0);
  });

  test('status parsing never treats unpaid or pending labels as received', () {
    for (final status in <String>[
      'unpaid', 'not paid', 'pending', 'pending verification',
      'awaiting_caretaker', 'failed', 'unknown',
    ]) {
      expect(rentTransactionStateFromStatus(status), RentTransactionState.pending,
          reason: 'Status "$status" must not reduce the balance.');
    }
  });

  test('status parsing accepts explicit receipt and reversal states only', () {
    for (final status in <String>[
      'paid', 'confirmed', 'received', 'Received (landlord verified)',
      'successful', 'success', 'completed',
    ]) {
      expect(rentTransactionStateFromStatus(status), RentTransactionState.confirmed);
    }
    for (final status in <String>['reversed', 'reversal', 'refunded', 'refund']) {
      expect(rentTransactionStateFromStatus(status), RentTransactionState.reversed);
    }
  });

}
