import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'mpesa_service.dart';

class MpesaRentPaymentScreen extends StatefulWidget {
  const MpesaRentPaymentScreen({super.key});
  @override
  State<MpesaRentPaymentScreen> createState() => _MpesaRentPaymentScreenState();
}

class _MpesaRentPaymentScreenState extends State<MpesaRentPaymentScreen> {
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  final _receipt = TextEditingController();
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _recipient;
  String? _houseId;
  String _houseNo = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _amount.dispose(); _phone.dispose(); _receipt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in again to continue.');
      final profileSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final profile = profileSnap.data() ?? <String, dynamic>{};
      final role = profile['role']?.toString();
      if (role != 'tenant' && role != 'caretaker') {
        throw StateError('This payment page is available to tenants and caretakers.');
      }
      String? houseId = profile['rentHouseId']?.toString();
      if (houseId == null || houseId.isEmpty) houseId = profile['houseId']?.toString();
      // Caretakers must have an explicit rent-house assignment; never guess
      // that the first managed property is the house where they personally rent.
      if (houseId == null || houseId.isEmpty) {
        throw StateError(role == 'caretaker'
          ? 'Your landlord must assign the house you rent to your caretaker profile before you can submit rent.'
          : 'Your account has no assigned house. Contact your landlord.');
      }
      final houseSnap = await FirebaseFirestore.instance.collection('houses').doc(houseId).get();
      if (!houseSnap.exists) throw StateError('Your linked house record could not be found.');
      final house = houseSnap.data() ?? <String, dynamic>{};
      if (role == 'tenant' && house['assignedTenantId'] != uid) {
        throw StateError('Your tenant-to-house assignment could not be verified.');
      }
      if (role == 'caretaker' && house['assignedTenantId'] != uid) {
        throw StateError('Your landlord must link your caretaker profile to the house you personally rent before you can submit rent.');
      }

      final recipient = await SkyNestMpesaService.getPaymentRecipient(houseId: houseId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _houseId = houseId;
        _houseNo = (house['houseNo'] ?? profile['houseNo'] ?? '').toString();
        _recipient = recipient;
        _phone.text = (profile['phone'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    final code = _receipt.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (amount == null || amount <= 0) {
      _message('Enter a valid rent amount.');
      return;
    }
    if (code.length < 8 || code.length > 16) {
      _message('Enter the M-Pesa receipt code from your confirmation message.');
      return;
    }
    final payerPhone = _phone.text.trim();
    if (payerPhone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      _message('Enter the phone number used to make this M-Pesa payment.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final profile = _profile;
    if (uid == null || profile == null || _houseId == null) return;
    setState(() => _saving = true);
    try {
      final landlordId = profile['landlordId']?.toString() ?? '';
      if (landlordId.isEmpty) throw StateError('Your account is not linked to a landlord.');
      final batch = FirebaseFirestore.instance.batch();
      final submission = FirebaseFirestore.instance.collection('paymentSubmissions').doc();
      batch.set(submission, {
        'tenantId': uid,
        'tenantName': (profile['displayName'] ?? 'Payer').toString(),
        'landlordId': landlordId,
        'houseId': _houseId,
        'houseNo': _houseNo,
        'amount': amount,
        'method': 'MPESA',
        'transactionCode': code,
        'payerPhone': payerPhone,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      final codeRef = FirebaseFirestore.instance.collection('mpesaTransactionCodes').doc(code);
      batch.set(codeRef, {
        'tenantId': uid,
        'landlordId': landlordId,
        'submissionId': submission.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _amount.clear();
      _receipt.clear();
      _message('Payment receipt submitted to your landlord for verification.');
    } catch (e) {
      _message('Could not submit payment receipt: ${e.toString().replaceFirst('Bad state: ', '')}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pay rent with M-Pesa')),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _recipient == null
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('M-Pesa recipient details are not available yet. Ask your landlord to add a PayBill or Till number.')))
        : ListView(padding: const EdgeInsets.all(18), children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PAYMENT RECIPIENT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
                const SizedBox(height: 12),
                Text(_recipient!['registeredBusinessName']?.toString() ?? '',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text((_recipient!['accountType']?.toString() == 'till') ? 'Buy Goods Till' : 'PayBill'),
                SelectableText(_recipient!['accountNumber']?.toString() ?? '',
                  style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: 1)),
                if ((_recipient!['accountType']?.toString() ?? 'paybill') == 'paybill') ...[
                  const SizedBox(height: 5),
                  Text('Account/reference: House $_houseNo'),
                ],
              ],
            ))),
            const SizedBox(height: 14),
            const Text('HOW TO PAY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
            const SizedBox(height: 8),
            if ((_recipient!['accountType']?.toString() ?? 'paybill') == 'paybill') ...[
              const ListTile(leading: CircleAvatar(child: Text('1')), title: Text('Open M-Pesa and select Lipa na M-Pesa.')),
              const ListTile(leading: CircleAvatar(child: Text('2')), title: Text('Choose PayBill and enter the recipient number above.')),
              const ListTile(leading: CircleAvatar(child: Text('3')), title: Text('Enter your house number as the account/reference.')),
              const ListTile(leading: CircleAvatar(child: Text('4')), title: Text('Enter the rent amount and confirm using your M-Pesa PIN.')),
            ] else ...[
              const ListTile(leading: CircleAvatar(child: Text('1')), title: Text('Open M-Pesa and select Lipa na M-Pesa.')),
              const ListTile(leading: CircleAvatar(child: Text('2')), title: Text('Choose Buy Goods and Services and enter the Till number above.')),
              const ListTile(leading: CircleAvatar(child: Text('3')), title: Text('Enter the rent amount and confirm using your M-Pesa PIN.')),
            ],
            const Divider(height: 28),
            const Text('SUBMIT YOUR M-PESA RECEIPT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .7)),
            const SizedBox(height: 8),
            TextField(controller: _amount, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount paid (KSh)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'M-Pesa phone number', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _receipt, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'M-Pesa receipt code', hintText: 'e.g. QHX...', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.receipt_long),
              label: Text(_saving ? 'Submitting…' : 'SUBMIT PAYMENT RECEIPT'),
            ),
            const SizedBox(height: 8),
            const Text('Your landlord verifies the receipt before the payment is added to your rent ledger. Never share your M-Pesa PIN or OTP with anyone.'),
          ]),
  );
}
