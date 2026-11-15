/// Domain model for rent invoices and verified instalment payments.
///
/// Amounts are stored as whole Kenyan shillings (KES). Pending and reversed
/// transactions never reduce the tenant's outstanding balance.
enum RentTransactionState { pending, confirmed, reversed }

enum RentInvoiceState { unpaid, partiallyPaid, paid, overpaid }

class RentPaymentRecord {
  const RentPaymentRecord({
    required this.transactionId,
    required this.amountKes,
    required this.state,
    this.mpesaReceipt,
    this.receivedAt,
  }) : assert(amountKes > 0);

  final String transactionId;
  final int amountKes;
  final RentTransactionState state;
  final String? mpesaReceipt;
  final DateTime? receivedAt;

  bool get countsAsReceived => state == RentTransactionState.confirmed;
}

class RentInvoiceLedger {
  const RentInvoiceLedger({
    required this.invoiceId,
    required this.landlordId,
    required this.tenantId,
    required this.houseId,
    required this.period,
    required this.amountDueKes,
    this.dueAt,
    this.promisedPaymentAt,
    this.payments = const <RentPaymentRecord>[],
  }) : assert(amountDueKes >= 0);

  final String invoiceId;
  final String landlordId;
  final String tenantId;
  final String houseId;
  final String period;
  final int amountDueKes;
  final DateTime? dueAt;

  /// Optional date the tenant says they expect to make the next instalment.
  /// This is a reminder hint, not proof that payment has been made.
  final DateTime? promisedPaymentAt;

  final List<RentPaymentRecord> payments;

  int get totalConfirmedKes => payments
      .where((payment) => payment.countsAsReceived)
      .fold<int>(0, (total, payment) => total + payment.amountKes);

  int get balanceKes {
    final remaining = amountDueKes - totalConfirmedKes;
    return remaining > 0 ? remaining : 0;
  }

  int get creditKes {
    final credit = totalConfirmedKes - amountDueKes;
    return credit > 0 ? credit : 0;
  }

  double get paidFraction {
    if (amountDueKes == 0) return 1;
    final fraction = totalConfirmedKes / amountDueKes;
    return fraction.clamp(0.0, 1.0);
  }

  RentInvoiceState get state {
    if (creditKes > 0) return RentInvoiceState.overpaid;
    if (balanceKes == 0) return RentInvoiceState.paid;
    if (totalConfirmedKes > 0) return RentInvoiceState.partiallyPaid;
    return RentInvoiceState.unpaid;
  }
}
