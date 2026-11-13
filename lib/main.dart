import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:table_calendar/table_calendar.dart';

const brand = Color(0xFF1565C0);
const skynestBannerAdUnitId = 'ca-app-pub-1281241380359357/4686680349';

final GlobalKey<ScaffoldMessengerState> _rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
bool _pushForegroundListenerRegistered = false;
StreamSubscription<String>? _pushTokenRefreshSubscription;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> _savePushToken(String uid, String token) async {
  await FirebaseFirestore.instance.collection('users').doc(uid)
      .collection('devices').doc(token).set({
    'token': token,
    'platform': 'android',
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> initializePushNotifications() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || !firebaseReady) return;
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) await _savePushToken(user.uid, token);
    if (!_pushForegroundListenerRegistered) {
      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'SkyNest';
        final body = message.notification?.body ?? 'You have a new notification.';
        _rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('$title: $body')),
        );
      });
      _pushForegroundListenerRegistered = true;
    }
    await _pushTokenRefreshSubscription?.cancel();
    _pushTokenRefreshSubscription = messaging.onTokenRefresh.listen((freshToken) {
      _savePushToken(user.uid, freshToken);
    });
  } catch (error) {
    debugPrint('Push notification setup failed: $error');
  }
}

bool firebaseReady = false;
String? firebaseError;
final currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 2);
final dateFormat = DateFormat('dd MMM yyyy');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opt into Android edge-to-edge so app surfaces can draw behind transparent system bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Render Flutter immediately. Firebase is initialized only when the user
  // requests authentication, so Firebase startup cannot block the login screen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  runApp(const SkynestApp());
}

Future<bool>? _firebaseInitialization;

Future<bool> ensureFirebaseReady() async {
  if (firebaseReady) return true;
  _firebaseInitialization ??= () async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
      firebaseError = null;
      return true;
    } catch (error) {
      firebaseError = error.toString();
      // Allow a later tap to retry initialization after a transient config/network
      // failure instead of caching a permanently failed Future.
      _firebaseInitialization = null;
      return false;
    }
  }();
  return _firebaseInitialization!;
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
  static ThemeData _make(Color seed, {Brightness brightness = Brightness.light, Color? surface}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, surface: surface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF111820)
          : Color.lerp(scheme.surface, scheme.primaryContainer, 0.13),
      cardColor: brightness == Brightness.dark
          ? const Color(0xFF202B36)
          : Color.lerp(scheme.surface, scheme.primaryContainer, 0.24),
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.dark ? const Color(0xFF18232E) : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? const Color(0xFF202B36) : scheme.surfaceContainerHighest.withOpacity(0.55),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: scheme.primary, width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      ),
    );
  }

  static final blue = _make(const Color(0xFF2463A6));
  static final dark = _make(const Color(0xFFB99A62), brightness: Brightness.dark);
  static final sunset = _make(const Color(0xFFC66A45));
  static final forest = _make(const Color(0xFF52745A));
  static final ivory = _make(const Color(0xFFB18A4A), surface: const Color(0xFFFFFBF3));
  static final ocean = _make(const Color(0xFF315D83));
  static final rose = _make(const Color(0xFF9A6572));
  static final slate = _make(const Color(0xFF64748B));
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
    builder: (_, __) {
      final isDark = themeManager.value.brightness == Brightness.dark;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ));
      return MaterialApp(
        title: 'SkyNest',
        scaffoldMessengerKey: _rootScaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        theme: themeManager.value,
        home: const StartupGate(),
      );
    },
  );
}

class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) => const LoginScreen();
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
    if (!await ensureFirebaseReady()) { message('Firebase could not start. Check the Firebase Android configuration and try again.'); return; }
    if (!validEmail(email.text)) { message('Enter a valid email address.'); return; }
    if (password.text.isEmpty) { message('Enter your password.'); return; }
    setState(() => busy = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      final user = credential.user!;
      final profile = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final profileSnapshot = await profile.get();
      if (!profileSnapshot.exists) {
        // First-time legacy account profile: the authenticated user owns this UID.
        await profile.set({'displayName': user.displayName ?? user.email ?? 'Landlord',
          'email': user.email, 'role': 'landlord', 'status': 'active',
          'createdAt': FieldValue.serverTimestamp(), 'legacyAccount': true});
      } else {
        final existing = profileSnapshot.data() ?? <String, dynamic>{};
        final keys = existing.keys.toSet();
        // Migrate only unlinked pre-role accounts. Never promote an account that
        // already carries tenant/caretaker linkage or an invitation.
        if (!keys.contains('role') && !keys.contains('status') &&
            !keys.contains('landlordId') && !keys.contains('invitationCode')) {
          await profile.update({'role': 'landlord', 'status': 'active',
            'legacyAccount': true, 'updatedAt': FieldValue.serverTimestamp()});
        } else if (existing['role'] == 'landlord' && !keys.contains('status')) {
          // Repair an incomplete landlord profile without changing its role.
          await profile.update({'status': 'active', 'legacyAccount': true,
            'updatedAt': FieldValue.serverTimestamp()});
        }
      }
      final latest = await profile.get();
      final accountStatus = latest.data()?['status']?.toString() ?? 'incomplete';
      if (!mounted) return;
      if (accountStatus == 'pending') {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const PendingApprovalScreen()));
      } else if (accountStatus != 'active') {
        await FirebaseAuth.instance.signOut();
        message('This account is ' + accountStatus + '. Contact your landlord or administrator.');
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const DashboardScreen()));
      }
    } on FirebaseAuthException catch (e) { message(authMessage(e)); }
    catch (_) { message('Login could not be completed. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> createAccount() async {
    if (!await ensureFirebaseReady()) { message('Firebase could not start. Check the Firebase Android configuration and try again.'); return; }
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

  String resetPasswordMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address and try again.';
      case 'user-not-found':
        // Keep the response neutral: Firebase email-enumeration protection may
        // intentionally hide whether an account exists for this address.
        return 'If an account exists for this email, a reset link will be sent. Check your inbox and spam folder.';
      case 'operation-not-allowed':
        return 'Password reset is disabled in Firebase Authentication. Enable the Email/Password provider in Firebase Console.';
      case 'network-request-failed':
        return 'No connection to Firebase. Check your internet and try again.';
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Password reset is temporarily rate-limited. Wait a while before trying again.';
      case 'invalid-continue-uri':
      case 'missing-continue-uri':
      case 'unauthorized-continue-uri':
        return 'Firebase rejected the password-reset link settings. Check the authorised domains and reset action URL in Firebase Console.';
      default:
        return 'Firebase could not process the password reset (' + e.code + '). Please try again later.';
    }
  }

  Future<void> resetPassword() async {
    final address = email.text.trim();
    if (!validEmail(address)) {
      message('Enter a valid email address in the Email field first.');
      return;
    }
    if (busy) return;
    if (!await ensureFirebaseReady()) {
      message('Firebase could not start. Check the Firebase Android configuration and try again.');
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: address);
      message('Request accepted. If an account exists for this email, Firebase will send a reset link. Check your inbox and spam folder.');
    } on FirebaseAuthException catch (e) {
      message(resetPasswordMessage(e));
    } catch (_) {
      message('Could not contact Firebase to request a reset link. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF2FF), Color(0xFFF8FAFD), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            image: const DecorationImage(
                              image: NetworkImage('https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=1200&q=90'),
                              fit: BoxFit.cover,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [const Color(0xFF10365F).withOpacity(0.86), const Color(0xFF2476C8).withOpacity(0.70)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF174D83).withOpacity(0.20),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 76,
                                width: 76,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                                ),
                                child: const Icon(Icons.apartment_rounded, size: 43, color: Colors.white),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'SkyNest',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'PROPERTY MANAGEMENT',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.88),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Manage properties. Connect people.\nMake renting simpler.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.94),
                                  height: 1.4,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Welcome back',
                          textAlign: TextAlign.left,
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xFF172B4D)),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Sign in to continue to your SkyNest account.',
                          style: TextStyle(fontSize: 14, color: Color(0xFF65758B)),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: 'Email address',
                            hintText: 'name@example.com',
                            prefixIcon: const Icon(Icons.email_outlined),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(color: Color(0xFFD8E1EE)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) { if (!busy) signIn(); },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(color: Color(0xFFD8E1EE)),
                            ),
                            suffixIcon: IconButton(
                              tooltip: obscure ? 'Show password' : 'Hide password',
                              onPressed: () => setState(() => obscure = !obscure),
                              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy ? null : resetPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: busy ? null : signIn,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF174D83),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: busy
                                ? const SizedBox(height: 21, width: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.login_rounded),
                                      SizedBox(width: 10),
                                      Text('SIGN IN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: busy ? null : showCreateAccount,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF174D83),
                              side: const BorderSide(color: Color(0xFF174D83), width: 1.3),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Text('CREATE ACCOUNT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ),
                        ),
                        if (firebaseError != null) ...[
                          const SizedBox(height: 14),
                          Card(
                            color: colors.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('Firebase setup is required before login or registration works.\n${firebaseError ?? ''}'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Color(0xFFD6DFEA))),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('SKYNEST', style: TextStyle(color: Color(0xFF8190A5), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
                            ),
                            Expanded(child: Divider(color: Color(0xFFD6DFEA))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Your property, our priority.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF65758B), fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Secure access • Simple property management',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8A97A9), fontSize: 11),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Developed by Benson',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF174D83),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


const List<String> _skynestPropertyPhotos = [
  'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=1000&q=85',
  'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=1000&q=85',
  'https://images.unsplash.com/photo-1600566753086-00f18fb6b3ea?w=1000&q=85',
  'https://images.unsplash.com/photo-1600047509807-ba8f99d2cdde?w=1000&q=85',
  'https://images.unsplash.com/photo-1600607687920-4e2a09cf159d?w=1000&q=85',
  'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?w=1000&q=85',
  'https://images.unsplash.com/photo-1600585154526-990dced4db0d?w=1000&q=85',
  'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?w=1000&q=85',
];

String _menuImageFor(String title) {
  final key = title.toLowerCase();
  if (key.contains('house') || key.contains('vacant')) {
    return 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=1000&q=88';
  }
  if (key.contains('tenant') || key.contains('people') || key.contains('approval')) {
    return 'https://images.unsplash.com/photo-1521737711867-e3b97375f902?w=1000&q=88';
  }
  if (key.contains('payment') || key.contains('rent') || key.contains('pay')) {
    return 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=1000&q=88';
  }
  if (key.contains('caretaker') || key.contains('invitation')) {
    return 'https://images.unsplash.com/photo-1521791136064-7986c2920216?w=1000&q=88';
  }
  if (key.contains('complaint') || key.contains('support') || key.contains('request')) {
    return 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=1000&q=88';
  }
  if (key.contains('group')) {
    return 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=1000&q=88';
  }
  if (key.contains('notice')) {
    return 'https://images.unsplash.com/photo-1497366811353-6870744d04b2?w=1000&q=88';
  }
  if (key.contains('electric')) {
    return 'https://images.unsplash.com/photo-1473341304170-971813c3e7b8?w=1000&q=88';
  }
  if (key.contains('activity') || key.contains('plan')) {
    return 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=1000&q=88';
  }
  if (key.contains('calculator')) {
    return 'https://images.unsplash.com/photo-1554224154-22dec7ec8818?w=1000&q=88';
  }
  if (key.contains('calendar')) {
    return 'https://images.unsplash.com/photo-1506784983877-45594efa4cbe?w=1000&q=88';
  }
  if (key.contains('achievement')) {
    return 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?w=1000&q=88';
  }
  if (key.contains('pamphlet') || key.contains('book')) {
    return 'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=1000&q=88';
  }
  if (key.contains('theme')) {
    return 'https://images.unsplash.com/photo-1494438639946-1ebd1d20bf85?w=1000&q=88';
  }
  if (key.contains('premium')) {
    return 'https://images.unsplash.com/photo-1600607687920-4e2a09cf159d?w=1000&q=88';
  }
  return _skynestPropertyPhotos[0];
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
    initializePushNotifications();
    // Initialize AdMob only after the dashboard is opened, never during app startup.
    _initializeBannerAd();
  }

  Future<void> _initializeBannerAd() async {
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      // Ads are optional; an AdMob failure must not prevent property management.
      return;
    }
    if (!mounted) return;
    banner = BannerAd(
      adUnitId: skynestBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => loaded = true); },
        onAdFailedToLoad: (ad, _) { ad.dispose(); banner = null; },
      ),
    )..load();
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
        _MenuItem('Tenant payment submissions', Icons.fact_check_outlined, Colors.teal, const PaymentSubmissionsScreen()),
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
      body: Stack(fit: StackFit.expand, children: [
        Image.network(
          _skynestPropertyPhotos[1],
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        ColoredBox(color: Theme.of(context).colorScheme.surface.withOpacity(0.88)),
        GridView.builder(
        padding: const EdgeInsets.all(14), itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.12, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final scheme = Theme.of(context).colorScheme;
          final tint = Color.lerp(item.color, scheme.surface, 0.84)!;
          return Card(
            color: tint,
            elevation: 3,
            shadowColor: item.color.withOpacity(0.22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => item.page)),
              child: Stack(fit: StackFit.expand, children: [
                Image.network(
                  _menuImageFor(item.title),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(color: tint),
                ),
                DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.22), Colors.black.withOpacity(0.72)],
                  ),
                )),
                Positioned(right: -13, top: -18, child: Icon(item.icon, size: 92, color: Colors.white.withOpacity(0.16))),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.20),
                        border: Border.all(color: Colors.white.withOpacity(0.35)),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(item.icon, size: 29, color: Colors.white),
                    ),
                    const Spacer(),
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, height: 1.15)),
                    const SizedBox(height: 5),
                    const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                  ]),
                ),
              ]),
            ),
          );
        },
      )]),
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
            await FirebaseFirestore.instance.collection('houses').add({'houseNo': number.text.trim(), 'rent': double.parse(rent.text), 'isOccupied': false, 'status': 'vacant', 'landlordId': FirebaseAuth.instance.currentUser?.uid, 'caretakerIds': <String>[], 'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid});
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
        return ListView(children: s.data!.docs.asMap().entries.map((entry) {
          final index = entry.key;
          final doc = entry.value;
          final d = doc.data();
          final rentValue = (d['rent'] as num?)?.toDouble() ?? 0;
          final occupancy = d['isOccupied'] == true ? 'Occupied' : 'Vacant';
          final colors = Theme.of(context).colorScheme;
          final occupied = d['isOccupied'] == true;
          return Card(
            margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            color: Color.lerp(colors.surface, occupied ? const Color(0xFFD9EEE7) : const Color(0xFFDCEBFA), 0.62),
            elevation: 2,
            shadowColor: colors.primary.withOpacity(0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    _skynestPropertyPhotos[index % _skynestPropertyPhotos.length],
                    width: 62, height: 62, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 62, height: 62, color: occupied ? const Color(0xFF2D8A72) : const Color(0xFF3979B9),
                      child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
                title: Text('House ' + (d['houseNo']?.toString() ?? ''),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(currency.format(rentValue) + ' / month',
                    style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w500)),
                ),
                isThreeLine: false,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: occupied ? const Color(0xFF287D66).withOpacity(0.13) : const Color(0xFF2463A6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(occupancy, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: occupied ? const Color(0xFF287D66) : const Color(0xFF2463A6))),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => confirmDelete(context, 'Delete this house?', () => doc.reference.delete()),
                  ),
                ]),
              ),
            ),
          );
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
            await FirebaseFirestore.instance.collection('tenants').add({'name': name.text.trim(), 'phone': phone.text.trim(), 'houseNo': house.text.trim(), 'rentAmount': double.parse(rent.text), 'createdAt': FieldValue.serverTimestamp(), 'createdBy': FirebaseAuth.instance.currentUser?.uid, 'landlordId': FirebaseAuth.instance.currentUser?.uid});
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
      stream: FirebaseFirestore.instance.collection('tenants').where('landlordId', isEqualTo: FirebaseAuth.instance.currentUser!.uid).snapshots(),
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
  void initState() {
    super.initState();
    _loadTenantDetails();
  }
  Future<void> _loadTenantDetails() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (profile.data()?['role'] == 'tenant' && mounted) {
        tenant.text = profile.data()?['displayName']?.toString() ?? '';
        house.text = profile.data()?['houseNo']?.toString() ?? '';
      }
    } catch (_) {}
  }
  @override
  void dispose() { tenant.dispose(); house.dispose(); amount.dispose(); super.dispose(); }
  Future<void> savePayment() async {
    final value = double.tryParse(amount.text.trim());
    if (tenant.text.trim().isEmpty || value == null || value <= 0) { snack(context, 'Enter tenant name and a valid amount.'); return; }
    setState(() => saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Please sign in again.');
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      if (p['role'] == 'tenant') {
        final landlordId = p['landlordId']?.toString();
        if (landlordId == null || landlordId.isEmpty) throw StateError('Your tenant account is not linked to a landlord.');
        await FirebaseFirestore.instance.collection('paymentSubmissions').add({
          'tenantId': uid, 'tenantName': tenant.text.trim(), 'landlordId': landlordId,
          'houseId': p['houseId'], 'houseNo': house.text.trim(), 'amount': value,
          'method': 'Manual payment submission', 'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) { amount.clear(); snack(context, 'Payment details sent to your landlord for verification. No automatic M-Pesa payment was made.'); }
      } else {
        final paymentRef = await FirebaseFirestore.instance.collection('payments').add({
          'tenantName': tenant.text.trim(), 'houseNo': house.text.trim(), 'amount': value,
          'method': 'Manual / awaiting M-Pesa confirmation', 'status': 'Pending verification',
          'createdAt': FieldValue.serverTimestamp(), 'createdBy': uid,
        });
        final matchingHouse = await FirebaseFirestore.instance.collection('houses')
          .where('createdBy', isEqualTo: uid).where('houseNo', isEqualTo: house.text.trim()).limit(1).get();
        if (matchingHouse.docs.isNotEmpty) {
          final assigned = (matchingHouse.docs.first.data()['caretakerIds'] as List?)?.whereType<String>().toList() ?? <String>[];
          if (assigned.isNotEmpty) {
            await FirebaseFirestore.instance.collection('paymentConfirmations').add({
              'landlordId': uid, 'caretakerId': assigned.first, 'paymentId': paymentRef.id,
              'tenantName': tenant.text.trim(), 'houseNo': house.text.trim(),
              'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
        if (mounted) { amount.clear(); snack(context, 'Payment record saved. Confirm actual receipt before marking it received.'); }
      }
    } catch (e) { if (mounted) snack(context, 'Could not submit payment: ' + e.toString()); }
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


class PaymentSubmissionsScreen extends StatelessWidget {
  const PaymentSubmissionsScreen({super.key});
  Future<void> assignCaretaker(BuildContext context, String id, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final houses = await FirebaseFirestore.instance.collection('houses')
        .where('createdBy', isEqualTo: uid).where('houseNo', isEqualTo: data['houseNo']).limit(1).get();
      if (houses.docs.isEmpty) throw StateError('House record not found.');
      final assigned = (houses.docs.first.data()['caretakerIds'] as List?)?.whereType<String>().toList() ?? <String>[];
      if (assigned.isEmpty) throw StateError('No caretaker is assigned to this house.');
      await FirebaseFirestore.instance.collection('paymentConfirmations').add({
        'landlordId': uid, 'caretakerId': assigned.first, 'paymentId': id,
        'tenantName': data['tenantName'] ?? 'Tenant', 'houseNo': data['houseNo'] ?? '',
        'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('paymentSubmissions').doc(id).update({'status': 'awaiting_caretaker'});
      if (context.mounted) snack(context, 'A payment confirmation task was sent to the caretaker.');
    } catch (e) { if (context.mounted) snack(context, 'Could not assign confirmation: ' + e.toString()); }
  }
  Future<void> markReceived(BuildContext context, String id, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final payment = await FirebaseFirestore.instance.collection('payments').add({
        'tenantName': data['tenantName'] ?? 'Tenant', 'houseNo': data['houseNo'] ?? '',
        'amount': data['amount'], 'method': data['method'] ?? 'Manual',
        'status': 'Received (landlord verified)', 'createdAt': FieldValue.serverTimestamp(),
        'createdBy': uid, 'landlordId': uid, 'tenantId': data['tenantId'],
      });
      await FirebaseFirestore.instance.collection('paymentSubmissions').doc(id).update({
        'status': 'received', 'ledgerPaymentId': payment.id, 'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) snack(context, 'Payment added to the landlord ledger.');
    } catch (e) { if (context.mounted) snack(context, 'Could not verify payment: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Tenant payment submissions')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('paymentSubmissions').where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Payment submissions could not load.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const EmptyView('No tenant payment submissions.');
          return ListView(children: snap.data!.docs.map((doc) {
            final d = doc.data();
            final status = d['status']?.toString() ?? 'pending';
            return Card(child: ListTile(
              title: Text(d['tenantName']?.toString() ?? 'Tenant'),
              subtitle: Text('House ' + (d['houseNo'] ?? '').toString() + ' • ' +
                currency.format((d['amount'] as num?)?.toDouble() ?? 0) + ' • ' + status),
              isThreeLine: true,
              trailing: status == 'received' || status == 'rejected' ? null : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'assign') assignCaretaker(context, doc.id, d);
                  if (value == 'received') markReceived(context, doc.id, d);
                  if (value == 'reject') doc.reference.update({'status': 'rejected', 'reviewedAt': FieldValue.serverTimestamp()});
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'assign', child: Text('Send to caretaker')),
                  PopupMenuItem(value: 'received', child: Text('Verify & record received')),
                  PopupMenuItem(value: 'reject', child: Text('Reject submission')),
                ],
              ),
            ));
          }).toList());
        },
      ),
    );
  }
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
                    height: 126,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [option.primary, option.secondary], begin: Alignment.centerLeft, end: Alignment.bottomRight)),
                    child: Stack(children: [
                      Positioned(right: 18, top: 12, child: Icon(option.icon, size: 58, color: Colors.white.withOpacity(0.22))),
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
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top_rounded, size: 72, color: brand),
        const SizedBox(height: 18),
        const Text('Your account is awaiting approval', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Your landlord or an authorised caretaker must approve your access.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () async {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) return;
          try {
            final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            final status = profile.data()?['status']?.toString() ?? 'pending';
            if (status == 'active' && context.mounted) {
              Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => const DashboardScreen()));
            } else if (context.mounted) {
              snack(context, 'Account status: ' + status + '.');
            }
          } catch (e) { if (context.mounted) snack(context, 'Could not check approval: ' + e.toString()); }
        }, icon: const Icon(Icons.refresh), label: const Text('CHECK APPROVAL')),
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
      final propertyIds = <String>[];
      if (role == 'caretaker') {
        final houses = await FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: uid).get();
        propertyIds.addAll(houses.docs.map((doc) => doc.id));
      }
      await FirebaseFirestore.instance.collection('invitations').doc(code).set({
        'role': role, 'landlordId': uid, 'createdBy': uid, 'propertyIds': propertyIds,
        'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      });
      await recordActivity(uid, 'Created a ' + role + ' invitation');
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
              subtitle: Text((d['role'] ?? 'user').toString() + ' • ' + (d['status'] ?? 'unknown').toString() + '\nID: ' + doc.id),
              trailing: d['role'] == 'caretaker' && d['status'] == 'active'
                ? IconButton(tooltip: 'Remove caretaker access', icon: const Icon(Icons.person_remove_alt_1, color: Colors.red),
                    onPressed: () async {
                      try {
                        await doc.reference.update({'status': 'suspended'});
                        final houses = await FirebaseFirestore.instance.collection('houses')
                          .where('createdBy', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                          .where('caretakerIds', arrayContains: doc.id).get();
                        for (final house in houses.docs) {
                          await house.reference.update({'caretakerIds': FieldValue.arrayRemove([doc.id])});
                        }
                        await recordActivity(FirebaseAuth.instance.currentUser!.uid, 'Removed caretaker access for ' + doc.id);
                        if (context.mounted) snack(context, 'Caretaker access removed.');
                      } catch (e) { if (context.mounted) snack(context, 'Could not remove caretaker: ' + e.toString()); }
                    })
                : null));
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
        'currentHouseId': p['houseId'], 'requestType': p['houseId'] == null ? 'new' : 'transfer',
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
                  trailing: FilledButton(onPressed: () => requestHouse(context, house), child: const Text('REQUEST'))));
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
    try {
      final ref = FirebaseFirestore.instance.collection('complaints').doc(id);
      final complaint = await ref.get();
      await ref.update({'status': status, 'lastUpdatedAt': FieldValue.serverTimestamp(), 'lastUpdatedBy': FirebaseAuth.instance.currentUser?.uid});
      final landlordId = complaint.data()?['landlordId']?.toString();
      if (landlordId != null) await recordActivity(landlordId, 'Updated complaint status to ' + status);
    } catch (e) { if (mounted) snack(context, 'Could not update complaint: ' + e.toString()); }
  }
  Future<void> respond(String id) async {
    final controller = TextEditingController();
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Respond to complaint'),
      content: TextField(controller: controller, minLines: 2, maxLines: 5,
        decoration: const InputDecoration(labelText: 'Response to tenant')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (controller.text.trim().isEmpty) return;
          try {
            final complaintRef = FirebaseFirestore.instance.collection('complaints').doc(id);
            final complaint = await complaintRef.get();
            await complaintRef.update({
              'response': controller.text.trim(), 'status': 'in_progress',
              'lastUpdatedAt': FieldValue.serverTimestamp(), 'lastUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
            });
            final landlordId = complaint.data()?['landlordId']?.toString();
            if (landlordId != null) await recordActivity(landlordId, 'Responded to a tenant complaint');
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) snack(context, 'Response sent to tenant.');
          } catch (e) { if (mounted) snack(context, 'Could not send response: ' + e.toString()); }
        }, child: const Text('SEND RESPONSE')),
      ],
    ));
    controller.dispose();
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
                    Padding(padding: const EdgeInsets.all(14), child: Align(alignment: Alignment.centerLeft, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['details']?.toString() ?? ''),
                        if ((d['response'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text('Manager response', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(d['response'].toString()),
                        ],
                      ],
                    ))),
                    if (role != 'tenant') Wrap(spacing: 8, children: [
                      TextButton(onPressed: () => respond(doc.id), child: const Text('Reply')),
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
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        final groupRef = FirebaseFirestore.instance.collection('groups').doc(doc.id);
                        await groupRef.update({'memberIds': FieldValue.arrayUnion([uid])});
                        await groupRef.collection('members').doc(uid).set({'joinedAt': FieldValue.serverTimestamp(), 'role': p['role'] ?? 'tenant'});
                        if (context.mounted) snack(context, 'Joined group.');
                      } catch (e) { if (context.mounted) snack(context, 'Could not join group: ' + e.toString()); }
                    },
                    child: Text(((doc.data()['memberIds'] as List?)?.contains(uid) ?? false) ? 'OPEN' : 'JOIN')),
                  onTap: () {
                    if (!((doc.data()['memberIds'] as List?)?.contains(uid) ?? false)) {
                      snack(context, 'Join this group first.');
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupChatScreen(groupId: doc.id, groupName: doc.data()['name']?.toString() ?? 'Group')));
                  },
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
  bool sending = false;
  @override
  void dispose() { message.dispose(); super.dispose(); }

  Future<void> send() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = message.text.trim();
    if (user == null || text.isEmpty || sending) return;
    setState(() => sending = true);
    message.clear();
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final senderName = (profile.data()?['displayName'] ?? user.displayName ?? 'Member').toString();
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('messages').add({
        'senderId': user.uid,
        'senderName': senderName,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) snack(context, 'Message not sent: ' + e.toString());
      message.text = text;
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> deleteMessage(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || doc.data()?['senderId'] != uid) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes your message for everyone in this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await doc.reference.delete();
    } catch (e) {
      if (mounted) snack(context, 'Could not delete message: ' + e.toString());
    }
  }

  Future<void> leaveGroup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this group?'),
        content: const Text('You will stop receiving new messages from this group. You can join again later if it remains available.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Leave group')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final group = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
      await group.update({'memberIds': FieldValue.arrayRemove([uid])});
      await group.collection('members').doc(uid).delete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, 'Could not leave group: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.groupName),
      actions: [
        IconButton(
          tooltip: 'Leave group',
          onPressed: leaveGroup,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('groups').doc(widget.groupId)
            .collection('messages').orderBy('createdAt').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return errorView('Messages could not load. Check group membership and Firestore permissions.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (snap.data!.docs.isEmpty) return const EmptyView('No messages yet. Say hello to the group.');
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snap.data!.docs[index];
              final data = doc.data();
              final mine = data['senderId'] == uid;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  child: Card(
                    color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 9, 7, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(mine ? 'You' : (data['senderName']?.toString() ?? 'Group member'),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary))),
                          if (mine) PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                            iconSize: 18,
                            onSelected: (value) { if (value == 'delete') deleteMessage(doc); },
                            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete message'))],
                          ),
                        ]),
                        Text(data['text']?.toString() ?? ''),
                        if (data['createdAt'] is Timestamp)
                          Align(alignment: Alignment.centerRight, child: Text(
                            DateFormat('HH:mm').format((data['createdAt'] as Timestamp).toDate()),
                            style: Theme.of(context).textTheme.labelSmall,
                          )),
                      ]),
                    ),
                  ),
                ),
              );
            },
          );
        },
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        Expanded(child: TextField(
          controller: message,
          minLines: 1, maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Write a message'),
          onSubmitted: (_) => send(),
        )),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send)),
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
        final tenantId = data['tenantId']?.toString();
        await FirebaseFirestore.instance.collection('houses').doc(data['houseId']?.toString()).update({
          'isOccupied': true, 'status': 'occupied', 'assignedTenantId': tenantId,
        });
        final oldHouseId = data['currentHouseId']?.toString();
        if (data['requestType'] == 'transfer' && oldHouseId != null && oldHouseId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('houses').doc(oldHouseId).update({
            'isOccupied': false, 'status': 'vacant', 'assignedTenantId': FieldValue.delete(),
          });
        }
        if (tenantId != null) {
          await FirebaseFirestore.instance.collection('users').doc(tenantId).update({
            'houseId': data['houseId'], 'houseNo': data['houseNo'],
          });
        }
        await FirebaseFirestore.instance.collection('tenants').add({
          'name': data['tenantName'] ?? 'Tenant', 'houseNo': data['houseNo'] ?? '',
          'tenantId': tenantId, 'landlordId': data['landlordId'],
          'createdBy': data['landlordId'], 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      final landlordId = data['landlordId']?.toString();
      if (landlordId != null) await recordActivity(landlordId, status + ' a tenant house request for unit ' + (data['houseNo'] ?? '').toString());
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
  final title = TextEditingController(), body = TextEditingController(), targetUids = TextEditingController();
  bool saving = false;
  @override
  void dispose() { title.dispose(); body.dispose(); targetUids.dispose(); super.dispose(); }
  Future<void> publish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || title.text.trim().isEmpty || body.text.trim().isEmpty) { snack(context, 'Enter a notice title and message.'); return; }
    setState(() => saving = true);
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      final landlordId = p['role'] == 'landlord' ? uid : p['landlordId'];
      if (landlordId == null) throw StateError('Your account is not linked to a landlord.');
      final explicitTargets = targetUids.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
      final linkedAccounts = await FirebaseFirestore.instance.collection('users')
        .where('landlordId', isEqualTo: landlordId).where('status', isEqualTo: 'active').get();
      final linkedIds = linkedAccounts.docs.map((d) => d.id).toSet();
      if (explicitTargets.any((id) => !linkedIds.contains(id))) {
        throw StateError('One or more selected tenant IDs do not belong to this property account.');
      }
      final recipients = explicitTargets.isNotEmpty ? explicitTargets : linkedAccounts.docs.map((d) => d.id).toList();
      final notice = {
        'title': title.text.trim(), 'body': body.text.trim(), 'landlordId': landlordId,
        'createdBy': uid, 'createdAt': FieldValue.serverTimestamp(),
        'audience': explicitTargets.isEmpty ? 'all' : 'selected',
      };
      final noticeRef = await FirebaseFirestore.instance.collection('notices').add(notice);
      for (final recipient in recipients) {
        await FirebaseFirestore.instance.collection('users').doc(recipient).collection('notices').doc(noticeRef.id).set(notice);
      }
      title.clear(); body.clear(); targetUids.clear();
      await recordActivity(landlordId, 'Published a property notice');
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
              TextField(controller: targetUids, decoration: const InputDecoration(labelText: 'Specific tenant UIDs (comma-separated; leave blank for all tenants)')),
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
            final noticeStream = p['role'] == 'tenant'
              ? FirebaseFirestore.instance.collection('users').doc(uid).collection('notices').snapshots()
              : FirebaseFirestore.instance.collection('notices').where('landlordId', isEqualTo: landlordId).snapshots();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: noticeStream,
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
  String interval = 'monthly';
  String? selectedMeterId;
  bool saving = false;
  @override
  void dispose() { meterName.dispose(); meterNumber.dispose(); houseNo.dispose(); amount.dispose(); super.dispose(); }
  Future<void> saveMeter() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || meterName.text.trim().isEmpty || meterNumber.text.trim().isEmpty) { snack(context, 'Enter meter name and meter number.'); return; }
    setState(() => saving = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('meters').add({
        'landlordId': uid, 'name': meterName.text.trim(), 'meterNumber': meterNumber.text.trim(),
        'billingType': billing, 'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => selectedMeterId = ref.id);
      meterName.clear(); meterNumber.clear();
      if (mounted) snack(context, 'Meter registered and selected. You can allocate this same meter to several houses.');
    } catch (e) { if (mounted) snack(context, 'Could not save meter: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> allocateUnit(Map<String, dynamic> meter) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final value = double.tryParse(amount.text.trim());
    final unit = houseNo.text.trim();
    if (uid == null || selectedMeterId == null || unit.isEmpty || value == null || value < 0) {
      snack(context, 'Select a registered meter, enter a house number and a valid amount.'); return;
    }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('electricityAllocations').add({
        'landlordId': uid, 'houseNo': unit, 'amount': value,
        'billingType': meter['billingType'] ?? billing,
        'meterId': selectedMeterId, 'meterReference': meter['meterNumber'] ?? '',
        'meterName': meter['name'] ?? '', 'interval': interval,
        'createdAt': FieldValue.serverTimestamp(),
      });
      houseNo.clear(); amount.clear();
      if (mounted) snack(context, 'House allocation saved. You can select this meter again for another house.');
    } catch (e) { if (mounted) snack(context, 'Could not save allocation: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Electricity management')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: uid == null ? null : FirebaseFirestore.instance.collection('meters').where('landlordId', isEqualTo: uid).snapshots(),
        builder: (context, meterSnap) {
          final meters = meterSnap.data?.docs ?? [];
          final validSelection = meters.any((m) => m.id == selectedMeterId);
          final selected = validSelection ? meters.firstWhere((m) => m.id == selectedMeterId) : null;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Register meters and keep prepaid or postpaid electricity records. One meter can be assigned to multiple houses.'),
            DropdownButtonFormField<String>(value: billing, decoration: const InputDecoration(labelText: 'Billing model for new meter'),
              items: const [DropdownMenuItem(value: 'prepaid', child: Text('Prepaid')), DropdownMenuItem(value: 'postpaid', child: Text('Postpaid'))],
              onChanged: (v) => setState(() => billing = v ?? 'prepaid')),
            const SizedBox(height: 10),
            TextField(controller: meterName, decoration: const InputDecoration(labelText: 'Meter label')),
            TextField(controller: meterNumber, decoration: const InputDecoration(labelText: 'Meter number / reference')),
            FilledButton(onPressed: saving ? null : saveMeter, child: const Text('REGISTER METER')),
            const Divider(height: 30),
            const Text('Allocate a meter to a house', style: TextStyle(fontWeight: FontWeight.bold)),
            if (meterSnap.hasError) errorView('Registered meters could not load.'),
            if (!meterSnap.hasData && !meterSnap.hasError) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              value: validSelection ? selectedMeterId : null,
              decoration: const InputDecoration(labelText: 'Choose registered meter'),
              items: meters.map((m) => DropdownMenuItem<String>(value: m.id,
                child: Text((m.data()['name'] ?? 'Meter').toString() + ' • ' + (m.data()['meterNumber'] ?? '').toString()))).toList(),
              onChanged: saving ? null : (v) => setState(() => selectedMeterId = v),
            ),
            if (selected != null) Padding(padding: const EdgeInsets.only(top: 6),
              child: Text("Selected: ${(selected.data()['billingType'] ?? 'prepaid').toString()} • This meter may be reused for other houses.")),
            DropdownButtonFormField<String>(value: interval, decoration: const InputDecoration(labelText: 'Charging / recording interval'),
              items: const [DropdownMenuItem(value: 'daily', child: Text('Daily')), DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly'))],
              onChanged: (v) => setState(() => interval = v ?? 'monthly')),
            TextField(controller: houseNo, decoration: const InputDecoration(labelText: 'House / unit number')),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (KSh) per interval')),
            FilledButton(onPressed: saving || selected == null ? null : () => allocateUnit(selected.data()), child: const Text('SAVE HOUSE ALLOCATION')),
            const SizedBox(height: 12),
            const Text('The same registered meter can be selected repeatedly and allocated to different houses. These are records only: no in-app payment, M-Pesa transaction or KPLC token purchase is made.'),
            const Divider(height: 24),
            const Text('Registered meters', style: TextStyle(fontWeight: FontWeight.bold)),
            ...meters.map((m) => ListTile(
              leading: const Icon(Icons.electric_meter_outlined),
              title: Text((m.data()['name'] ?? 'Meter').toString()),
              subtitle: Text((m.data()['meterNumber'] ?? '').toString() + ' • ' + (m.data()['billingType'] ?? 'prepaid').toString()),
              trailing: TextButton(onPressed: () => setState(() => selectedMeterId = m.id), child: const Text('SELECT')),
            )),
          ]);
        },
      ),
    );
  }
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(id);
      final user = await userRef.get();
      final data = user.data() ?? {};
      await userRef.update({
        'status': status, 'approvedAt': FieldValue.serverTimestamp(), 'approvedBy': uid,
      });
      if (status == 'active' && data['role'] == 'caretaker') {
        final propertyIds = (data['propertyIds'] as List?)?.whereType<String>().toList() ?? <String>[];
        for (final houseId in propertyIds) {
          await FirebaseFirestore.instance.collection('houses').doc(houseId).update({
            'caretakerIds': FieldValue.arrayUnion([id]),
          });
        }
      }
      final profile = uid == null ? null : await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final landlordId = profile?.data()?['role'] == 'landlord' ? uid : profile?.data()?['landlordId'];
      if (landlordId != null) {
        await FirebaseFirestore.instance.collection('activityLogs').add({
          'landlordId': landlordId, 'actorId': uid, 'actorName': profile?.data()?['displayName'] ?? 'Manager',
          'action': 'Account ' + status + ': ' + (data['displayName'] ?? data['email'] ?? id).toString(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
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
            stream: FirebaseFirestore.instance.collection('users').where('landlordId', isEqualTo: landlordId).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return errorView('Tenant accounts could not load.');
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final managerRole = p['role']?.toString() ?? 'tenant';
              final pendingAccounts = snap.data!.docs.where((doc) =>
                (doc.data()['role'] == 'tenant' || (managerRole == 'landlord' && doc.data()['role'] == 'caretaker')) &&
                doc.data()['status'] == 'pending').toList();
              if (pendingAccounts.isEmpty) return const EmptyView('No tenant or caretaker accounts awaiting approval.');
              return ListView(children: pendingAccounts.map((doc) {
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
      final confirmationRef = FirebaseFirestore.instance.collection('paymentConfirmations').doc(id);
      final confirmation = await confirmationRef.get();
      await confirmationRef.update({
        'status': 'confirmed_by_caretaker', 'confirmedBy': FirebaseAuth.instance.currentUser?.uid,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      final landlordId = confirmation.data()?['landlordId']?.toString();
      if (landlordId != null) await recordActivity(landlordId, 'Caretaker confirmed rent payment for house ' + (confirmation.data()?['houseNo'] ?? '').toString());
      if (context.mounted) snack(context, 'Payment marked as confirmed by caretaker.');
    } catch (e) { if (context.mounted) snack(context, 'Could not confirm payment: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Rent confirmations')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('paymentConfirmations').where('caretakerId', isEqualTo: uid).snapshots(),
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

Future<void> recordActivity(String landlordId, String action) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    await FirebaseFirestore.instance.collection('activityLogs').add({
      'landlordId': landlordId, 'actorId': user.uid,
      'actorName': profile.data()?['displayName'] ?? user.displayName ?? 'Account',
      'action': action, 'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Activity logging must never block the primary tenant/property operation.
  }
}

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
