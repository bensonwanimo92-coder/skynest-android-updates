import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

const brand = Color(0xFF1565C0);
const testBanner = 'ca-app-pub-3940256099942544/6300978111';
bool firebaseReady = false;
String? firebaseError;
final currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 2);
final dateFormat = DateFormat('dd MMM yyyy');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is required by the authentication and rental-management screens.
  // Keep startup resilient so a Firebase configuration issue is visible in-app.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e, stackTrace) {
    firebaseError = e.toString();
    debugPrint('SkyNest Firebase initialization failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  // Render the first screen before initializing optional advertising services.
  // A native ads SDK startup issue must not prevent the login screen from opening.
  runApp(const SkynestApp());
  unawaited(_initializeAds());
}

Future<void> _initializeAds() async {
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint('SkyNest Mobile Ads initialization failed safely: $e');
  }
}

class ThemeManager extends ChangeNotifier {
  ThemeData value = Themes.blue;
  void set(ThemeData theme) { value = theme; notifyListeners(); }
}
final themeManager = ThemeManager();

class Themes {
  static final blue = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: brand), useMaterial3: true);
  static final dark = ThemeData.dark(useMaterial3: true);
  static final sunset = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange), useMaterial3: true);
  static final forest = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green), useMaterial3: true);
}

class SkynestApp extends StatelessWidget {
  const SkynestApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: themeManager,
    builder: (_, __) => MaterialApp(title: 'SkyNest', debugShowCheckedModeBanner: false, theme: themeManager.value, home: const LoginScreen()),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false, obscure = true;
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  void message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  Future<void> signIn({bool create = false}) async {
    if (busy) return;
    if (!firebaseReady) {
      message('Firebase is not configured. Please check the Firebase Android configuration.');
      return;
    }
    final emailAddress = email.text.trim();
    if (emailAddress.isEmpty || password.text.isEmpty) {
      message('Enter your email and password.');
      return;
    }

    setState(() => busy = true);
    try {
      final auth = FirebaseAuth.instance;
      if (create) {
        await auth.createUserWithEmailAndPassword(
          email: emailAddress,
          password: password.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: emailAddress,
          password: password.text,
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
      );
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('SkyNest Firebase Auth error [${e.code}]: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);
      message(_authErrorMessage(e));
    } catch (e, stackTrace) {
      debugPrint('SkyNest sign-in failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      final details = e.toString();
      if (details.contains('PigeonUserDetails') ||
          details.contains('List<Object?>')) {
        message('Firebase sign-in plugin error. Please update SkyNest and try again.');
      } else {
        message('Login failed. Please check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase Authentication.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }
  Future<void> resetPassword() async {
    if (!firebaseReady) { message('Firebase is not configured yet.'); return; }
    if (email.text.trim().isEmpty) { message('Enter your email first.'); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      message('Password reset email sent.');
    } on FirebaseAuthException catch (e) { message(e.message ?? e.code); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.apartment_rounded, size: 78, color: brand),
          const SizedBox(height: 8),
          const Text('SKYNEST PREMIUM', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const Text('Rental management made simpler', textAlign: TextAlign.center),
          const SizedBox(height: 30),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)), border: const OutlineInputBorder())),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: resetPassword, child: const Text('Forgot password?'))),
          FilledButton(onPressed: busy ? null : () => signIn(), child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('LOGIN')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: busy ? null : () => signIn(create: true), child: const Text('CREATE ACCOUNT')),
          if (!firebaseReady) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text('Firebase setup is required before login works.\n' + (firebaseError ?? '')))),
        ],
      )),
    ))),
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  BannerAd? banner;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    if (firebaseReady) {
      banner = BannerAd(adUnitId: testBanner, size: AdSize.banner, request: const AdRequest(), listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => loaded = true); },
        onAdFailedToLoad: (ad, _) { ad.dispose(); banner = null; },
      ))..load();
    }
  }
  @override
  void dispose() { banner?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      _MenuItem('Houses', Icons.home_work_outlined, Colors.orange, const HousesScreen()),
      _MenuItem('Tenants', Icons.people_alt_outlined, Colors.green, const TenantsScreen()),
      _MenuItem('Payments', Icons.payments_outlined, Colors.blue, const PaymentsScreen()),
      _MenuItem('Pay rent', Icons.phone_android, Colors.teal, const TenantPayScreen()),
      _MenuItem('Calculator', Icons.calculate_outlined, Colors.purple, const CalculatorScreen()),
      _MenuItem('Calendar', Icons.calendar_month, Colors.cyan, const CalendarScreen()),
      _MenuItem('Plans', Icons.assignment_outlined, Colors.indigo, const PlansScreen()),
      _MenuItem('Achievements', Icons.emoji_events_outlined, Colors.amber, const AchievementsScreen()),
      _MenuItem('Pamphlets', Icons.menu_book_outlined, Colors.brown, const PamphletsScreen()),
      _MenuItem('Themes', Icons.palette_outlined, Colors.pink, const ThemesScreen()),
      _MenuItem('Premium', Icons.workspace_premium, Colors.deepOrange, const PremiumScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('SkyNest Dashboard'), actions: [
        IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () async {
          if (firebaseReady) await FirebaseAuth.instance.signOut();
          if (!context.mounted) return;
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
        }),
      ]),
      body: GridView.builder(
        padding: const EdgeInsets.all(14), itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.12, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          return Card(clipBehavior: Clip.antiAlias, child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => item.page)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(item.icon, size: 42, color: item.color), const SizedBox(height: 10),
              Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ));
        },
      ),
      bottomNavigationBar: loaded && banner != null ? SizedBox(height: banner!.size.height.toDouble(), child: AdWidget(ad: banner!)) : null,
    );
  }
}
class _MenuItem {
  final String title; final IconData icon; final Color color; final Widget page;
  const _MenuItem(this.title, this.icon, this.color, this.page);
}

class HousesScreen extends StatelessWidget {
  const HousesScreen({super.key});
  Future<void> addHouse(BuildContext context) async {
    final number = TextEditingController(), rent = TextEditingController();
    final key = GlobalKey<FormState>();
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Add house'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: number, decoration: const InputDecoration(labelText: 'House number'), validator: requiredField),
        TextFormField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly rent (KSh)'), validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid amount' : null),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (!key.currentState!.validate()) return;
          try {
            await FirebaseFirestore.instance.collection('houses').add({'houseNo': number.text.trim(), 'rent': double.parse(rent.text), 'isOccupied': false, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid});
            if (d.mounted) Navigator.pop(d);
          } catch (e) { snack(context, 'Could not save house: ' + e.toString()); }
        }, child: const Text('Save')),
      ],
    ));
    number.dispose(); rent.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Houses')),
    floatingActionButton: FloatingActionButton(onPressed: () => addHouse(context), child: const Icon(Icons.add)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Houses could not load: ' + s.error.toString());
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const EmptyView('No houses added yet.');
        return ListView(children: s.data!.docs.map((doc) {
          final d = doc.data();
          final rentValue = (d['rent'] as num?)?.toDouble() ?? 0;
          final occupancy = d['isOccupied'] == true ? 'Occupied' : 'Vacant';
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
            title: Text('House ' + (d['houseNo']?.toString() ?? '')),
            subtitle: Text(currency.format(rentValue) + ' / month • ' + occupancy),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => confirmDelete(context, 'Delete this house?', () => doc.reference.delete())),
          ));
        }).toList());
      },
    ),
  );
}

class TenantsScreen extends StatelessWidget {
  const TenantsScreen({super.key});
  Future<void> addTenant(BuildContext context) async {
    final name = TextEditingController(), phone = TextEditingController(), house = TextEditingController(), rent = TextEditingController();
    final key = GlobalKey<FormState>();
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Add tenant'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: requiredField),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number'), validator: requiredField),
        TextFormField(controller: house, decoration: const InputDecoration(labelText: 'House number'), validator: requiredField),
        TextFormField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly rent (KSh)'), validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid amount' : null),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (!key.currentState!.validate()) return;
          try {
            await FirebaseFirestore.instance.collection('tenants').add({'name': name.text.trim(), 'phone': phone.text.trim(), 'houseNo': house.text.trim(), 'rentAmount': double.parse(rent.text), 'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid});
            if (d.mounted) Navigator.pop(d);
          } catch (e) { snack(context, 'Could not save tenant: ' + e.toString()); }
        }, child: const Text('Save tenant')),
      ],
    ));
    name.dispose(); phone.dispose(); house.dispose(); rent.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tenants')),
    floatingActionButton: FloatingActionButton(onPressed: () => addTenant(context), child: const Icon(Icons.person_add_alt_1)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('tenants').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Tenants could not load: ' + s.error.toString());
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const EmptyView('No tenants added yet.');
        return ListView(children: s.data!.docs.map((doc) {
          final d = doc.data();
          final rentValue = (d['rentAmount'] as num?)?.toDouble() ?? 0;
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(d['name']?.toString() ?? 'Tenant'),
            subtitle: Text('House ' + (d['houseNo']?.toString() ?? '-') + ' • ' + (d['phone']?.toString() ?? '-') + '\n' + currency.format(rentValue) + ' / month'),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.person_remove_alt_1, color: Colors.red), onPressed: () => confirmDelete(context, 'Remove ' + (d['name']?.toString() ?? 'this tenant') + '? Payment records will remain.', () => doc.reference.delete())),
          ));
        }).toList());
      },
    ),
  );
}

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment records')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Payments could not load: ' + s.error.toString());
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const EmptyView('No payment records yet.');
        return ListView(children: s.data!.docs.map((doc) {
          final d = doc.data();
          final value = (d['amount'] as num?)?.toDouble() ?? 0;
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
            title: Text(d['tenantName']?.toString() ?? 'Tenant'),
            subtitle: Text((d['houseNo']?.toString() ?? 'House not set') + ' • ' + (d['method']?.toString() ?? 'Manual') + '\n' + (d['status']?.toString() ?? 'Pending verification')),
            isThreeLine: true,
            trailing: Text(currency.format(value), style: const TextStyle(fontWeight: FontWeight.bold)),
          );
        }).toList());
      },
    ),
  );
}

class TenantPayScreen extends StatefulWidget {
  const TenantPayScreen({super.key});
  @override
  State<TenantPayScreen> createState() => _TenantPayScreenState();
}
class _TenantPayScreenState extends State<TenantPayScreen> {
  final tenant = TextEditingController(), house = TextEditingController(), amount = TextEditingController();
  bool saving = false;
  @override
  void dispose() { tenant.dispose(); house.dispose(); amount.dispose(); super.dispose(); }
  Future<void> savePayment() async {
    final value = double.tryParse(amount.text.trim());
    if (tenant.text.trim().isEmpty || value == null || value <= 0) { snack(context, 'Enter tenant name and a valid amount.'); return; }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('payments').add({
        'tenantName': tenant.text.trim(), 'houseNo': house.text.trim(), 'amount': value,
        'method': 'Manual / awaiting M-Pesa confirmation', 'status': 'Pending verification',
        'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (mounted) { amount.clear(); snack(context, 'Saved as pending verification. No M-Pesa STK Push was sent.'); }
    } catch (e) { snack(context, 'Could not save: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record rent payment')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.phone_android, size: 56, color: Colors.green),
      const Text('Record a rent payment', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      TextField(controller: tenant, decoration: const InputDecoration(labelText: 'Tenant name', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: house, decoration: const InputDecoration(labelText: 'House number', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (KSh)', border: OutlineInputBorder())),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: saving ? null : savePayment, icon: const Icon(Icons.save_outlined), label: Text(saving ? 'Saving...' : 'SAVE PAYMENT RECORD')),
      const SizedBox(height: 12),
      const Text('This records a payment for verification only. It does not send an M-Pesa STK Push or confirm money received. Live Daraja payments require credentials and a secure backend server.'),
    ]),
  );
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}
class _CalculatorScreenState extends State<CalculatorScreen> {
  final rent = TextEditingController(text: '10000'), months = TextEditingController(text: '12');
  double total = 120000;
  void calculate() => setState(() => total = (double.tryParse(rent.text) ?? 0) * (int.tryParse(months.text) ?? 0));
  @override
  void dispose() { rent.dispose(); months.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rent calculator')),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly rent (KSh)', border: OutlineInputBorder()), onChanged: (_) => calculate()),
      const SizedBox(height: 14),
      TextField(controller: months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of months', border: OutlineInputBorder()), onChanged: (_) => calculate()),
      const SizedBox(height: 28),
      Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
        const Text('Total rent'), const SizedBox(height: 8),
        Text(currency.format(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      ]))),
    ])),
  );
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}
class _CalendarScreenState extends State<CalendarScreen> {
  DateTime focused = DateTime.now();
  DateTime? selected;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rent calendar')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Calendar could not load: ' + s.error.toString());
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final events = <DateTime, List<Map<String, dynamic>>>{};
        for (final doc in s.data!.docs) {
          final data = doc.data();
          final raw = data['createdAt'];
          DateTime? day;
          if (raw is Timestamp) day = raw.toDate();
          if (day == null && data['date'] is String) day = DateTime.tryParse(data['date']);
          if (day != null) {
            final key = DateTime(day.year, day.month, day.day);
            events.putIfAbsent(key, () => []).add(data);
          }
        }
        final chosen = selected ?? DateTime(focused.year, focused.month, focused.day);
        final selectedEvents = events[DateTime(chosen.year, chosen.month, chosen.day)] ?? [];
        return ListView(padding: const EdgeInsets.all(12), children: [
          TableCalendar<Map<String, dynamic>>(
            firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: focused, selectedDayPredicate: (day) => isSameDay(selected, day),
            eventLoader: (day) => events[DateTime(day.year, day.month, day.day)] ?? [],
            onDaySelected: (day, focus) => setState(() { selected = day; focused = focus; }),
            onPageChanged: (day) => focused = day,
          ),
          const SizedBox(height: 14),
          Text('Records for ' + dateFormat.format(chosen), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (selectedEvents.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No payment records for this date.')),
          ...selectedEvents.map((e) => ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text(e['tenantName']?.toString() ?? 'Tenant'),
            subtitle: Text(e['status']?.toString() ?? 'Pending verification'),
            trailing: Text(currency.format((e['amount'] as num?)?.toDouble() ?? 0)),
          )),
        ]);
      },
    ),
  );
}

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});
  Future<void> addPlan(BuildContext context) async {
    final title = TextEditingController(), note = TextEditingController();
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Add reminder'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Notes')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (title.text.trim().isEmpty) return;
          await FirebaseFirestore.instance.collection('plans').add({'title': title.text.trim(), 'note': note.text.trim(), 'done': false, 'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid});
          if (d.mounted) Navigator.pop(d);
        }, child: const Text('Save')),
      ],
    ));
    title.dispose(); note.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plans and reminders')),
    floatingActionButton: FloatingActionButton(onPressed: () => addPlan(context), child: const Icon(Icons.add)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('plans').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Plans could not load: ' + s.error.toString());
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.docs.isEmpty) return const EmptyView('No reminders yet. Tap + to add one.');
        return ListView(children: s.data!.docs.map((doc) {
          final d = doc.data();
          return CheckboxListTile(value: d['done'] == true, title: Text(d['title']?.toString() ?? ''), subtitle: Text(d['note']?.toString() ?? ''), onChanged: (v) => doc.reference.update({'done': v == true}));
        }).toList());
      },
    ),
  );
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Achievements')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
      builder: (context, h) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tenants').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
        builder: (context, t) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
          builder: (context, p) {
            if (h.hasError || t.hasError || p.hasError) return errorView('Could not load achievement counts.');
            if (!h.hasData || !t.hasData || !p.hasData) return const Center(child: CircularProgressIndicator());
            final stats = <(String, int, IconData)>[
              ('Houses registered', h.data!.size, Icons.home_work),
              ('Tenants registered', t.data!.size, Icons.people),
              ('Payment records', p.data!.size, Icons.receipt_long),
            ];
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Your property management progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...stats.map((x) => Card(child: ListTile(leading: Icon(x.$3, color: brand, size: 32), title: Text(x.$1), trailing: Text(x.$2.toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))))),
            ]);
          },
        ),
      ),
    ),
  );
}

class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final themes = <(String, ThemeData, IconData)>[
      ('Flashy Blue', Themes.blue, Icons.water_drop),
      ('Flashy Dark', Themes.dark, Icons.dark_mode),
      ('Sunset Orange', Themes.sunset, Icons.wb_sunny),
      ('Forest Green', Themes.forest, Icons.forest),
    ];
    return Scaffold(appBar: AppBar(title: const Text('Free themes')), body: ListView(children: themes.map((x) => ListTile(
      leading: Icon(x.$3), title: Text(x.$1), trailing: const Icon(Icons.chevron_right),
      onTap: () { themeManager.set(x.$2); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(x.$1 + ' theme applied.'))); },
    )).toList()));
  }
}

class PamphletsScreen extends StatelessWidget {
  const PamphletsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Being a responsible landlord', 'Keep clear rent records, respond to maintenance requests, communicate respectfully, and follow the written tenancy agreement and applicable Kenyan law.'),
      ('Tenant responsibilities', 'Pay rent as agreed, take reasonable care of the property, report repair issues promptly, and keep copies of important communications and receipts.'),
      ('Keeping payment records', 'Record the amount, date, tenant, house number and payment reference. Confirm money has reached the correct account before marking a payment as received.'),
      ('Planning property maintenance', 'Inspect shared facilities regularly, keep a maintenance log, prioritise urgent safety repairs, and inform tenants about planned work.'),
    ];
    return Scaffold(appBar: AppBar(title: const Text('Pamphlets and guidance')), body: ListView(children: items.map((x) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(leading: const Icon(Icons.menu_book_outlined), title: Text(x.$1), children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: Text(x.$2))]),
    )).toList()));
  }
}

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Scaffold(appBar: AppBar(title: const Text('Premium')), body: const EmptyView('Sign in to view subscription status.'));
    return Scaffold(appBar: AppBar(title: const Text('SkyNest Premium')), body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('subscriptions').doc(uid).snapshots(),
      builder: (context, s) {
        if (s.hasError) return errorView('Subscription status could not load.');
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final active = s.data!.data()?['isPremium'] == true;
        return Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.workspace_premium, size: 76, color: Colors.amber),
          const SizedBox(height: 12),
          Text(active ? 'PREMIUM ACTIVE' : 'Unlock Premium', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          const Text('Premium may include an ad-free experience, extended reports and priority support.'),
          const SizedBox(height: 12),
          const Card(child: ListTile(leading: Icon(Icons.support_agent), title: Text('Premium support'), subtitle: Text('0746941942'))),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(active ? 'Your account is marked as Premium.' : 'Premium activation requires verified payment and administrator approval. Subscription payment is not yet connected in this build.'))),
        ]));
      },
    ));
  }
}

class EmptyView extends StatelessWidget {
  final String text;
  const EmptyView(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
}
Widget errorView(String text) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
String? requiredField(String? value) => value == null || value.trim().isEmpty ? 'This field is required' : null;
void snack(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<void> confirmDelete(BuildContext context, String prompt, Future<void> Function() action) async {
  final yes = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
    title: const Text('Please confirm'), content: Text(prompt),
    actions: [
      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirm')),
    ],
  ));
  if (yes == true) {
    try { await action(); if (context.mounted) snack(context, 'Record removed.'); }
    catch (e) { if (context.mounted) snack(context, 'Could not remove record: ' + e.toString()); }
  }
}
