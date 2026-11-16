import 'package:flutter/material.dart';
import 'mpesa_service.dart';

class MpesaAccountScreen extends StatefulWidget {
  const MpesaAccountScreen({super.key});
  @override
  State<MpesaAccountScreen> createState() => _MpesaAccountScreenState();
}

class _MpesaAccountScreenState extends State<MpesaAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _accountNumber = TextEditingController();
  String _type = 'paybill';
  String _status = 'not_configured';
  String _maskedAccount = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _businessName.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await SkyNestMpesaService.getLandlordAccount();
      if (!mounted) return;
      setState(() {
        _status = data['status']?.toString() ?? 'not_configured';
        _type = data['accountType']?.toString() ?? 'paybill';
        _businessName.text = data['registeredBusinessName']?.toString() ?? '';
        _accountNumber.text = data['accountNumber']?.toString() ?? '';
        _maskedAccount = data['maskedAccount']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message(e.toString());
    }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await SkyNestMpesaService.saveLandlordAccount(
        accountType: _type,
        registeredBusinessName: _businessName.text.trim(),
        accountNumber: _accountNumber.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _status = result['status']?.toString() ?? 'configured';
        _maskedAccount = _accountNumber.text.trim();
        if (_maskedAccount.length > 4) _maskedAccount = '••••${_maskedAccount.substring(_maskedAccount.length - 4)}';
      });
      _message('M-Pesa recipient details saved. Tenants and assigned caretakers can now view the payment instructions.');
    } catch (e) {
      _message(e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('M-Pesa receiving account')),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(18), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.account_balance_wallet_outlined, color: Colors.green),
                SizedBox(width: 10),
                Expanded(child: Text('Your rent payment recipient', style: TextStyle(fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 10),
              Text(_maskedAccount.isEmpty ? 'No recipient details saved.' : 'Saved account • $_maskedAccount'),
              const SizedBox(height: 6),
              Text('Status: ${_status.replaceAll('_', ' ')}'),
              const SizedBox(height: 8),
              const Text('Enter the PayBill or Buy Goods Till details that tenants should use when paying rent. Do not enter Daraja API keys or passwords here.'),
            ],
          ))),
          const SizedBox(height: 16),
          Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Receiving account type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'paybill', child: Text('PayBill')),
                DropdownMenuItem(value: 'till', child: Text('Buy Goods Till')),
              ],
              onChanged: _saving ? null : (value) => setState(() => _type = value ?? 'paybill'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _businessName,
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter the registered business name.' : null,
              decoration: const InputDecoration(labelText: 'Registered business name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accountNumber,
              keyboardType: TextInputType.number,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Enter the ${_type == 'paybill' ? 'PayBill' : 'Till'} number.';
                if (!RegExp(r'^\d{5,20}.hasMatch(value)) return 'Enter a valid account number.';
                return null;
              },
              decoration: InputDecoration(
                labelText: _type == 'paybill' ? 'PayBill number' : 'Buy Goods Till number',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'SAVE PAYMENT DETAILS'),
            ),
          ])),
          const SizedBox(height: 14),
          const Text('Note: Saving these details publishes the recipient instructions inside the linked tenant and caretaker payment screens. Automatic STK Push remains subject to SkyNest’s authorised Daraja merchant integration.'),
        ]),
  );
}
).hasMatch(value)) return 'Enter a valid account number.';
                return null;
              },
              decoration: InputDecoration(
                labelText: _type == 'paybill' ? 'PayBill number' : 'Buy Goods Till number',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'SAVE PAYMENT DETAILS'),
            ),
          ])),
          const SizedBox(height: 14),
          const Text('Note: Saving these details publishes the recipient instructions inside the linked tenant and caretaker payment screens. Automatic STK Push remains subject to SkyNest’s authorised Daraja merchant integration.'),
        ]),
  );
}
