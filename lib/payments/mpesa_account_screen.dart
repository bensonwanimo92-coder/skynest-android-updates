import 'package:flutter/material.dart';
import 'mpesa_service.dart';

class MpesaAccountScreen extends StatefulWidget {
  const MpesaAccountScreen({super.key});

  @override
  State<MpesaAccountScreen> createState() => _MpesaAccountScreenState();
}

class _MpesaAccountScreenState extends State<MpesaAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shortcode = TextEditingController();
  final _till = TextEditingController();
  final _phone = TextEditingController();
  String _type = 'paybill';
  String _status = 'not_configured';
  String _maskedAccount = '';
  String _environment = 'sandbox';
  bool _loading = true;
  bool _saving = false;
  bool _verifying = false;
  bool _routingEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shortcode.dispose();
    _till.dispose();
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
        _maskedAccount = data['maskedAccount']?.toString() ?? '';
        _environment = data['environment']?.toString() ?? 'production';
        _routingEnabled = data['routingEnabled'] == true;
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
        businessShortCode: _shortcode.text.trim(),
        tillNumber: _type == 'till' ? _till.text.trim() : '',
      );
      if (!mounted) return;
      setState(() {
        _status = result['status']?.toString() ?? 'pending_verification';
        final accountNumber = (_type == 'till' ? _till.text : _shortcode.text).trim();
        _maskedAccount = accountNumber.length <= 4 ? '••••' : '••••' + accountNumber.substring(accountNumber.length - 4);
      });
      _message('Receiving account details saved. Verification is available after SkyNest merchant routing is enabled.');
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
      appBar: AppBar(
        title: const Text('M-Pesa receiving account'),
        actions: [IconButton(tooltip: 'Refresh verification status', onPressed: _loading ? null : () { setState(() => _loading = true); _load(); }, icon: const Icon(Icons.refresh))],
      ),
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
                      const Text('SkyNest manages one central Daraja integration. Enter only the PayBill or Buy Goods Till where you receive rent.'),
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
                    if (_type == 'paybill') ...[
                      TextFormField(controller: _shortcode, validator: _required, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your PayBill number', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                    ],
                    if (_type == 'till') ...[
                      const SizedBox(height: 12),
                      TextFormField(controller: _till, validator: _required, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buy Goods Till number', border: OutlineInputBorder())),
                    ],
                    const SizedBox(height: 8),
                    const Text('Daraja API credentials are managed centrally by SkyNest and are never requested from landlords.'),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline),
                      label: Text(_saving ? 'Saving securely…' : 'Save receiving account securely'),
                    ),
                  ]),
                ),
                const Divider(height: 36),
                Text('Verify merchant connection', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('Verification will become available after Safaricom enables the central SkyNest merchant-routing arrangement. Saving these details does not send a payment.'),
                const SizedBox(height: 12),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Landlord verification phone', hintText: '07XXXXXXXX or 2547XXXXXXXX', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _verifying || _saving || !_routingEnabled ? null : _verify,
                  icon: _verifying ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
                  label: Text(!_routingEnabled ? 'Safaricom routing approval required' : (_verifying ? 'Sending verification…' : 'Verify with KES 1 STK Push')),
                ),
                const SizedBox(height: 16),
                const Text('Direct settlement remains locked until Safaricom approves and enables SkyNest central merchant routing. No payment is sent while that approval is missing.'),
              ],
            ),
    );
  }
}
