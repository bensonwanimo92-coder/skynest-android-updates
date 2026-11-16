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
  final _shortcode = TextEditingController();
  final _till = TextEditingController();
  final _consumerKey = TextEditingController();
  final _consumerSecret = TextEditingController();
  final _passkey = TextEditingController();
  final _phone = TextEditingController();
  String _type = 'paybill';
  String _status = 'not_configured';
  String _maskedAccount = '';
  String _environment = 'sandbox';
  bool _loading = true;
  bool _saving = false;
  bool _verifying = false;
  bool _obscureSecrets = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _businessName.dispose();
    _shortcode.dispose();
    _till.dispose();
    _consumerKey.dispose();
    _consumerSecret.dispose();
    _passkey.dispose();
    _phone.dispose();
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
        _maskedAccount = data['maskedAccount']?.toString() ?? '';
        _environment = data['environment']?.toString() ?? 'sandbox';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message(e.toString());
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await SkyNestMpesaService.saveLandlordAccount(
        accountType: _type,
        registeredBusinessName: _businessName.text.trim(),
        businessShortCode: _shortcode.text.trim(),
        tillNumber: _type == 'till' ? _till.text.trim() : '',
        consumerKey: _consumerKey.text.trim(),
        consumerSecret: _consumerSecret.text.trim(),
        passkey: _passkey.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _status = result['status']?.toString() ?? 'pending_verification';
        final accountNumber = (_type == 'till' ? _till.text : _shortcode.text).trim();
        _maskedAccount = accountNumber.length <= 4 ? '••••' : '••••' + accountNumber.substring(accountNumber.length - 4);
        _consumerKey.clear();
        _consumerSecret.clear();
        _passkey.clear();
      });
      _message('Account details encrypted and saved. Complete the KES 1 verification next.');
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verify() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      _message('Enter the landlord’s Safaricom M-Pesa number for the verification prompt.');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify receiving account'),
        content: const Text('SkyNest will send a KES 1 STK Push to your phone. Approve it with your M-Pesa PIN. This is a real KES 1 payment to the configured PayBill/Till, but it will not be recorded as rent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('SEND KES 1 PROMPT')),
        ],
      ),
    );
    if (approved != true) return;
    setState(() => _verifying = true);
    try {
      final result = await SkyNestMpesaService.verifyLandlordAccount(phone);
      if (!mounted) return;
      _message(result['message']?.toString() ?? 'Check your phone and approve the KES 1 prompt.');
      await _load();
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Color get _statusColor => _status == 'verified' ? Colors.green :
      _status == 'pending_verification' ? Colors.orange : Colors.blueGrey;

  String get _statusLabel => switch (_status) {
    'verified' => 'Verified',
    'pending_verification' => 'Pending verification',
    'not_configured' => 'Not configured',
    _ => _status.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('M-Pesa receiving account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.account_balance_wallet_outlined, color: Colors.blue),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Landlord payment destination', style: TextStyle(fontWeight: FontWeight.bold))),
                        Chip(label: Text(_statusLabel), backgroundColor: _statusColor.withOpacity(.13), side: BorderSide(color: _statusColor)),
                      ]),
                      const SizedBox(height: 8),
                      Text(_maskedAccount.isEmpty ? 'No receiving account saved yet.' : 'Saved account • $_maskedAccount'),
                      Text('Environment: $_environment', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      const Text('Tenant rent payments will be routed to this landlord’s own merchant account. Credentials are encrypted by the server and are never returned to this app.'),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    TextFormField(controller: _businessName, validator: _required, decoration: const InputDecoration(labelText: 'Registered business name', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextFormField(controller: _shortcode, validator: _required, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _type == 'paybill' ? 'PayBill / Daraja shortcode' : 'Daraja head-office shortcode', border: const OutlineInputBorder())),
                    if (_type == 'till') ...[
                      const SizedBox(height: 12),
                      TextFormField(controller: _till, validator: _required, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buy Goods Till number', border: OutlineInputBorder())),
                    ],
                    const SizedBox(height: 16),
                    Text('Daraja API credentials', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Use the credentials issued for this merchant in Safaricom Daraja. Never paste them into chat or share them with tenants.'),
                    const SizedBox(height: 10),
                    TextFormField(controller: _consumerKey, validator: _required, decoration: const InputDecoration(labelText: 'Consumer Key', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextFormField(controller: _consumerSecret, validator: _required, obscureText: _obscureSecrets, decoration: const InputDecoration(labelText: 'Consumer Secret', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextFormField(controller: _passkey, validator: _required, obscureText: _obscureSecrets, decoration: const InputDecoration(labelText: 'Lipa Na M-Pesa Passkey', border: OutlineInputBorder())),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _obscureSecrets = !_obscureSecrets),
                        icon: Icon(_obscureSecrets ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        label: Text(_obscureSecrets ? 'Show credential fields' : 'Hide credential fields'),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline),
                      label: Text(_saving ? 'Saving securely…' : 'Save receiving account securely'),
                    ),
                  ]),
                ),
                const Divider(height: 36),
                Text('Verify ownership', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('A KES 1 STK Push confirms that the saved merchant credentials can receive payments. The prompt goes to the landlord’s own M-Pesa phone.'),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Landlord verification phone', hintText: '07XXXXXXXX or 2547XXXXXXXX', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _verifying || _saving ? null : _verify,
                  icon: _verifying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
                  label: Text(_verifying ? 'Sending verification…' : 'Verify with KES 1 STK Push'),
                ),
                const SizedBox(height: 16),
                const Text('Important: production payments remain unavailable until the landlord has Safaricom-approved live Daraja credentials and the verification payment succeeds in the production environment.'),
              ],
            ),
    );
  }
}
