import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:table_calendar/table_calendar.dart';

const brand = Color(0xFF1565C0);
const skynestBannerAdUnitId = 'ca-app-pub-1281241380359357/4686680349';
bool firebaseReady = false;
String? firebaseError;
final currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 2);
final dateFormat = DateFormat('dd MMM yyyy');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(); firebaseReady = true; }
  catch (e) { firebaseError = e.toString(); }
  try { await MobileAds.instance.initialize(); } catch (_) {}
  runApp(const SkynestApp());
}

class ThemeManager extends ChangeNotifier {
  ThemeData value = Themes.blue;
  String selectedName = 'Classic Blue';
  void set(ThemeData theme, String name) { value = theme; selectedName = name; notifyListeners(); }
}
final themeManager = ThemeManager();

class ThemeOption {
  final String name, description;
  final ThemeData theme;
  final Color primary, secondary;
  final IconData icon;
  const ThemeOption(this.name, this.description, this.theme, this.primary, this.secondary, this.icon);
}

class Themes {
  static final blue = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2463A6)), useMaterial3: true);
  static final dark = ThemeData(colorScheme: const ColorScheme.dark(primary: Color(0xFFC4A66A), secondary: Color(0xFF9CA3AF), surface: Color(0xFF17191D)), useMaterial3: true);
  static final sunset = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC66A45)), useMaterial3: true);
  static final forest = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF52745A)), useMaterial3: true);
  static final ivory = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB18A4A), brightness: Brightness.light, surface: const Color(0xFFFFFBF3)), scaffoldBackgroundColor: const Color(0xFFFFFBF3), useMaterial3: true);
  static final ocean = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315D83)), useMaterial3: true);
  static final rose = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9A6572)), useMaterial3: true);
  static final slate = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF64748B)), useMaterial3: true);
  static final options = <ThemeOption>[
    ThemeOption('Ivory & Gold Estate', 'Warm ivory, champagne and gold', ivory, const Color(0xFFF5EBDD), const Color(0xFFB18A4A), Icons.villa_outlined),
    ThemeOption('Midnight Luxury', 'Charcoal, black and silver', dark, const Color(0xFF17191D), const Color(0xFFC4A66A), Icons.directions_car_filled_outlined),
    ThemeOption('Ocean Residence', 'Navy blue and cool coastal tones', ocean, const Color(0xFF173B5E), const Color(0xFF78A9C9), Icons.water),
    ThemeOption('Forest Residence', 'Natural greens and soft stone', forest, const Color(0xFF294B37), const Color(0xFF9BAF8A), Icons.park_outlined),
    ThemeOption('Sunset Villa', 'Terracotta, sand and sunset gold', sunset, const Color(0xFF9D4F35), const Color(0xFFE8B878), Icons.wb_twilight),
    ThemeOption('Rosewood Classic', 'Muted rose and warm neutral shades', rose, const Color(0xFF76505B), const Color(0xFFD5AEB2), Icons.weekend_outlined),
    ThemeOption('Silver Slate', 'Clean slate, graphite and silver', slate, const Color(0xFF475569), const Color(0xFFCBD5E1), Icons.apartment_outlined),
    ThemeOption('Classic Blue', 'The familiar SkyNest blue', blue, const Color(0xFF174D83), const Color(0xFF79A9D6), Icons.home_work_outlined),
    ThemeOption('Flashy Dark', 'A simple dark appearance', dark, const Color(0xFF101114), const Color(0xFFB7B7B7), Icons.dark_mode),
  ];
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
  final confirmPassword = TextEditingController();
  final displayName = TextEditingController();
  final invitationCode = TextEditingController();
  String selectedRole = 'landlord';
  bool busy = false, obscure = true, creating = false;

  @override
  void dispose() {
    email.dispose(); password.dispose(); confirmPassword.dispose(); displayName.dispose(); invitationCode.dispose();
    super.dispose();
  }
  void message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  bool validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  String authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use': return 'This email already has an account. Please log in or reset your password.';
      case 'invalid-email': return 'That email address is not valid.';
      case 'weak-password': return 'Choose a stronger password with at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential': return 'Email or password is incorrect. You can reset your password if needed.';
      case 'network-request-failed': return 'Network error. Check your internet connection and try again.';
      case 'too-many-requests': return 'Too many attempts. Wait a little before trying again.';
      case 'operation-not-allowed': return 'Email/password sign-in is not enabled in Firebase Authentication.';
      default: return e.message ?? 'Authentication failed (' + e.code + ').';
    }
  }

  Future<void> signIn() async {
    if (!firebaseReady) { message('Firebase is not configured. Complete the Android Firebase setup first.'); return; }
    if (!validEmail(email.text)) { message('Enter a valid email address.'); return; }
    if (password.text.isEmpty) { message('Enter your password.'); return; }
    setState(() => busy = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      final user = credential.user!;
      final profile = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final profileSnapshot = await profile.get();
      if (!profileSnapshot.exists) {
        // Existing SkyNest accounts pre-date role profiles; preserve them as landlords.
        await profile.set({'displayName': user.displayName ?? user.email ?? 'Landlord',
          'email': user.email, 'role': 'landlord', 'status': 'active',
          'createdAt': FieldValue.serverTimestamp(), 'legacyAccount': true});
      }
      final latest = await profile.get();
      if (latest.data()?['status'] == 'pending') {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const PendingApprovalScreen()));
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const DashboardScreen()));
      }
    } on FirebaseAuthException catch (e) { message(authMessage(e)); }
    catch (_) { message('Login could not be completed. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> createAccount() async {
    if (!firebaseReady) { message('Firebase is not configured. Complete the Android Firebase setup first.'); return; }
    if (displayName.text.trim().length < 2) { message('Enter your full name.'); return; }
    if (!validEmail(email.text)) { message('Enter a valid email address.'); return; }
    if (password.text.length < 6) { message('Use a password with at least 6 characters.'); return; }
    if (password.text != confirmPassword.text) { message('The passwords do not match.'); return; }
    if (!['landlord', 'caretaker', 'tenant'].contains(selectedRole)) { message('Choose an account type.'); return; }
    if (selectedRole != 'landlord' && invitationCode.text.trim().length < 6) {
      message('Enter the invitation code provided by your landlord.'); return;
    }
    setState(() => busy = true);
    User? newUser;
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(), password: password.text);
      newUser = credential.user;
      await newUser?.updateDisplayName(displayName.text.trim());
      final profile = FirebaseFirestore.instance.collection('users').doc(newUser!.uid);
      if (selectedRole == 'landlord') {
        await profile.set({'displayName': displayName.text.trim(), 'email': email.text.trim(),
          'role': 'landlord', 'status': 'active', 'createdAt': FieldValue.serverTimestamp()});
      } else {
        final code = invitationCode.text.trim().toUpperCase();
        final inviteRef = FirebaseFirestore.instance.collection('invitations').doc(code);
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final inviteSnapshot = await transaction.get(inviteRef);
          if (!inviteSnapshot.exists) throw StateError('Invitation code not found.');
          final invite = inviteSnapshot.data()!;
          final expiry = invite['expiresAt'];
          if (invite['status'] != 'open' || invite['role'] != selectedRole ||
              invite['landlordId'] == null || expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now())) {
            throw StateError('This invitation is invalid, expired, already used, or for a different role.');
          }
          transaction.set(profile, {'displayName': displayName.text.trim(), 'email': email.text.trim(),
            'role': selectedRole, 'status': 'pending', 'landlordId': invite['landlordId'],
            'propertyIds': invite['propertyIds'] ?? [], 'invitationCode': code,
            'createdAt': FieldValue.serverTimestamp()});
          transaction.update(inviteRef, {'status': 'used', 'usedBy': newUser!.uid,
            'usedAt': FieldValue.serverTimestamp()});
        });
      }
      if (!mounted) return;
      if (selectedRole == 'landlord') {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const DashboardScreen()));
        message('Landlord account created successfully.');
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const PendingApprovalScreen()));
        message('Account created. Your landlord must approve your access.');
      }
    } on FirebaseAuthException catch (e) {
      message(authMessage(e));
    } catch (e) {
      // Do not leave an unusable Firebase Auth account behind if invitation validation fails.
      try { await newUser?.delete(); } catch (_) {}
      message(e is StateError ? e.message.toString() : 'Account creation could not be completed. Check your connection and try again.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> resetPassword() async {
    if (!firebaseReady) { message('Firebase is not configured yet.'); return; }
    if (!validEmail(email.text)) { message('Enter a valid email address in the Email field first.'); return; }
    setState(() => busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      message('If an account exists for this email, a password-reset link has been sent. Check your inbox and spam folder.');
    } on FirebaseAuthException catch (e) { message(authMessage(e)); }
    catch (_) { message('Could not send the reset email. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> showCreateAccount() async {
    password.clear(); confirmPassword.clear(); displayName.clear(); invitationCode.clear(); selectedRole = 'landlord';
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create your SkyNest account'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: displayName, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedRole,
            decoration: const InputDecoration(labelText: 'Account type', prefixIcon: Icon(Icons.badge_outlined)),
            items: const [
              DropdownMenuItem(value: 'landlord', child: Text('Landlord')),
              DropdownMenuItem(value: 'caretaker', child: Text('Caretaker')),
              DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
            ],
            onChanged: (value) => setDialogState(() => selectedRole = value ?? 'landlord'),
          ),
          if (selectedRole != 'landlord') ...[
            const SizedBox(height: 12),
            TextField(controller: invitationCode, textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Landlord invitation code', prefixIcon: Icon(Icons.key_outlined))),
          ],
          const SizedBox(height: 12),
          TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: obscure,
            decoration: InputDecoration(labelText: 'Password (minimum 6 characters)', prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(onPressed: () => setDialogState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)))),
          const SizedBox(height: 12),
          TextField(controller: confirmPassword, obscureText: obscure,
            decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_reset_outlined))),
        ])),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: busy ? null : () async {
            Navigator.pop(dialogContext);
            await createAccount();
          }, child: const Text('CREATE ACCOUNT')),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Column(children: [
      Expanded(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.apartment_rounded, size: 78, color: brand),
            const SizedBox(height: 8),
            const Text('SKYNEST PREMIUM', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            const Text('Rental management made simpler', textAlign: TextAlign.center),
            const SizedBox(height: 30),
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: password, obscureText: obscure, autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)), border: const OutlineInputBorder())),
            Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: busy ? null : resetPassword, child: const Text('Forgot password? Reset here'))),
            FilledButton(onPressed: busy ? null : signIn,
              child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('LOGIN')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : showCreateAccount, child: const Text('CREATE ACCOUNT')),
            if (!firebaseReady) Card(color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12),
                child: Text('Firebase setup is required before login or registration works.\n' + (firebaseError ?? '')))),
          ],
        )),
      ))),
      Padding(padding: const EdgeInsets.only(bottom: 14, top: 6),
        child: Text('Benson', style: TextStyle(color: Theme.of(context).colorScheme.primary,
          fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.0))),
    ])),
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
  String userRole = 'landlord';
  @override
  void initState() {
    super.initState();
    _loadUserRole();
    // AdMob is independent of Firebase, so load ads even if Firebase is unavailable.
    banner = BannerAd(adUnitId: skynestBannerAdUnitId, size: AdSize.banner, request: const AdRequest(), listener: BannerAdListener(
      onAdLoaded: (_) { if (mounted) setState(() => loaded = true); },
      onAdFailedToLoad: (ad, _) { ad.dispose(); banner = null; },
    ))..load();
  }
  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !firebaseReady) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) setState(() => userRole = doc.data()?['role']?.toString() ?? 'landlord');
    } catch (_) {}
  }
  @override
  void dispose() { banner?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[];
    if (userRole == 'landlord') {
      items.addAll([

        _MenuItem('Houses', Icons.home_work_outlined, Colors.orange, const HousesScreen()),
        _MenuItem('Tenants', Icons.people_alt_outlined, Colors.green, const TenantsScreen()),
        _MenuItem('Payments', Icons.payments_outlined, Colors.blue, const PaymentsScreen()),
        _MenuItem('Caretakers & invitations', Icons.badge_outlined, Colors.teal, const InvitationsScreen()),
        _MenuItem('Complaints', Icons.support_agent, Colors.deepOrange, const ComplaintsScreen()),
        _MenuItem('Tenant groups', Icons.groups_outlined, Colors.indigo, const TenantGroupsScreen()),
        _MenuItem('Notices', Icons.campaign_outlined, Colors.purple, const NoticesScreen()),
        _MenuItem('Electricity', Icons.electric_bolt, Colors.amber, const ElectricityScreen()),
        _MenuItem('Activity log', Icons.fact_check_outlined, Colors.blueGrey, const ActivityLogScreen()),
        _MenuItem('Calculator', Icons.calculate_outlined, Colors.purple, const CalculatorScreen()),
        _MenuItem('Calendar', Icons.calendar_month, Colors.cyan, const CalendarScreen()),
        _MenuItem('Plans', Icons.assignment_outlined, Colors.indigo, const PlansScreen()),
        _MenuItem('Achievements', Icons.emoji_events_outlined, Colors.amber, const AchievementsScreen()),
        _MenuItem('Pamphlets', Icons.menu_book_outlined, Colors.brown, const PamphletsScreen()),
        _MenuItem('Themes', Icons.palette_outlined, Colors.pink, const ThemesScreen()),
        _MenuItem('Premium', Icons.workspace_premium, Colors.deepOrange, const PremiumScreen()),
      ]);
    } else if (userRole == 'caretaker') {
      items.addAll([
        _MenuItem('Assigned houses', Icons.home_work_outlined, Colors.orange, const CaretakerHousesScreen()),
        _MenuItem('Tenant approvals', Icons.how_to_reg_outlined, Colors.green, const TenantApprovalsScreen()),
        _MenuItem('Rent confirmations', Icons.fact_check_outlined, Colors.blue, const CaretakerPaymentsScreen()),
        _MenuItem('Complaints', Icons.support_agent, Colors.deepOrange, const ComplaintsScreen()),
        _MenuItem('Tenant groups', Icons.groups_outlined, Colors.indigo, const TenantGroupsScreen()),
        _MenuItem('House requests', Icons.swap_horiz, Colors.teal, const HouseRequestsScreen()),
        _MenuItem('Notices', Icons.campaign_outlined, Colors.purple, const NoticesScreen()),
        _MenuItem('Tenant portal', Icons.person_outline, Colors.cyan, const TenantPortalScreen()),
        _MenuItem('Themes', Icons.palette_outlined, Colors.pink, const ThemesScreen()),
      ]);
    } else {
      items.addAll([
        _MenuItem('Find a vacant house', Icons.home_work_outlined, Colors.orange, const TenantPortalScreen()),
        _MenuItem('My complaints', Icons.support_agent, Colors.deepOrange, const ComplaintsScreen()),
        _MenuItem('Tenant groups', Icons.groups_outlined, Colors.indigo, const TenantGroupsScreen()),
        _MenuItem('House change requests', Icons.swap_horiz, Colors.teal, const HouseRequestsScreen()),
        _MenuItem('Notices', Icons.campaign_outlined, Colors.purple, const NoticesScreen()),
        _MenuItem('Pay rent', Icons.phone_android, Colors.green, const TenantPayScreen()),
        _MenuItem('Themes', Icons.palette_outlined, Colors.pink, const ThemesScreen()),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text('SkyNest • ' + userRole[0].toUpperCase() + userRole.substring(1)), actions: [
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
    final options = Themes.options;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your style')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 14), child: Text('A more beautiful space to manage your properties.', style: TextStyle(fontSize: 14))),
          ...options.map((option) {
            final selected = themeManager.selectedName == option.name;
            return Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 14),
              child: InkWell(
                onTap: () {
                  themeManager.set(option.theme, option.name);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(option.name + ' applied')));
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    height: 112,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [option.primary, option.secondary], begin: Alignment.centerLeft, end: Alignment.bottomRight)),
                    child: Stack(children: [
                      Positioned(right: 18, top: 12, child: Icon(Icons.directions_car_filled_rounded, size: 55, color: Colors.white.withOpacity(0.22))),
                      Positioned(left: 18, bottom: 8, child: Icon(Icons.villa_rounded, size: 76, color: Colors.white.withOpacity(0.88))),
                      Positioned(right: 22, bottom: 10, child: Icon(Icons.apartment_rounded, size: 48, color: Colors.white.withOpacity(0.48))),
                      Positioned(left: 18, top: 14, child: Icon(option.icon, color: Colors.white, size: 23)),
                      if (selected) const Positioned(right: 14, bottom: 12, child: Icon(Icons.check_circle, color: Colors.white, size: 25)),
                    ]),
                  ),
                  ListTile(
                    title: Text(option.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(option.description),
                    trailing: selected ? const Chip(label: Text('Selected')) : const Icon(Icons.chevron_right),
                  ),
                ]),
              ),
            );
          }),
        ],
      ),
    );
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
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(active ? 'Your account is marked as Premium.' : 'Premium activation requires verified payment and administrator approval. Subscription payment is not yet connected in this build.'))),
        ]));
      },
    ));
  }
}


class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account approval')),
    body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hourglass_top_rounded, size: 72, color: brand),
        SizedBox(height: 18),
        Text('Your account is awaiting approval', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        Text('Your landlord or an authorised caretaker must approve your access.', textAlign: TextAlign.center),
      ],
    ))),
    floatingActionButton: FloatingActionButton.extended(onPressed: () async {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute<void>(builder: (_) => const LoginScreen()), (_) => false);
    }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
  );
}

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});
  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}
class _InvitationsScreenState extends State<InvitationsScreen> {
  String role = 'tenant';
  bool saving = false;
  String? latestCode;
  Future<void> createInvitation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => saving = true);
    try {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      final code = List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
      await FirebaseFirestore.instance.collection('invitations').doc(code).set({
        'role': role, 'landlordId': uid, 'createdBy': uid, 'propertyIds': <String>[],
        'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      });
      if (mounted) setState(() => latestCode = code);
      if (mounted) snack(context, 'Invitation created. It expires in 7 days.');
    } catch (e) { if (mounted) snack(context, 'Could not create invitation: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Caretakers & invitations')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Invite a tenant or caretaker to join your property account. Codes are single-use and expire after seven days.'),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(value: role, decoration: const InputDecoration(labelText: 'Invite role'),
        items: const [DropdownMenuItem(value: 'tenant', child: Text('Tenant')), DropdownMenuItem(value: 'caretaker', child: Text('Caretaker'))],
        onChanged: (v) => setState(() => role = v ?? 'tenant')),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: saving ? null : createInvitation, icon: const Icon(Icons.key),
        label: Text(saving ? 'Creating...' : 'GENERATE INVITATION CODE')),
      if (latestCode != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Share this code with the invited person'),
        SelectableText(latestCode!, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
        const Text('Long-press the code to copy it.'),
      ]))),
      const Divider(height: 32),
      const Text('Linked accounts', style: TextStyle(fontWeight: FontWeight.bold)),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').where('landlordId', isEqualTo: FirebaseAuth.instance.currentUser?.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Could not load linked accounts.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const EmptyView('No invited accounts yet.');
          return Column(children: snap.data!.docs.map((doc) {
            final d = doc.data();
            return Card(child: ListTile(leading: const Icon(Icons.person_outline),
              title: Text(d['displayName']?.toString() ?? d['email']?.toString() ?? 'Account'),
              subtitle: Text((d['role'] ?? 'user').toString() + ' • ' + (d['status'] ?? 'unknown').toString())));
          }).toList());
        },
      ),
    ]),
  );
}

class TenantPortalScreen extends StatelessWidget {
  const TenantPortalScreen({super.key});
  Future<void> requestHouse(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> house) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      final landlordId = p['landlordId']?.toString();
      if (landlordId == null || landlordId.isEmpty) { snack(context, 'Ask your landlord for an invitation first.'); return; }
      await FirebaseFirestore.instance.collection('houseRequests').add({
        'tenantId': uid, 'tenantName': p['displayName'] ?? 'Tenant', 'landlordId': landlordId,
        'houseId': house.id, 'houseNo': house.data()['houseNo'] ?? '',
        'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) snack(context, 'House request sent for approval.');
    } catch (e) { if (context.mounted) snack(context, 'Could not send request: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Vacant houses')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, profile) {
          if (!profile.hasData) return const Center(child: CircularProgressIndicator());
          final landlordId = profile.data?.data()?['landlordId']?.toString();
          if (landlordId == null) return const EmptyView('Your account is not linked to a landlord.');
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('houses').where('landlordId', isEqualTo: landlordId).where('isOccupied', isEqualTo: false).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return errorView('Vacant houses could not load.');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const EmptyView('No vacant houses declared yet.');
              return ListView(children: snap.data!.docs.map((house) {
                final d = house.data();
                return Card(child: ListTile(leading: const Icon(Icons.home_outlined),
                  title: Text('House ' + (d['houseNo'] ?? '').toString()),
                  subtitle: Text(currency.format((d['rent'] as num?)?.toDouble() ?? 0) + ' / month'),
                  trailing: FilledButton(onPressed: () => requestHouse(context, house), child: const Text('REQUEST')));
              }).toList());
            },
          );
        },
      ),
    );
  }
}

class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}
class _ComplaintsScreenState extends State<ComplaintsScreen> {
  final subject = TextEditingController(), details = TextEditingController();
  bool saving = false;
  @override
  void dispose() { subject.dispose(); details.dispose(); super.dispose(); }
  Future<void> submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || subject.text.trim().isEmpty || details.text.trim().isEmpty) { snack(context, 'Enter a subject and describe the issue.'); return; }
    setState(() => saving = true);
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
      if (landlordId == null) throw StateError('Your account is not linked to a landlord.');
      await FirebaseFirestore.instance.collection('complaints').add({
        'createdBy': uid, 'createdByName': p['displayName'] ?? 'User', 'role': p['role'] ?? 'tenant',
        'landlordId': landlordId, 'subject': subject.text.trim(), 'details': details.text.trim(),
        'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
      });
      subject.clear(); details.clear();
      if (mounted) snack(context, 'Complaint submitted.');
    } catch (e) { if (mounted) snack(context, 'Could not submit complaint: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> updateStatus(String id, String status) async {
    try { await FirebaseFirestore.instance.collection('complaints').doc(id).update({
      'status': status, 'lastUpdatedAt': FieldValue.serverTimestamp(), 'lastUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
    }); } catch (e) { if (mounted) snack(context, 'Could not update complaint: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Smart complaint channel')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: subject, decoration: const InputDecoration(labelText: 'Complaint subject', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: details, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Describe the issue', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : submit,
            icon: const Icon(Icons.send), label: Text(saving ? 'Sending...' : 'SUBMIT COMPLAINT'))),
        ])),
        const Divider(height: 1),
        Expanded(child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, profile) {
            if (!profile.hasData) return const Center(child: CircularProgressIndicator());
            final p = profile.data?.data() ?? {};
            final role = p['role']?.toString() ?? 'tenant';
            final stream = role == 'landlord'
              ? FirebaseFirestore.instance.collection('complaints').where('landlordId', isEqualTo: uid).snapshots()
              : role == 'caretaker'
                ? FirebaseFirestore.instance.collection('complaints').where('landlordId', isEqualTo: p['landlordId']).snapshots()
                : FirebaseFirestore.instance.collection('complaints').where('createdBy', isEqualTo: uid).snapshots();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snap) {
              if (snap.hasError) return errorView('Complaints could not load.');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const EmptyView('No complaints yet.');
              return ListView(children: snap.data!.docs.map((doc) {
                final d = doc.data();
                return Card(child: ExpansionTile(leading: const Icon(Icons.report_problem_outlined),
                  title: Text(d['subject']?.toString() ?? 'Complaint'),
                  subtitle: Text((d['createdByName'] ?? 'User').toString() + ' • ' + (d['status'] ?? 'open').toString()),
                  children: [
                    Padding(padding: const EdgeInsets.all(14), child: Align(alignment: Alignment.centerLeft, child: Text(d['details']?.toString() ?? ''))),
                    if (role != 'tenant') Wrap(spacing: 8, children: [
                      TextButton(onPressed: () => updateStatus(doc.id, 'in_progress'), child: const Text('In progress')),
                      TextButton(onPressed: () => updateStatus(doc.id, 'resolved'), child: const Text('Resolve')),
                    ]),
                  ]));
              }).toList());
            });
          },
        )),
      ]),
    );
  }
}

class TenantGroupsScreen extends StatefulWidget {
  const TenantGroupsScreen({super.key});
  @override
  State<TenantGroupsScreen> createState() => _TenantGroupsScreenState();
}
class _TenantGroupsScreenState extends State<TenantGroupsScreen> {
  final name = TextEditingController();
  bool saving = false;
  @override
  void dispose() { name.dispose(); super.dispose(); }
  Future<void> createGroup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || name.text.trim().isEmpty) { snack(context, 'Enter a group name.'); return; }
    setState(() => saving = true);
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
      if (landlordId == null) throw StateError('Your account is not linked to a property.');
      final ref = FirebaseFirestore.instance.collection('groups').doc();
      await ref.set({'name': name.text.trim(), 'createdBy': uid, 'landlordId': landlordId,
        'createdAt': FieldValue.serverTimestamp(), 'memberIds': [uid]});
      await ref.collection('members').doc(uid).set({'joinedAt': FieldValue.serverTimestamp(), 'role': p['role'] ?? 'tenant'});
      name.clear();
      if (mounted) snack(context, 'Group created.');
    } catch (e) { if (mounted) snack(context, 'Could not create group: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Tenant-to-tenant groups')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'New group name'))),
          IconButton(onPressed: saving ? null : createGroup, icon: const Icon(Icons.add_circle, size: 32)),
        ])),
        Expanded(child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, profile) {
            if (!profile.hasData) return const Center(child: CircularProgressIndicator());
            final p = profile.data?.data() ?? {};
            final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
            if (landlordId == null) return const EmptyView('Join a landlord property account first.');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('groups').where('landlordId', isEqualTo: landlordId).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return errorView('Groups could not load.');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                if (snap.data!.docs.isEmpty) return const EmptyView('No groups yet. Create the first group.');
                return ListView(children: snap.data!.docs.map((doc) => Card(child: ListTile(
                  leading: const Icon(Icons.groups_outlined), title: Text(doc.data()['name']?.toString() ?? 'Group'),
                  subtitle: Text(((doc.data()['memberIds'] as List?)?.length ?? 1).toString() + ' members'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: doc.id, groupName: doc.data()['name']?.toString() ?? 'Group'))),
                ))).toList());
              },
            );
          },
        )),
      ]),
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  final String groupId, groupName;
  const GroupChatScreen({super.key, required this.groupId, required this.groupName});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}
class _GroupChatScreenState extends State<GroupChatScreen> {
  final message = TextEditingController();
  @override
  void dispose() { message.dispose(); super.dispose(); }
  Future<void> send() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || message.text.trim().isEmpty) return;
    final text = message.text.trim(); message.clear();
    try { await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').add({
      'senderId': uid, 'text': text, 'createdAt': FieldValue.serverTimestamp(),
    }); } catch (e) { if (mounted) snack(context, 'Message not sent: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.groupName)),
    body: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').orderBy('createdAt').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Messages could not load. Group membership may be required.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: snap.data!.docs.map((doc) => ListTile(
            title: Text(doc.data()['text']?.toString() ?? ''),
            subtitle: Text(doc.data()['senderId'] == FirebaseAuth.instance.currentUser?.uid ? 'You' : 'Group member'),
          )).toList());
        },
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        Expanded(child: TextField(controller: message, decoration: const InputDecoration(hintText: 'Write a message'))),
        IconButton(onPressed: send, icon: const Icon(Icons.send)),
      ]))),
    ]),
  );
}

class HouseRequestsScreen extends StatelessWidget {
  const HouseRequestsScreen({super.key});
  Future<void> decide(BuildContext context, String id, String status, Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance.collection('houseRequests').doc(id).update({
        'status': status, 'reviewedAt': FieldValue.serverTimestamp(), 'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (status == 'approved') {
        await FirebaseFirestore.instance.collection('houses').doc(data['houseId']?.toString()).update({
          'isOccupied': true, 'status': 'occupied', 'assignedTenantId': data['tenantId'],
        });
        await FirebaseFirestore.instance.collection('tenants').add({
          'name': data['tenantName'] ?? 'Tenant', 'houseNo': data['houseNo'] ?? '',
          'tenantId': data['tenantId'], 'landlordId': data['landlordId'],
          'createdBy': data['landlordId'], 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (context.mounted) snack(context, 'Request ' + status + '.');
    } catch (e) { if (context.mounted) snack(context, 'Could not process request: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('House requests')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, profile) {
          if (!profile.hasData) return const Center(child: CircularProgressIndicator());
          final p = profile.data?.data() ?? {};
          final role = p['role']?.toString() ?? 'tenant';
          final stream = role == 'tenant'
            ? FirebaseFirestore.instance.collection('houseRequests').where('tenantId', isEqualTo: uid).snapshots()
            : FirebaseFirestore.instance.collection('houseRequests').where('landlordId', isEqualTo: role == 'landlord' ? uid : p['landlordId']).snapshots();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snap) {
            if (snap.hasError) return errorView('Requests could not load.');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.docs.isEmpty) return const EmptyView('No house requests.');
            return ListView(children: snap.data!.docs.map((doc) {
              final d = doc.data();
              return Card(child: ListTile(title: Text('House ' + (d['houseNo'] ?? '').toString()),
                subtitle: Text((d['tenantName'] ?? 'Tenant').toString() + ' • ' + (d['status'] ?? 'pending').toString()),
                trailing: role == 'tenant' ? null : Wrap(children: [
                  IconButton(tooltip: 'Approve', onPressed: d['status'] == 'pending' ? () => decide(context, doc.id, 'approved', d) : null, icon: const Icon(Icons.check_circle, color: Colors.green)),
                  IconButton(tooltip: 'Decline', onPressed: d['status'] == 'pending' ? () => decide(context, doc.id, 'declined', d) : null, icon: const Icon(Icons.cancel_outlined, color: Colors.red)),
                ])));
            }).toList());
          });
        },
      ),
    );
  }
}

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}
class _NoticesScreenState extends State<NoticesScreen> {
  final title = TextEditingController(), body = TextEditingController();
  bool saving = false;
  @override
  void dispose() { title.dispose(); body.dispose(); super.dispose(); }
  Future<void> publish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || title.text.trim().isEmpty || body.text.trim().isEmpty) { snack(context, 'Enter a notice title and message.'); return; }
    setState(() => saving = true);
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
      if (landlordId == null) throw StateError('Your account is not linked to a landlord.');
      await FirebaseFirestore.instance.collection('notices').add({
        'title': title.text.trim(), 'body': body.text.trim(), 'landlordId': landlordId,
        'createdBy': uid, 'createdAt': FieldValue.serverTimestamp(), 'audience': 'all',
      });
      title.clear(); body.clear();
      if (mounted) snack(context, 'Notice published.');
    } catch (e) { if (mounted) snack(context, 'Could not publish notice: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Property notices')),
      body: Column(children: [
        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, profile) {
            if (!profile.hasData) return const SizedBox.shrink();
            if (profile.data?.data()?['role'] == 'tenant') return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Notice title')),
              TextField(controller: body, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: saving ? null : publish, child: Text(saving ? 'Publishing...' : 'PUBLISH NOTICE'))),
            ]));
          },
        ),
        const Divider(height: 1),
        Expanded(child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, profile) {
            if (!profile.hasData) return const Center(child: CircularProgressIndicator());
            final p = profile.data?.data() ?? {};
            final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
            if (landlordId == null) return const EmptyView('No landlord linked.');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('notices').where('landlordId', isEqualTo: landlordId).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return errorView('Notices could not load.');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(children: snap.data!.docs.map((doc) => Card(child: ListTile(
                  leading: const Icon(Icons.campaign_outlined), title: Text(doc.data()['title']?.toString() ?? ''),
                  subtitle: Text(doc.data()['body']?.toString() ?? ''),
                ))).toList());
              },
            );
          },
        )),
      ]),
    );
  }
}

class ElectricityScreen extends StatefulWidget {
  const ElectricityScreen({super.key});
  @override
  State<ElectricityScreen> createState() => _ElectricityScreenState();
}
class _ElectricityScreenState extends State<ElectricityScreen> {
  final meterName = TextEditingController(), meterNumber = TextEditingController(), houseNo = TextEditingController(), amount = TextEditingController();
  String billing = 'prepaid';
  bool saving = false;
  @override
  void dispose() { meterName.dispose(); meterNumber.dispose(); houseNo.dispose(); amount.dispose(); super.dispose(); }
  Future<void> saveMeter() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || meterName.text.trim().isEmpty || meterNumber.text.trim().isEmpty) { snack(context, 'Enter meter name and meter number.'); return; }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('meters').add({
        'landlordId': uid, 'name': meterName.text.trim(), 'meterNumber': meterNumber.text.trim(),
        'billingType': billing, 'createdAt': FieldValue.serverTimestamp(),
      });
      meterName.clear(); meterNumber.clear();
      if (mounted) snack(context, 'Meter registered.');
    } catch (e) { if (mounted) snack(context, 'Could not save meter: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> allocateUnit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final value = double.tryParse(amount.text.trim());
    if (uid == null || houseNo.text.trim().isEmpty || value == null || value < 0) { snack(context, 'Enter a house number and valid amount.'); return; }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('electricityAllocations').add({
        'landlordId': uid, 'houseNo': houseNo.text.trim(), 'amount': value,
        'billingType': billing, 'interval': 'monthly', 'createdAt': FieldValue.serverTimestamp(),
      });
      houseNo.clear(); amount.clear();
      if (mounted) snack(context, 'Electricity allocation saved.');
    } catch (e) { if (mounted) snack(context, 'Could not save allocation: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Electricity management')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Register prepaid or postpaid meters and record per-unit electricity allocations.'),
      DropdownButtonFormField<String>(value: billing, decoration: const InputDecoration(labelText: 'Billing model'),
        items: const [DropdownMenuItem(value: 'prepaid', child: Text('Prepaid')), DropdownMenuItem(value: 'postpaid', child: Text('Postpaid'))],
        onChanged: (v) => setState(() => billing = v ?? 'prepaid')),
      const SizedBox(height: 10),
      TextField(controller: meterName, decoration: const InputDecoration(labelText: 'Meter label')),
      TextField(controller: meterNumber, decoration: const InputDecoration(labelText: 'Meter number / reference')),
      FilledButton(onPressed: saving ? null : saveMeter, child: const Text('REGISTER METER')),
      const Divider(height: 30),
      const Text('Per-house electricity allocation', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: houseNo, decoration: const InputDecoration(labelText: 'House / unit number')),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (KSh) per interval')),
      FilledButton(onPressed: saving ? null : allocateUnit, child: const Text('SAVE UNIT ALLOCATION')),
      const SizedBox(height: 12),
      const Text('This stores meter and billing allocation records only. It does not purchase KPLC tokens or automatically pay electricity bills; live transactions need a verified provider integration and secure backend.'),
    ]));
}

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Caretaker activity log')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('activityLogs').where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Activity log could not load.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const EmptyView('No recorded caretaker activity yet.');
          return ListView(children: snap.data!.docs.map((doc) => ListTile(
            leading: const Icon(Icons.history), title: Text(doc.data()['action']?.toString() ?? 'Activity'),
            subtitle: Text(doc.data()['actorName']?.toString() ?? 'Account'),
          )).toList());
        },
      ),
    );
  }
}

class CaretakerHousesScreen extends StatelessWidget {
  const CaretakerHousesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Assigned properties')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('houses').where('caretakerIds', arrayContains: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Assigned properties could not load.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const EmptyView('No properties have been assigned to you yet.');
          return ListView(children: snap.data!.docs.map((doc) => ListTile(
            leading: const Icon(Icons.home_work_outlined), title: Text('House ' + (doc.data()['houseNo'] ?? '').toString()),
            subtitle: Text(doc.data()['isOccupied'] == true ? 'Occupied' : 'Vacant'),
          )).toList());
        },
      ),
    );
  }
}

class TenantApprovalsScreen extends StatelessWidget {
  const TenantApprovalsScreen({super.key});
  Future<void> approve(BuildContext context, String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'status': status, 'approvedAt': FieldValue.serverTimestamp(), 'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (context.mounted) snack(context, 'Account ' + status + '.');
    } catch (e) { if (context.mounted) snack(context, 'Could not update account: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Tenant approvals')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, profile) {
          if (!profile.hasData) return const Center(child: CircularProgressIndicator());
          final p = profile.data?.data() ?? {};
          final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').where('landlordId', isEqualTo: landlordId).where('role', isEqualTo: 'tenant').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return errorView('Tenant accounts could not load.');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const EmptyView('No tenant accounts awaiting approval.');
              return ListView(children: snap.data!.docs.map((doc) {
                final d = doc.data();
                return Card(child: ListTile(title: Text(d['displayName']?.toString() ?? 'Tenant'),
                  subtitle: Text((d['email'] ?? '').toString() + ' • ' + (d['status'] ?? 'pending').toString()),
                  trailing: d['status'] == 'pending' ? Wrap(children: [
                    IconButton(onPressed: () => approve(context, doc.id, 'active'), icon: const Icon(Icons.check_circle, color: Colors.green)),
                    IconButton(onPressed: () => approve(context, doc.id, 'rejected'), icon: const Icon(Icons.cancel, color: Colors.red)),
                  ]) : null));
              }).toList());
            },
          );
        },
      ),
    );
  }
}

class CaretakerPaymentsScreen extends StatelessWidget {
  const CaretakerPaymentsScreen({super.key});
  Future<void> confirm(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance.collection('payments').doc(id).update({
        'status': 'confirmed_by_caretaker', 'confirmedBy': FirebaseAuth.instance.currentUser?.uid,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) snack(context, 'Payment marked as confirmed by caretaker.');
    } catch (e) { if (context.mounted) snack(context, 'Could not confirm payment: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Rent confirmations')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('payments').where('caretakerId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Assigned payment records could not load.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const EmptyView('No rent confirmations assigned to you. The landlord controls financial totals.');
          return ListView(children: snap.data!.docs.map((doc) {
            final d = doc.data();
            return ListTile(title: Text(d['tenantName']?.toString() ?? 'Tenant'),
              subtitle: Text('House ' + (d['houseNo'] ?? '').toString() + ' • ' + (d['status'] ?? 'pending').toString()),
              trailing: TextButton(onPressed: d['status'] == 'pending' ? () => confirm(context, doc.id) : null, child: const Text('CONFIRM')));
          }).toList());
        },
      ),
    );
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
