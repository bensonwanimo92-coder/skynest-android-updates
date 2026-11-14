import 'package:cloud_firestore/cloud_firestore.dart';
import 'calls/skynest_call_screen.dart';
import 'security/message_encryption.dart';
import 'security/biometric_security.dart';
import 'reading/reading_hub.dart';
import 'messaging/direct_message_screen.dart';
import 'settings/sound_settings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
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
  // Render Flutter immediately. StartupGate restores an existing Firebase
  // session asynchronously so incoming-call notifications can reopen the app.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  unawaited(themeManager.load());
  runApp(const SkynestApp());
}

Future<bool>? _firebaseInitialization;

Future<bool> ensureFirebaseReady() async {
  if (firebaseReady) return true;
  _firebaseInitialization ??= () async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
      skyNestFirebaseReady.value = true;
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
  int? customColorValue;
  bool slideshowEnabled = true;

  Future<void> setSlideshowEnabled(bool enabled) async {
    slideshowEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('skynest_photo_slideshow', enabled);
    } catch (error) {
      debugPrint('Slideshow preference save failed: $error');
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('skynest_theme_name');
      final savedColor = prefs.getInt('skynest_custom_theme_color');
      slideshowEnabled = prefs.getBool('skynest_photo_slideshow') ?? true;
      if (savedName == 'Custom' && savedColor != null) {
        customColorValue = savedColor;
        value = Themes.custom(Color(savedColor));
        selectedName = 'Custom';
      } else {
        final matches = Themes.options.where((item) => item.name == savedName).toList();
        if (matches.isNotEmpty) {
          value = matches.first.theme;
          selectedName = matches.first.name;
        }
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Theme preference load failed: $error');
    }
  }

  Future<void> set(ThemeData theme, String name, {Color? customColor}) async {
    value = theme;
    selectedName = name;
    customColorValue = customColor?.value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('skynest_theme_name', name);
      if (customColor != null) {
        await prefs.setInt('skynest_custom_theme_color', customColor.value);
      } else {
        await prefs.remove('skynest_custom_theme_color');
      }
    } catch (error) {
      debugPrint('Theme preference save failed: $error');
    }
  }
}
final themeManager = ThemeManager();

class ThemeOption {
  final String name, description;
  final ThemeData theme;
  final Color primary, secondary;
  final IconData icon;
  final bool isPremium;
  const ThemeOption(this.name, this.description, this.theme, this.primary, this.secondary, this.icon, {this.isPremium = false});
}

class Themes {
  static ThemeData _make(Color seed, {Brightness brightness = Brightness.light, Color? surface}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, surface: surface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary, elevation: 3),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      listTileTheme: ListTileThemeData(iconColor: scheme.primary, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5)),
    );
  }

  static ThemeData custom(Color color) => _make(color);
  static final blue = _make(const Color(0xFF2463A6));
  static final dark = _make(const Color(0xFFB99A62), brightness: Brightness.dark);
  static final sunset = _make(const Color(0xFFC66A45));
  static final forest = _make(const Color(0xFF52745A));
  static final ivory = _make(const Color(0xFFB18A4A), surface: const Color(0xFFFFFBF3));
  static final ocean = _make(const Color(0xFF315D83));
  static final rose = _make(const Color(0xFF9A6572));
  static final slate = _make(const Color(0xFF64748B));
  static final shamba = _make(const Color(0xFF2E7D32), surface: const Color(0xFFE8F5E9));
  static final makuti = _make(const Color(0xFF795548), surface: const Color(0xFFEFEBE9));
  static final gold = _make(const Color(0xFFB8860B), surface: const Color(0xFFFFF8E1));

  static final options = <ThemeOption>[
    ThemeOption('Ivory & Gold Estate', 'Warm ivory, champagne and gold', ivory, const Color(0xFFF5EBDD), const Color(0xFFB18A4A), Icons.villa_outlined),
    ThemeOption('Midnight Luxury', 'Charcoal, black and silver', dark, const Color(0xFF17191D), const Color(0xFFC4A66A), Icons.directions_car_filled_outlined),
    ThemeOption('Ocean Residence', 'Navy blue and cool coastal tones', ocean, const Color(0xFF173B5E), const Color(0xFF78A9C9), Icons.water),
    ThemeOption('Forest Residence', 'Natural greens and soft stone', forest, const Color(0xFF294B37), const Color(0xFF9BAF8A), Icons.park_outlined),
    ThemeOption('Shamba Green', 'Fresh leafy green with a soft garden background', shamba, const Color(0xFF2E7D32), const Color(0xFF9CCC65), Icons.eco_outlined),
    ThemeOption('Makuti Brown', 'Earthy timber, woven makuti and warm sand', makuti, const Color(0xFF795548), const Color(0xFFD7A86E), Icons.roofing_outlined),
    ThemeOption('Gold Landlord', 'A premium-inspired champagne and gold finish', gold, const Color(0xFFB8860B), const Color(0xFFFFD54F), Icons.workspace_premium_outlined, isPremium: true),
    ThemeOption('Sunset Villa', 'Terracotta, sand and sunset gold', sunset, const Color(0xFF9D4F35), const Color(0xFFE8B878), Icons.wb_twilight),
    ThemeOption('Rosewood Classic', 'Muted rose and warm neutral shades', rose, const Color(0xFF76505B), const Color(0xFFD5AEB2), Icons.weekend_outlined),
    ThemeOption('Silver Slate', 'Clean slate, graphite and silver', slate, const Color(0xFF475569), const Color(0xFFCBD5E1), Icons.apartment_outlined),
    ThemeOption('Classic Blue', 'The familiar SkyNest blue', blue, const Color(0xFF174D83), const Color(0xFF79A9D6), Icons.home_work_outlined),
    ThemeOption('Flashy Dark', 'A simple dark appearance', dark, const Color(0xFF101114), const Color(0xFFB7B7B7), Icons.dark_mode),
  ];
}

final ValueNotifier<String> _activeScreenName = ValueNotifier<String>('SkyNest');
final _skynestRouteObserver = _SkynestRouteObserver();

class _SkynestRouteObserver extends NavigatorObserver {
  void _setRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;

    // Navigator restoration can notify observers while the widget tree is
    // still being built. Defer notifier updates until the frame is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activeScreenName.value != name) {
        _activeScreenName.value = name;
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _setRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setRoute(previousRoute);
  }
}

List<String> _backdropImagesFor(String screen, String themeName) {
  final key = (screen + ' ' + themeName).toLowerCase();
  if (key.contains('tenant') || key.contains('people') || key.contains('approval')) {
    return const [
      'https://images.unsplash.com/photo-1521737711867-e3b97375f902?w=1600&q=88',
      'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=1600&q=88',
      'https://images.unsplash.com/photo-1521791136064-7986c2920216?w=1600&q=88',
    ];
  }
  if (key.contains('payment') || key.contains('rent') || key.contains('calculator')) {
    return const [
      'https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?w=1600&q=88',
      'https://images.unsplash.com/photo-1554224154-22dec7ec8818?w=1600&q=88',
      'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=1600&q=88',
    ];
  }
  if (key.contains('house') || key.contains('property') || key.contains('vacant') || key.contains('theme')) {
    return const [
      'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=1600&q=88',
      'https://images.unsplash.com/photo-1600607687920-4e2a09cf159d?w=1600&q=88',
      'https://images.unsplash.com/photo-1600566753086-00f18fb6b3ea?w=1600&q=88',
    ];
  }
  return const [
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1600&q=88',
    'https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=1600&q=88',
    'https://images.unsplash.com/photo-1470252649378-9c29740c9fa8?w=1600&q=88',
  ];
}

class _AnimatedPhotoBackdrop extends StatefulWidget {
  final String screen;
  final String themeName;
  final bool enabled;
  const _AnimatedPhotoBackdrop({required this.screen, required this.themeName, required this.enabled});
  @override
  State<_AnimatedPhotoBackdrop> createState() => _AnimatedPhotoBackdropState();
}

class _AnimatedPhotoBackdropState extends State<_AnimatedPhotoBackdrop> {
  Timer? _timer;
  int _index = 0;
  @override
  void initState() { super.initState(); _start(); }
  @override
  void didUpdateWidget(covariant _AnimatedPhotoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screen != widget.screen || oldWidget.themeName != widget.themeName || oldWidget.enabled != widget.enabled) {
      _index = 0;
      _timer?.cancel();
      _start();
    }
  }
  void _start() {
    if (!widget.enabled) return;
    _timer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _backdropImagesFor(widget.screen, widget.themeName).length);
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final images = _backdropImagesFor(widget.screen, widget.themeName);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1100),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: Image.network(
        images[_index % images.length],
        key: ValueKey<String>(images[_index % images.length]),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => ColoredBox(color: Theme.of(context).colorScheme.surface),
      ),
    );
  }
}

class SkynestApp extends StatelessWidget {
  const SkynestApp({super.key, this.enableRemoteBackdrops = true});

  /// Allows deterministic widget tests and offline startup without changing
  /// the production default of photographic screen backdrops.
  final bool enableRemoteBackdrops;

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
        navigatorKey: skyNestNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: themeManager.value,
        navigatorObservers: [_skynestRouteObserver],
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            if (enableRemoteBackdrops)
              ValueListenableBuilder<String>(
                valueListenable: _activeScreenName,
                builder: (context, screen, _) => _AnimatedPhotoBackdrop(
                  screen: screen,
                  enabled: themeManager.slideshowEnabled,
                  themeName: themeManager.selectedName,
                ),
              )
            else
              ColoredBox(color: Theme.of(context).colorScheme.surface),
            ColoredBox(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.68)
                  : Colors.white.withOpacity(0.70),
            ),
            if (child != null) IncomingCallHost(child: child),
          ],
        ),
        home: StartupGate(enableRemoteImages: enableRemoteBackdrops),
      );
    },
  );
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.enableRemoteImages = true});

  final bool enableRemoteImages;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _checkingSession = true;
  Widget? _restoredHome;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      if (await ensureFirebaseReady()) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (profile.data()?['status'] == 'active') {
            _restoredHome = const DashboardScreen();
          } else if (profile.data()?['status'] == 'pending') {
            _restoredHome = const PendingApprovalScreen();
          }
        }
      }
    } catch (error) {
      debugPrint('Session restore skipped: $error');
    }
    if (mounted) setState(() => _checkingSession = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return Scaffold(
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.apartment_rounded, size: 52, color: brand),
            const SizedBox(height: 14),
            const Text('SkyNest', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 10),
            Text('Restoring your session…', style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
      );
    }
    return BiometricLockGate(child: _restoredHome ?? LoginScreen(enableRemoteImages: widget.enableRemoteImages));
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.enableRemoteImages = true});

  final bool enableRemoteImages;
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
    var address = email.text.trim();
    if (address.isEmpty) {
      final resetEmail = TextEditingController();
      final entered = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset your password'),
          content: TextField(
            controller: resetEmail,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(
              labelText: 'Account email address',
              hintText: 'you@gmail.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, resetEmail.text.trim()),
              child: const Text('SEND RESET LINK')),
          ],
        ),
      );
      resetEmail.dispose();
      if (entered == null) return;
      address = entered.trim();
      email.text = address;
    }
    if (!validEmail(address)) {
      message('Enter a valid Gmail or other account email address.');
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
      message('Firebase accepted the reset request for $address. Check that inbox, including Spam and Promotions. Delivery depends on the Firebase Authentication email settings.');
    } on FirebaseAuthException catch (e) {
      debugPrint('SkyNest password reset failed: code=${e.code}, message=${e.message}');
      message(resetPasswordMessage(e));
    } catch (error) {
      debugPrint('SkyNest password reset request failed: $error');
      message('Could not contact Firebase to request a reset link. Check your internet connection and try again.');
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
                            image: widget.enableRemoteImages
                                ? const DecorationImage(
                                    image: NetworkImage('https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=1200&q=90'),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [const Color(0xFF090D16).withOpacity(0.96), const Color(0xFF17243A).withOpacity(0.91)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD4AF37).withOpacity(0.16),
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
                                child: const Icon(Icons.apartment_rounded, size: 43, color: Color(0xFFF5D76E)),
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
                              backgroundColor: const Color(0xFF101827),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: busy
                                ? const SizedBox(height: 21, width: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.login_rounded),
                                      SizedBox(width: 10),
                                      Text('SIGN IN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFFF5D76E))),
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
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    initializePushNotifications();
    // Ads are optional and must never block the dashboard.
    _initializeBannerAd();
  }

  Future<void> _initializeBannerAd() async {
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    banner = BannerAd(
      adUnitId: skynestBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => loaded = true); },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          banner = null;
        },
      ),
    )..load();
  }

  Future<void> _loadUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !firebaseReady) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() => userRole = doc.data()?['role']?.toString() ?? 'landlord');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    banner?.dispose();
    super.dispose();
  }

  void _open(BuildContext context, _MenuItem item) {
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        settings: RouteSettings(name: item.title),
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => item.page,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.035, 0.025), end: Offset.zero).animate(curved),
              child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(curved), child: child),
            ),
          );
        },
      ),
    );
  }

  Future<void> _previewModule(BuildContext context, _MenuItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: item.color.withOpacity(0.14),
                  child: Icon(item.icon, color: item.color, size: 27),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Preview this SkyNest section before opening it. Continue when you are ready to view its tools and records.',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _open(context, item);
                },
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: const Text('Continue to section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[];
    if (userRole == 'landlord') {
      items.addAll([
        _MenuItem('Houses', Icons.home_work_outlined, Colors.orange, const HousesScreen()),
        _MenuItem('Account approvals', Icons.how_to_reg_outlined, Colors.green, const TenantApprovalsScreen()),
        _MenuItem('Tenants', Icons.people_alt_outlined, Colors.green, const TenantsScreen()),
        _MenuItem('Payments', Icons.payments_outlined, Colors.blue, const PaymentsScreen()),
        _MenuItem('Tenant payment submissions', Icons.fact_check_outlined, Colors.teal, const PaymentSubmissionsScreen()),
        _MenuItem('Caretakers & invitations', Icons.badge_outlined, Colors.teal, const InvitationsScreen()),
        _MenuItem('Complaints', Icons.support_agent, Colors.deepOrange, const ComplaintsScreen()),
        _MenuItem('Tenant groups', Icons.groups_outlined, Colors.indigo, const TenantGroupsScreen()),
        _MenuItem('Notices', Icons.campaign_outlined, Colors.purple, const NoticesScreen()),
        _MenuItem('Electricity', Icons.electric_bolt, Colors.amber, const ElectricityScreen()),
        _MenuItem('Activity log', Icons.fact_check_outlined, Colors.blueGrey, const ActivityLogScreen()),
        _MenuItem('Reports', Icons.analytics_outlined, Colors.deepPurple, const ReportsScreen()),
        _MenuItem('Calculator', Icons.calculate_outlined, Colors.purple, const CalculatorScreen()),
        _MenuItem('Calendar', Icons.calendar_month, Colors.cyan, const CalendarScreen()),
        _MenuItem('Plans', Icons.assignment_outlined, Colors.indigo, const PlansScreen()),
        _MenuItem('Achievements', Icons.emoji_events_outlined, Colors.amber, const AchievementsScreen()),
        _MenuItem('Pamphlets', Icons.menu_book_outlined, Colors.brown, const PamphletsScreen()),
        _MenuItem('Reading & media hub', Icons.auto_stories_rounded, Colors.teal, const ReadingHubScreen()),
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
        _MenuItem('Reading & media hub', Icons.auto_stories_rounded, Colors.teal, const ReadingHubScreen()),
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
        _MenuItem('Reading & media hub', Icons.auto_stories_rounded, Colors.teal, const ReadingHubScreen()),
        _MenuItem('Themes', Icons.palette_outlined, Colors.pink, const ThemesScreen()),
      ]);
    }

    items.add(_MenuItem('Sounds & vibration', Icons.volume_up_rounded, Colors.deepOrange, const SoundSettingsScreen()));
    items.add(_MenuItem('Security & fingerprint', Icons.fingerprint_rounded, Colors.blueGrey, const SecuritySettingsScreen()));

    final query = searchQuery.trim().toLowerCase();
    final filteredItems = items.where((item) => item.title.toLowerCase().contains(query)).toList();
    final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final initial = displayName != null && displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : 'S';
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final firstName = displayName != null && displayName.trim().isNotEmpty
        ? displayName.trim().split(RegExp(r'\s+')).first
        : 'there';
    final dailyMessage = userRole == 'landlord'
        ? 'Your properties, people and plans — all moving together.'
        : userRole == 'caretaker'
            ? 'Your daily property tasks, organised in one place.'
            : 'Your home updates and helpful tools, all in one place.';

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation), child: child),
          ),
          child: Text('SkyNest • ' + userRole[0].toUpperCase() + userRole.substring(1), key: ValueKey<String>(userRole)),
        ),
        actions: [
          IconButton(
            tooltip: 'Notices and announcements',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const NoticesScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: FirebaseAuth.instance.currentUser?.photoURL != null
                    ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                    : null,
                child: FirebaseAuth.instance.currentUser?.photoURL == null
                    ? Text(initial, style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ))
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Account and role',
            icon: const Icon(Icons.manage_accounts_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountRoleScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (firebaseReady) await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedPhotoBackdrop(
            screen: 'Dashboard',
            themeName: themeManager.selectedName,
            enabled: themeManager.slideshowEnabled,
          ),
          ColoredBox(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.88),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Color.lerp(
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.tertiary,
                          0.52,
                        )!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.20),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$greeting, $firstName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              dailyMessage,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.88),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 11),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 13,
                                  color: Colors.white.withOpacity(0.88),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  DateFormat('EEEE, d MMMM').format(now),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.92),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.22)),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search modules...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => searchQuery = ''),
                          ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filteredItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 10),
                              const Text('No modules found'),
                              const SizedBox(height: 4),
                              Text('Try another search term.',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                        itemCount: filteredItems.length,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          childAspectRatio: 1.02,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final scheme = Theme.of(context).colorScheme;
                          final tint = Color.lerp(item.color, scheme.surface, 0.84)!;
                          var hovered = false;
                          return StatefulBuilder(
                            builder: (context, setTileState) => MouseRegion(
                              onEnter: (_) => setTileState(() => hovered = true),
                              onExit: (_) => setTileState(() => hovered = false),
                              child: AnimatedScale(
                                scale: hovered ? 1.035 : 1.0,
                                duration: const Duration(milliseconds: 170),
                                curve: Curves.easeOutBack,
                                child: Card(
                            color: tint,
                            elevation: hovered ? 7 : 3,
                            shadowColor: item.color.withOpacity(0.30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () async {
                                await SkyNestFeedback.playTap();
                                if (!context.mounted) return;
                                await _previewModule(context, item);
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    _menuImageFor(item.title),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => ColoredBox(color: tint),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.20),
                                          Colors.black.withOpacity(0.76),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: -13,
                                    top: -18,
                                    child: Icon(item.icon, size: 92, color: Colors.white.withOpacity(0.16)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(15),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 58,
                                          height: 58,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.20),
                                            border: Border.all(color: Colors.white.withOpacity(0.35)),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          child: Icon(item.icon, size: 29, color: Colors.white),
                                        ),
                                        const Spacer(),
                                        Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            height: 1.15,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        const Row(
                                          children: [
                                            Text('Open module', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                            SizedBox(width: 5),
                                            Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                                ),
                              ),
                            ),
                          ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: loaded && banner != null
          ? SizedBox(
              height: banner!.size.height.toDouble(),
              child: AdWidget(ad: banner!),
            )
          : null,
    );
  }
}

class AccountRoleScreen extends StatefulWidget {
  const AccountRoleScreen({super.key});
  @override
  State<AccountRoleScreen> createState() => _AccountRoleScreenState();
}

class _AccountRoleScreenState extends State<AccountRoleScreen> {
  final invitationCode = TextEditingController();
  String role = '';
  String status = '';
  bool loading = true;
  bool saving = false;
  bool photoBusy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    invitationCode.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = snapshot.data() ?? <String, dynamic>{};
      if (mounted) setState(() {
        role = data['role']?.toString() ?? '';
        status = data['status']?.toString() ?? '';
        loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);
        snack(context, 'Could not load account details: ' + error.toString());
      }
    }
  }

  Future<void> _syncGroupMemberPhoto(String uid, String? photoUrl) async {
    final groups = await FirebaseFirestore.instance.collection('groups')
        .where('memberIds', arrayContains: uid).get();
    for (var start = 0; start < groups.docs.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = groups.docs.skip(start).take(400);
      for (final group in chunk) {
        batch.set(group.reference.collection('members').doc(uid), {
          'photoUrl': photoUrl,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _changeProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || photoBusy) return;
    setState(() => photoBusy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 84,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (picked == null) return;
      final file = File(picked.path);
      final length = await file.length();
      if (length > 5 * 1024 * 1024) {
        throw StateError('Choose an image smaller than 5 MB.');
      }
      final ref = FirebaseStorage.instance.ref()
          .child('profile_photos').child(user.uid).child('profile.jpg');
      final task = await ref.putFile(file, SettableMetadata(
        contentType: picked.mimeType ?? 'image/jpeg',
        cacheControl: 'private,max-age=3600',
      ));
      final url = await task.ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': url,
        'photoPath': ref.fullPath,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.updatePhotoURL(url);
      await _syncGroupMemberPhoto(user.uid, url);
      await user.reload();
      if (mounted) snack(context, 'Profile photo updated.');
    } catch (error) {
      if (mounted) snack(context, 'Photo upload failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || photoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('Your account will return to its initials avatar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('REMOVE')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => photoBusy = true);
    try {
      final ref = FirebaseStorage.instance.ref()
          .child('profile_photos').child(user.uid).child('profile.jpg');
      try { await ref.delete(); } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': FieldValue.delete(),
        'photoPath': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.updatePhotoURL(null);
      await _syncGroupMemberPhoto(user.uid, null);
      await user.reload();
      if (mounted) snack(context, 'Profile photo removed.');
    } catch (error) {
      if (mounted) snack(context, 'Could not remove photo: ' + error.toString());
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  Future<Map<String, dynamic>> _sendRoleChange(String targetRole) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in again before changing your role.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw StateError('Could not refresh your secure sign-in token.');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(Uri.parse(
        'https://us-central1-hello-chuka.cloudfunctions.net/changeAccountRole',
      ));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + token);
      request.headers.contentType = ContentType.json;
      final data = <String, dynamic>{'targetRole': targetRole};
      if (targetRole == 'tenant') data['invitationCode'] = invitationCode.text.trim().toUpperCase();
      request.write(jsonEncode({'data': data}));
      final response = await request.close().timeout(const Duration(seconds: 35));
      final responseText = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 20));
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(responseText) as Map<String, dynamic>;
      } catch (_) {
        throw StateError('The role service returned an unreadable response. Please try again later.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded.containsKey('error')) {
        final error = decoded['error'];
        final message = error is Map
            ? error['message']?.toString()
            : null;
        throw StateError(message ?? 'Role change failed (HTTP ' + response.statusCode.toString() + ').');
      }
      final result = decoded['result'];
      if (result is! Map) throw StateError('The role service did not confirm the change.');
      return Map<String, dynamic>.from(result);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _changeRole(String targetRole) async {
    if (saving) return;
    if (targetRole == 'tenant' && invitationCode.text.trim().length < 6) {
      snack(context, 'Enter the Tenant invitation code supplied by your new landlord.');
      return;
    }
    final targetName = targetRole == 'tenant' ? 'Tenant' : 'Landlord';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Switch to ' + targetName + '?'),
        content: Text(targetRole == 'tenant'
          ? 'Your account will keep the same email and password. You must use a valid Tenant invitation code, and the new landlord must approve your account. Existing properties or active linked tenants/caretakers must be transferred or cleared first. Existing history will not be deleted.'
          : 'Your account will become a Landlord account. You cannot switch while you have an assigned house or a pending house request. Your existing account and sign-in details will be kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('CONFIRM SWITCH')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      final result = await _sendRoleChange(targetRole);
      if (!mounted) return;
      final newRole = result['role']?.toString() ?? targetRole;
      final newStatus = result['status']?.toString() ?? '';
      snack(context, 'Your account role is now ' + newRole + '.');
      if (newRole == 'tenant' && newStatus == 'pending') {
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute<void>(builder: (_) => const PendingApprovalScreen()), (_) => false);
      } else {
        Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute<void>(builder: (_) => const DashboardScreen()), (_) => false);
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Bad state: ', '');
        snack(context, message);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & role')),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(18), children: [
            Card(child: ListTile(
              leading: const Icon(Icons.account_circle_outlined, size: 38),
              title: Text(role.isEmpty ? 'Account role unavailable' : role[0].toUpperCase() + role.substring(1),
                style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Account status: ' + (status.isEmpty ? 'unknown' : status)),
            )),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.userChanges(),
                    initialData: FirebaseAuth.instance.currentUser,
                    builder: (context, snapshot) {
                      final user = snapshot.data;
                      final photo = user?.photoURL;
                      final name = user?.displayName?.trim() ?? '';
                      return CircleAvatar(
                        radius: 34,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo == null || photo.isEmpty
                          ? Text(name.isEmpty ? 'S' : name.characters.first.toUpperCase(),
                              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800))
                          : null,
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Profile photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('Add a clear photo so people recognise you in groups and private chats.',
                      style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 9),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: photoBusy ? null : _changeProfilePhoto,
                        icon: photoBusy
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_camera_outlined, size: 17),
                        label: Text(photoBusy ? 'Please wait…' : 'Change photo'),
                      ),
                      TextButton(
                        onPressed: photoBusy ? null : _removeProfilePhoto,
                        child: const Text('Remove'),
                      ),
                    ]),
                  ])),
                ]),
              ),
            ),
            if (role == 'landlord') ...[
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Switch to Tenant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('If you created your account as a Landlord by mistake, you can use the same account to join another property as a Tenant. Ask that landlord for a Tenant invitation code.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: invitationCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Tenant invitation code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: saving ? null : () => _changeRole('tenant'),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(saving ? 'PLEASE WAIT...' : 'SWITCH TO TENANT'),
                  )),
                ]),
              )),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('Safety check: SkyNest will block this switch if you still own properties or have active tenants/caretakers linked to your account. Transfer those responsibilities first.'),
              ),
            ] else if (role == 'tenant') ...[
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Switch to Landlord', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('You can return to a Landlord account if you have no assigned house and no pending house request. Your previous account history is retained.'),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: saving ? null : () => _changeRole('landlord'),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(saving ? 'PLEASE WAIT...' : 'SWITCH TO LANDLORD'),
                  )),
                ]),
              )),
            ] else if (role == 'caretaker') ...[
              const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Caretaker access is assigned by a Landlord. Ask the Landlord to remove or change your assignment before changing account type.'),
              )),
            ] else ...[
              const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Your account role could not be identified. Please sign out and sign in again, or contact support.'),
              )),
            ],
            if (saving) const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          ]),
    );
  }
}

class _MenuItem {
  final String title; final IconData icon; final Color color; final Widget page;
  const _MenuItem(this.title, this.icon, this.color, this.page);
}

class _StaggeredPressCard extends StatefulWidget {
  final int index;
  final Widget child;
  final VoidCallback? onTap;
  const _StaggeredPressCard({required this.index, required this.child, this.onTap});
  @override
  State<_StaggeredPressCard> createState() => _StaggeredPressCardState();
}
class _StaggeredPressCardState extends State<_StaggeredPressCard> {
  bool visible = false;
  bool pressed = false;
  Timer? entryTimer;
  @override
  void initState() {
    super.initState();
    entryTimer = Timer(Duration(milliseconds: widget.index * 50), () {
      if (mounted) setState(() => visible = true);
    });
  }
  @override
  void dispose() { entryTimer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 300),
    child: AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 0.07),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) => setState(() => pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: AnimatedScale(
          scale: pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    ),
  );
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
            await FirebaseFirestore.instance.collection('houses').add({
              'houseNo': number.text.trim(), 'rent': double.parse(rent.text),
              'isOccupied': false, 'status': 'vacant', 'landlordId': FirebaseAuth.instance.currentUser?.uid,
              'caretakerIds': <String>[], 'createdAt': FieldValue.serverTimestamp(),
              'createdBy': FirebaseAuth.instance.currentUser?.uid,
            });
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
          final occupied = d['isOccupied'] == true;
          final colors = Theme.of(context).colorScheme;
          final occupancy = occupied ? 1.0 : 0.0;
          return _StaggeredPressCard(
            index: index,
            onTap: () => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
              title: Text('House ' + (d['houseNo']?.toString() ?? '')),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(currency.format(rentValue) + ' monthly rent'),
                const SizedBox(height: 8),
                Text(occupied ? 'Currently occupied' : 'Currently vacant'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: occupancy, minHeight: 7),
                const SizedBox(height: 4),
                Text(occupied ? '1 of 1 unit occupied' : '0 of 1 units occupied'),
              ]),
              actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE'))],
            )),
            child: Card(
              margin: const EdgeInsets.fromLTRB(14, 7, 14, 10),
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 142,
                  width: double.infinity,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(
                      _skynestPropertyPhotos[index % _skynestPropertyPhotos.length],
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) => progress == null ? child : Container(
                        color: colors.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const SizedBox(width: 90, child: LinearProgressIndicator(minHeight: 3)),
                      ),
                      errorBuilder: (_, __, ___) => ColoredBox(color: colors.surfaceContainerHighest,
                        child: const Icon(Icons.apartment_rounded, size: 54)),
                    ),
                    const DecoratedBox(decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)]),
                    )),
                    Positioned(left: 15, right: 8, bottom: 10, child: Row(children: [
                      Expanded(child: Text('House ' + (d['houseNo']?.toString() ?? ''),
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800))),
                      IconButton(
                        tooltip: 'Delete house',
                        color: Colors.white,
                        onPressed: () => confirmDelete(context, 'Delete this house?', () => doc.reference.delete()),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ])),
                  ]),
                ),
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(currency.format(rentValue) + ' / month',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: occupied ? const Color(0x222D8A72) : const Color(0x222463A6),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(occupied ? 'Occupied' : 'Vacant',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: occupied ? const Color(0xFF287D66) : const Color(0xFF2463A6))),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(value: occupancy, minHeight: 7,
                        color: occupancy == 1 ? Colors.green : Colors.orange,
                        backgroundColor: colors.surfaceContainerHighest))),
                    const SizedBox(width: 10),
                    Text(occupied ? '1/1 occupied' : '0/1 occupied',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ]),
                ])),
              ]),
            ),
          );
        }).toList());
      },
    ),
  );
}

class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key});
  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}
class _TenantsScreenState extends State<TenantsScreen> {
  String selectedFilter = 'All';
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
            await FirebaseFirestore.instance.collection('tenants').add({
              'name': name.text.trim(), 'phone': phone.text.trim(), 'houseNo': house.text.trim(),
              'rentAmount': double.parse(rent.text), 'createdAt': FieldValue.serverTimestamp(),
              'createdBy': FirebaseAuth.instance.currentUser?.uid, 'landlordId': FirebaseAuth.instance.currentUser?.uid,
              'status': 'active',
            });
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
        final docs = s.data!.docs.where((doc) {
          final d = doc.data();
          final status = (d['status']?.toString() ?? 'active').toLowerCase();
          final balance = (d['balance'] ?? d['outstandingBalance'] ?? 0);
          final hasDebt = balance is num && balance > 0;
          if (selectedFilter == 'Overdue') return hasDebt || status == 'overdue';
          if (selectedFilter == 'New') return status == 'new';
          if (selectedFilter == 'Vacating') return status == 'vacating' || status == 'moved_out';
          return true;
        }).toList()
          ..sort((a, b) => (a.data()['name']?.toString() ?? '').toLowerCase()
            .compareTo((b.data()['name']?.toString() ?? '').toLowerCase()));
        return Column(children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: ['All', 'Overdue', 'New', 'Vacating'].map((filter) => Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(label: Text(filter), selected: selectedFilter == filter,
                onSelected: (_) => setState(() => selectedFilter = filter)),
            )).toList())),
          Expanded(child: docs.isEmpty
            ? const EmptyView('No tenants match this filter.')
            : ListView(children: docs.map((doc) {
              final d = doc.data();
              final rentValue = (d['rentAmount'] as num?)?.toDouble() ?? 0;
              final balanceRaw = d['balance'] ?? d['outstandingBalance'] ?? 0;
              final balance = balanceRaw is num ? balanceRaw.toDouble() : 0.0;
              final status = (d['status']?.toString() ?? 'active').toLowerCase();
              final active = !['moved_out', 'inactive', 'vacating'].contains(status);
              final contractEnd = d['contractEnd'];
              final daysLeft = contractEnd is Timestamp ? contractEnd.toDate().difference(DateTime.now()).inDays : null;
              final familyCount = d['familyCount'];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(child: Row(children: [
                  Container(width: 4, color: balance > 0 ? Colors.red : active ? Colors.green : Colors.grey),
                  Expanded(child: ListTile(
                    leading: Stack(clipBehavior: Clip.none, children: [
                      CircleAvatar(child: Text((d['name']?.toString().trim().isNotEmpty == true)
                        ? d['name'].toString().trim().substring(0, 1).toUpperCase() : 'T')),
                      Positioned(right: -1, bottom: -1, child: Container(width: 12, height: 12,
                        decoration: BoxDecoration(color: active ? Colors.green : Colors.grey,
                          shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2)))),
                    ]),
                    title: Row(children: [
                      Expanded(child: Text(d['name']?.toString() ?? 'Tenant', style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (balance > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                        child: const Text('BALANCE DUE', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.w900))),
                    ]),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('House ' + (d['houseNo']?.toString() ?? '-') + ' • ' + (d['phone']?.toString() ?? '-')),
                      Text(currency.format(rentValue) + ' / month' + (balance > 0 ? ' • Due ' + currency.format(balance) : '')),
                      if (daysLeft != null) Text(daysLeft < 0 ? 'Contract ended' : 'Contract: $daysLeft days left',
                        style: TextStyle(fontSize: 11, color: daysLeft <= 14 ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (familyCount is num) Text('Family members: $familyCount', style: const TextStyle(fontSize: 11)),
                    ]),
                    isThreeLine: true,
                    trailing: IconButton(icon: const Icon(Icons.person_remove_alt_1, color: Colors.red),
                      onPressed: () => confirmDelete(context, 'Remove ' + (d['name']?.toString() ?? 'this tenant') + '? Payment records will remain.', () => doc.reference.delete())),
                  )),
                ])),
              );
            }).toList())),
        ]);
      },
    ),
  );
}

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  Future<bool> _confirmReceived(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Confirm payment received?'),
      content: Text('Only confirm if you have actually received KES ' +
        currency.format((doc.data()['amount'] as num?)?.toDouble() ?? 0) + '. This updates the payment record.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('CONFIRM RECEIPT')),
      ],
    ));
    if (confirmed != true) return false;
    try {
      await doc.reference.update({'status': 'Paid', 'confirmedAt': FieldValue.serverTimestamp(), 'confirmedBy': FirebaseAuth.instance.currentUser?.uid});
      HapticFeedback.mediumImpact();
      if (context.mounted) snack(context, 'Payment marked as received.');
    } catch (e) {
      if (context.mounted) snack(context, 'Could not confirm payment: ' + e.toString());
    }
    return false;
  }
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
          final status = (d['status']?.toString() ?? 'Pending').toLowerCase();
          final paid = status.contains('paid') || status.contains('received');
          final partial = status.contains('partial');
          final overdue = status.contains('overdue');
          final railColor = paid ? Colors.green : overdue ? Colors.red : partial ? Colors.orange : Colors.grey;
          final method = (d['method']?.toString() ?? 'Manual').toLowerCase();
          final methodIcon = method.contains('mpesa') ? Icons.phone_android
            : method.contains('bank') ? Icons.account_balance : Icons.payments_outlined;
          final created = d['createdAt'];
          final createdLabel = created is Timestamp ? DateFormat('dd MMM yyyy').format(created.toDate()) : 'Date pending';
          final due = d['dueDate'];
          final dueLabel = due is Timestamp ? 'Due ' + DateFormat('dd MMM yyyy').format(due.toDate()) : createdLabel;
          return Dismissible(
            key: ValueKey('payment-' + doc.id),
            direction: paid ? DismissDirection.none : DismissDirection.startToEnd,
            confirmDismiss: (_) => _confirmReceived(context, doc),
            background: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 22),
              decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(18)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8),
                Text('Confirm received', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ]),
            ),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: IntrinsicHeight(child: Row(children: [
                Container(width: 4, color: railColor),
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(13, 13, 15, 13), child: Row(children: [
                  CircleAvatar(backgroundColor: railColor.withOpacity(0.12),
                    child: Icon(Icons.person_outline, color: railColor)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['tenantName']?.toString() ?? 'Tenant', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text((d['houseNo']?.toString() ?? 'House not set') + ' • ' + status,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: railColor, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(methodIcon, size: 14, color: method.contains('mpesa') ? Colors.green : method.contains('bank') ? Colors.blue : Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(child: Text(dueLabel, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    ]),
                  ])),
                  const SizedBox(width: 8),
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(currency.format(value), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(createdLabel, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ]))),
              ])),
            ),
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
  final tenant = TextEditingController(), house = TextEditingController(), amount = TextEditingController(), transactionCode = TextEditingController();
  String paymentMethod = 'mpesa';
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
  void dispose() { tenant.dispose(); house.dispose(); amount.dispose(); transactionCode.dispose(); super.dispose(); }
  Future<void> savePayment() async {
    final value = double.tryParse(amount.text.trim());
    final code = transactionCode.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (tenant.text.trim().isEmpty || value == null || value <= 0) { snack(context, 'Enter tenant name and a valid amount.'); return; }
    if (paymentMethod == 'mpesa' && (code.length < 8 || code.length > 16 || !RegExp(r'^[A-Z0-9]+').hasMatch(code))) {
      snack(context, 'Enter a valid M-Pesa transaction code (8–16 letters or numbers).');
      return;
    }
    setState(() => saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Please sign in again.');
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? {};
      if (p['role'] == 'tenant') {
        final landlordId = p['landlordId']?.toString();
        if (landlordId == null || landlordId.isEmpty) throw StateError('Your tenant account is not linked to a landlord.');
        final submissionRef = FirebaseFirestore.instance.collection('paymentSubmissions').doc();
        final batch = FirebaseFirestore.instance.batch();
        batch.set(submissionRef, {
          'tenantId': uid, 'tenantName': tenant.text.trim(), 'landlordId': landlordId,
          'houseId': p['houseId'], 'houseNo': house.text.trim(), 'amount': value,
          'method': paymentMethod.toUpperCase(), 'transactionCode': paymentMethod == 'mpesa' ? code : '',
          'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
        });
        if (paymentMethod == 'mpesa') {
          final codeRef = FirebaseFirestore.instance.collection('mpesaTransactionCodes').doc(code);
          batch.set(codeRef, {
            'tenantId': uid, 'landlordId': landlordId, 'submissionId': submissionRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        if (mounted) { amount.clear(); snack(context, 'Payment details sent to your landlord for verification. No automatic M-Pesa payment was made.'); }
      } else {
        final paymentRef = await FirebaseFirestore.instance.collection('payments').add({
          'tenantName': tenant.text.trim(), 'houseNo': house.text.trim(), 'amount': value,
          'method': paymentMethod.toUpperCase(), 'transactionCode': paymentMethod == 'mpesa' ? code : '', 'status': 'Pending verification',
          'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(), 'createdBy': uid,
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
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: paymentMethod,
        decoration: const InputDecoration(labelText: 'Payment method'),
        items: const [
          DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
          DropdownMenuItem(value: 'cash', child: Text('Cash')),
          DropdownMenuItem(value: 'bank', child: Text('Bank')),
        ],
        onChanged: saving ? null : (value) => setState(() => paymentMethod = value ?? 'mpesa'),
      ),
      if (paymentMethod == 'mpesa') ...[
        const SizedBox(height: 12),
        TextField(controller: transactionCode, textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'M-Pesa transaction code', border: OutlineInputBorder())),
      ],
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
  Future<bool> _reviewBySwipe(BuildContext context, String id, Map<String, dynamic> data, DismissDirection direction) async {
    final approve = direction == DismissDirection.startToEnd;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(approve ? 'Verify this payment?' : 'Reject this submission?'),
      content: Text(approve
        ? 'Confirm only after you have verified receipt of ' + currency.format((data['amount'] as num?)?.toDouble() ?? 0) + '. The amount will be added to the payment ledger.'
        : 'This will mark the tenant payment submission as rejected.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
        FilledButton(
          style: approve ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(approve ? 'VERIFY & RECORD' : 'REJECT'),
        ),
      ],
    ));
    if (confirmed != true) return false;
    if (approve) {
      await markReceived(context, id, data);
    } else {
      try {
        await FirebaseFirestore.instance.collection('paymentSubmissions').doc(id).update({
          'status': 'rejected', 'reviewedAt': FieldValue.serverTimestamp(),
        });
        if (context.mounted) snack(context, 'Payment submission rejected.');
      } catch (e) {
        if (context.mounted) snack(context, 'Could not reject submission: ' + e.toString());
      }
    }
    HapticFeedback.mediumImpact();
    return false;
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
          return ListView(children: snap.data!.docs.asMap().entries.map((entry) {
            final queueIndex = entry.key + 1;
            final doc = entry.value;
            final d = doc.data();
            final status = d['status']?.toString() ?? 'pending';
            final created = d['createdAt'];
            final age = created is Timestamp ? DateTime.now().difference(created.toDate()) : null;
            final ageLabel = age == null ? 'Just submitted' : age.inMinutes < 1 ? 'Just now'
              : age.inHours < 1 ? '${age.inMinutes}m ago'
              : age.inDays < 1 ? '${age.inHours}h ago' : '${age.inDays}d ago';
            final canSwipe = status == 'pending';
            return Dismissible(
              key: ValueKey('submission-' + doc.id),
              direction: canSwipe ? DismissDirection.horizontal : DismissDirection.none,
              confirmDismiss: (direction) => _reviewBySwipe(context, doc.id, d, direction),
              background: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 7),
                  Text('Verify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
              ),
              secondaryBackground: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(width: 7),
                  Icon(Icons.close_rounded, color: Colors.white),
                ]),
              ),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: status == 'received' ? Colors.green.withOpacity(0.12) : status == 'rejected' ? Colors.red.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                    child: Icon(status == 'received' ? Icons.verified : status == 'rejected' ? Icons.cancel_outlined : Icons.receipt_long,
                      color: status == 'received' ? Colors.green : status == 'rejected' ? Colors.red : Colors.orange),
                  ),
                  title: Text(d['tenantName']?.toString() ?? 'Tenant'),
                  subtitle: Text('Queue #$queueIndex • House ' + (d['houseNo'] ?? '').toString() + ' • ' +
                    currency.format((d['amount'] as num?)?.toDouble() ?? 0) + ' • ' + status + '\n' + ageLabel),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
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
                ),
              ),
            );
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
  final rent = TextEditingController(text: '10000');
  final rentIncome = TextEditingController(text: '10000');
  final quickEntry = TextEditingController();
  double? quickResult;
  final deposit = TextEditingController(text: '10000');
  final arrears = TextEditingController(text: '0');
  final expenses = TextEditingController(text: '0');
  final loan = TextEditingController(text: '1000000');
  final annualRate = TextEditingController(text: '12');
  final loanMonths = TextEditingController(text: '120');
  final materials = TextEditingController(text: '50000');
  final contributors = TextEditingController(text: '2');
  final secondHouseRent = TextEditingController(text: '12000');
  final exchangeRate = TextEditingController(text: '130');
  final note = TextEditingController();
  bool showUsd = false;

  double value(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double get rentValue => value(rent);
  double get arrearsValue => value(arrears);
  double get depositValue => value(deposit);
  double get lateFee => arrearsValue * 0.05;
  double get amountDue => rentValue + depositValue + arrearsValue + lateFee;
  double get profit => value(rentIncome) - value(expenses);
  double get loanPayment {
    final principal = value(loan);
    final months = value(loanMonths);
    final annualPercent = value(annualRate);
    if (principal <= 0 || months <= 0 || annualPercent < 0 || months != months.roundToDouble()) return 0;
    final monthlyRate = annualPercent / 1200;
    if (monthlyRate == 0) return principal / months;
    final factor = math.pow(1 + monthlyRate, months).toDouble();
    return principal * monthlyRate * factor / (factor - 1);
  }
  double get materialShare => value(contributors) <= 0 ? 0 : value(materials) / value(contributors);
  double get exchange => value(exchangeRate) <= 0 ? 130 : value(exchangeRate);

  double? parseQuickExpression(String input) {
    final pattern = RegExp(r'^[ ]*(\d+(?:[.]\d+)?)[ ]*([kK]?)[ ]*(?:[+]|plus)[ ]*(\d+(?:[.]\d+)?)[ ]*([kK]?)[ ]*$', caseSensitive: false);
    final match = pattern.firstMatch(input.trim());
    if (match == null) return null;
    final first = double.tryParse(match.group(1)!);
    final second = double.tryParse(match.group(3)!);
    if (first == null || second == null) return null;
    final a = first * (match.group(2)!.isEmpty ? 1 : 1000);
    final b = second * (match.group(4)!.isEmpty ? 1 : 1000);
    final result = a + b;
    return result.isFinite ? result : null;
  }

  @override
  void dispose() {
    for (final c in [rent, rentIncome, quickEntry, deposit, arrears, expenses, loan, annualRate, loanMonths, materials, contributors, secondHouseRent, exchangeRate, note]) {
      c.dispose();
    }
    super.dispose();
  }
  Widget field(String label, TextEditingController controller, {String? suffix}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
      onChanged: (_) => setState(() {}),
    ),
  );

  String money(double amount) => showUsd
    ? 'USD ' + (amount / exchange).toStringAsFixed(2)
    : currency.format(amount);

  Future<void> saveCalculation() async {
    final numericValues = [rentValue, depositValue, arrearsValue, value(expenses), value(loan), value(annualRate), value(loanMonths), value(materials), value(contributors), value(secondHouseRent), exchange];
    if (numericValues.any((number) => !number.isFinite || number < 0)) {
      snack(context, 'Please enter valid non-negative amounts and rates.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { snack(context, 'Sign in to save this calculation.'); return; }
    try {
      await FirebaseFirestore.instance.collection('savedCalculations').add({
        'createdBy': uid,
        'title': note.text.trim().isEmpty ? 'Rent calculation' : note.text.trim(),
        'rent': rentValue, 'deposit': depositValue, 'arrears': arrearsValue,
        'lateFee': lateFee, 'amountDue': amountDue, 'monthlyProfitEstimate': profit,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) snack(context, 'Calculation saved to your notes.');
    } catch (e) {
      if (mounted) snack(context, 'Could not save calculation: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Property calculator'),
      actions: [
        IconButton(
          tooltip: showUsd ? 'Show Kenyan shillings' : 'Show US dollars',
          icon: const Icon(Icons.currency_exchange),
          onPressed: () => setState(() => showUsd = !showUsd),
        ),
      ],
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Rent, deposit & arrears', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          Text(showUsd ? 'USD view' : 'KES view', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        field('Monthly rent', rent, suffix: 'KES'),
        field('Deposit', deposit, suffix: 'KES'),
        field('Outstanding arrears', arrears, suffix: 'KES'),
        Text('Late fee (5% of arrears): \${currency.format(lateFee)}'),
        const Divider(height: 24),
        const Text('Total payable', style: TextStyle(color: Colors.grey)),
        Text(money(amountDue), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profit estimate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 12),
        field('Monthly rent income', rentIncome, suffix: 'KES'),
        field('Monthly expenses', expenses, suffix: 'KES'),
        Text('Estimated monthly profit: \${money(profit)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Building loan repayment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 12),
        field('Loan principal', loan, suffix: 'KES'),
        field('Annual interest rate', annualRate, suffix: '%'),
        field('Repayment period', loanMonths, suffix: 'months'),
        Text('Estimated monthly repayment: \${money(loanPayment)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Materials split & rent increase', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 12),
        field('Total materials cost', materials, suffix: 'KES'),
        field('Number of contributors', contributors),
        Text('Each contributor pays: \${currency.format(materialShare)}'),
        const SizedBox(height: 10),
        Text('Rent after 10% increase: \${currency.format(rentValue * 1.10)}'),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Compare two houses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 12),
        field('House A monthly rent', rent),
        field('House B monthly rent', secondHouseRent),
        Text('Difference: \${currency.format((rentValue - value(secondHouseRent)).abs())} • ' +
          (rentValue >= value(secondHouseRent) ? 'House A earns more' : 'House B earns more')),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Currency conversion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        const Text('Enter the current exchange rate manually; SkyNest does not fetch live FX rates in this version.'),
        field('KES per 1 USD', exchangeRate),
        Text('Current total in ' + (showUsd ? 'KES' : 'USD') + ': ' + (showUsd ? currency.format(amountDue * exchange) : 'USD ' + (amountDue / exchange).toStringAsFixed(2))),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick calculation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        TextField(controller: quickEntry,
          decoration: const InputDecoration(labelText: 'Example: 15k plus 2k', hintText: 'Enter two amounts to add', border: OutlineInputBorder()),
          onChanged: (text) => setState(() => quickResult = parseQuickExpression(text))),
        if (quickEntry.text.trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(
            quickResult == null ? 'Use a valid expression such as 15k + 2k.' : 'Result: ' + currency.format(quickResult!),
            style: TextStyle(fontWeight: FontWeight.w700, color: quickResult == null ? Colors.orange : Colors.green))),
      ]))),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Calculation note (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saveCalculation, icon: const Icon(Icons.save_outlined), label: const Text('SAVE CALCULATION AS NOTE'))),
      ]))),
      const Padding(padding: EdgeInsets.all(8), child: Text('Estimates are for planning only. Confirm actual fees, loan terms and exchange rates with the relevant provider.', style: TextStyle(color: Colors.grey))),
    ]),
  );
}

class _CalendarEntry {
  final String id;
  final String title;
  final String note;
  final String type;
  final DateTime date;
  final bool recurring;
  final bool custom;
  final String status;
  final double? amount;

  const _CalendarEntry({
    required this.id,
    required this.title,
    required this.note,
    required this.type,
    required this.date,
    this.recurring = false,
    this.custom = false,
    this.status = '',
    this.amount,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime focused = DateTime.now();
  DateTime? selected;

  DateTime _dayKey(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'rentDue': return Colors.red;
      case 'inspection': return Colors.blue;
      case 'meeting': return Colors.deepPurple;
      case 'loan': return Colors.teal;
      case 'blackout': return Colors.orange;
      default: return Colors.blueGrey;
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'rentDue': return 'Rent due';
      case 'inspection': return 'Inspection';
      case 'meeting': return 'Meeting';
      case 'loan': return 'Loan';
      case 'blackout': return 'Blackout';
      case 'payment': return 'Payment record';
      default: return 'Other';
    }
  }

  Future<void> _addEvent() async {
    final title = TextEditingController();
    final note = TextEditingController();
    DateTime eventDate = selected ?? DateTime.now();
    String eventType = 'rentDue';
    bool recurring = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: const Text('Add calendar event'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Event title')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: eventType,
                decoration: const InputDecoration(labelText: 'Event type'),
                items: const [
                  DropdownMenuItem(value: 'rentDue', child: Text('Rent due')),
                  DropdownMenuItem(value: 'inspection', child: Text('Inspection')),
                  DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                  DropdownMenuItem(value: 'loan', child: Text('Loan')),
                  DropdownMenuItem(value: 'blackout', child: Text('Blackout')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => refreshDialog(() => eventType = value ?? 'other'),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Event date'),
                subtitle: Text(dateFormat.format(eventDate)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: eventDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035, 12, 31),
                  );
                  if (picked != null) refreshDialog(() => eventDate = picked);
                },
              ),
              TextField(controller: note, maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes (optional)')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: recurring,
                title: const Text('Mark as recurring'),
                subtitle: const Text('A label only; this does not auto-create future events.'),
                onChanged: (value) => refreshDialog(() => recurring = value == true),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;
                if (title.text.trim().isEmpty) {
                  snack(dialogContext, 'Enter an event title.');
                  return;
                }
                try {
                  await FirebaseFirestore.instance.collection('calendarEvents').add({
                    'title': title.text.trim(),
                    'note': note.text.trim(),
                    'type': eventType,
                    'eventDate': Timestamp.fromDate(DateTime(eventDate.year, eventDate.month, eventDate.day)),
                    'isRecurring': recurring,
                    'createdBy': user.uid,
                    'landlordId': user.uid,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) snack(context, 'Calendar event saved.');
                } catch (error) {
                  if (dialogContext.mounted) snack(dialogContext, 'Could not save event: ' + error.toString());
                }
              },
              child: const Text('Save event'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    note.dispose();
  }

  Future<void> _deleteEvent(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete calendar event?'),
        content: const Text('This removes the event from your calendar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection('calendarEvents').doc(id).delete();
      if (mounted) snack(context, 'Event deleted.');
    } catch (error) {
      if (mounted) snack(context, 'Could not delete event: ' + error.toString());
    }
  }

  Future<void> _shareMonth(List<_CalendarEntry> entries) async {
    final monthEntries = entries.where((entry) =>
      entry.date.year == focused.year && entry.date.month == focused.month).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final lines = <String>['SkyNest calendar • ' + DateFormat('MMMM yyyy').format(focused)];
    for (final entry in monthEntries) {
      lines.add(DateFormat('EEE, dd MMM').format(entry.date) + ' • ' + entry.title +
        (entry.note.isEmpty ? '' : ' — ' + entry.note));
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) snack(context, 'This month’s calendar copied. You can paste it into a message.');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: EmptyView('Please sign in to view your calendar.'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rent calendar'),
        actions: [
          IconButton(tooltip: 'Share this month', icon: const Icon(Icons.share_outlined),
            onPressed: () => _loadAndShare()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEvent,
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('payments')
          .where('createdBy', isEqualTo: user.uid).snapshots(),
        builder: (context, paymentsSnapshot) {
          if (paymentsSnapshot.hasError) return errorView('Payment records could not load: ' + paymentsSnapshot.error.toString());
          if (!paymentsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('calendarEvents')
              .where('landlordId', isEqualTo: user.uid).snapshots(),
            builder: (context, customSnapshot) {
              if (customSnapshot.hasError) return errorView('Calendar events could not load: ' + customSnapshot.error.toString());
              if (!customSnapshot.hasData) return const Center(child: CircularProgressIndicator());

              final allEntries = <_CalendarEntry>[];
              for (final doc in paymentsSnapshot.data!.docs) {
                final data = doc.data();
                // Due date is the meaningful calendar date; createdAt is only a fallback.
                final date = _readDate(data['dueDate']) ?? _readDate(data['createdAt']);
                if (date == null) continue;
                final amount = data['amount'];
                allEntries.add(_CalendarEntry(
                  id: doc.id,
                  title: 'Rent payment • ' + (data['tenantName']?.toString() ?? 'Tenant'),
                  note: 'House ' + (data['houseNo']?.toString() ?? '—'),
                  type: 'payment',
                  date: date,
                  status: data['status']?.toString() ?? 'Pending verification',
                  amount: amount is num ? amount.toDouble() : null,
                ));
              }
              for (final doc in customSnapshot.data!.docs) {
                final data = doc.data();
                final date = _readDate(data['eventDate']);
                if (date == null) continue;
                allEntries.add(_CalendarEntry(
                  id: doc.id,
                  title: data['title']?.toString() ?? 'Calendar event',
                  note: data['note']?.toString() ?? '',
                  type: data['type']?.toString() ?? 'other',
                  date: date,
                  recurring: data['isRecurring'] == true,
                  custom: true,
                ));
              }

              final eventsByDay = <DateTime, List<_CalendarEntry>>{};
              for (final entry in allEntries) {
                eventsByDay.putIfAbsent(_dayKey(entry.date), () => []).add(entry);
              }
              final chosen = _dayKey(selected ?? focused);
              final selectedEntries = eventsByDay[chosen] ?? <_CalendarEntry>[];
              final monthCount = allEntries.where((entry) =>
                entry.date.year == focused.year && entry.date.month == focused.month).length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 92),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.calendar_month, color: brand),
                          const SizedBox(width: 8),
                          Expanded(child: Text(DateFormat('MMMM yyyy').format(focused),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
                          Chip(label: Text(monthCount.toString() + ' events')),
                        ]),
                        TableCalendar<_CalendarEntry>(
                          firstDay: DateTime(2020, 1, 1),
                          lastDay: DateTime(2035, 12, 31),
                          focusedDay: focused,
                          selectedDayPredicate: (day) => isSameDay(selected, day),
                          eventLoader: (day) => eventsByDay[_dayKey(day)] ?? const <_CalendarEntry>[],
                          onDaySelected: (day, focus) => setState(() { selected = day; focused = focus; }),
                          onPageChanged: (day) => setState(() { focused = day; }),
                          calendarStyle: CalendarStyle(
                            markerDecoration: const BoxDecoration(color: brand, shape: BoxShape.circle),
                            todayDecoration: BoxDecoration(color: brand.withOpacity(0.35), shape: BoxShape.circle),
                            selectedDecoration: const BoxDecoration(color: brand, shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          _calendarLegend(Colors.red, 'Rent due'),
                          _calendarLegend(Colors.blue, 'Inspection'),
                          _calendarLegend(Colors.deepPurple, 'Meeting'),
                          _calendarLegend(Colors.orange, 'Blackout'),
                          _calendarLegend(Colors.blueGrey, 'Payments'),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Events • ' + dateFormat.format(chosen),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (selectedEntries.isEmpty)
                    const Padding(padding: EdgeInsets.all(18),
                      child: Center(child: Text('No events recorded for this date.')))
                  else
                    ...selectedEntries.map((entry) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _colorFor(entry.type).withOpacity(0.14),
                          child: Icon(entry.custom ? Icons.event_note : Icons.receipt_long,
                            color: _colorFor(entry.type)),
                        ),
                        title: Text(entry.title),
                        subtitle: Text([
                          _labelFor(entry.type),
                          if (entry.note.isNotEmpty) entry.note,
                          if (entry.status.isNotEmpty) entry.status,
                          if (entry.amount != null) currency.format(entry.amount),
                        ].join(' • ')),
                        trailing: entry.recurring
                          ? const Icon(Icons.repeat, size: 18)
                          : entry.custom
                            ? IconButton(tooltip: 'Delete event', icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteEvent(entry.id))
                            : null,
                      ),
                    )),
                  const SizedBox(height: 12),
                  const Text('Payment dates use the recorded due date where available; otherwise the record date is shown.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _calendarLegend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );

  Future<void> _loadAndShare() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final payments = await FirebaseFirestore.instance.collection('payments')
        .where('createdBy', isEqualTo: user.uid).get();
      final custom = await FirebaseFirestore.instance.collection('calendarEvents')
        .where('landlordId', isEqualTo: user.uid).get();
      final entries = <_CalendarEntry>[];
      for (final doc in payments.docs) {
        final data = doc.data();
        final date = _readDate(data['dueDate']) ?? _readDate(data['createdAt']);
        if (date == null) continue;
        entries.add(_CalendarEntry(id: doc.id,
          title: 'Rent payment • ' + (data['tenantName']?.toString() ?? 'Tenant'),
          note: 'House ' + (data['houseNo']?.toString() ?? '—'),
          type: 'payment', date: date));
      }
      for (final doc in custom.docs) {
        final data = doc.data();
        final date = _readDate(data['eventDate']);
        if (date == null) continue;
        entries.add(_CalendarEntry(id: doc.id,
          title: data['title']?.toString() ?? 'Calendar event',
          note: data['note']?.toString() ?? '',
          type: data['type']?.toString() ?? 'other',
          date: date));
      }
      await _shareMonth(entries);
    } catch (error) {
      if (mounted) snack(context, 'Could not prepare calendar: ' + error.toString());
    }
  }
}
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final Set<String> _selectedPlanIds = <String>{};
  bool _selectionEnabled = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _currentPlanDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool get _selectionMode => _selectionEnabled || _selectedPlanIds.isNotEmpty;

  String _type(String value) => const {
    'build': 'New build', 'renovate': 'Renovation',
    'expand': 'Expansion', 'loanClear': 'Loan clearance',
  }[value] ?? 'Property project';

  Future<void> _editEntry(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final note = TextEditingController(text: data['note']?.toString() ?? '');
    final budget = TextEditingController(text: data['budget']?.toString() ?? '');
    final spent = TextEditingController(text: data['spent']?.toString() ?? '0');
    final progress = TextEditingController(text: data['progress']?.toString() ?? '0');
    final isProject = data['planType'] != null;
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Edit plan or reminder'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
        if (isProject) ...[
          TextField(controller: budget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Budget (KES)')),
          TextField(controller: spent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Spent (KES)')),
          TextField(controller: progress, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Progress (0–100)')),
        ],
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final b = double.tryParse(budget.text.trim());
          final sp = double.tryParse(spent.text.trim());
          final pr = int.tryParse(progress.text.trim());
          if (title.text.trim().isEmpty ||
              (isProject && (b == null || b <= 0 || sp == null || sp < 0 || pr == null || pr < 0 || pr > 100))) {
            snack(d, 'Check the title, budget, spending and progress values.');
            return;
          }
          try {
            final changes = <String, dynamic>{
              'title': title.text.trim(), 'note': note.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            };
            if (isProject) {
              changes.addAll({'budget': b, 'spent': sp, 'progress': pr});
            }
            await doc.reference.update(changes);
            if (d.mounted) Navigator.pop(d);
            if (mounted) snack(context, 'Updated successfully.');
          } catch (error) {
            if (d.mounted) snack(d, 'Could not update: $error');
          }
        }, child: const Text('Save changes')),
      ],
    ));
    title.dispose(); note.dispose(); budget.dispose(); spent.dispose(); progress.dispose();
  }

  Future<void> _deleteEntry(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Delete this item?'),
      content: Text('“${doc.data()['title'] ?? 'Plan'}” will be permanently deleted.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true) return;
    try {
      await doc.reference.delete();
      if (mounted) snack(context, 'Item deleted.');
    } catch (error) {
      if (mounted) snack(context, 'Could not delete item: $error');
    }
  }

  Future<void> _deleteSelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final selected = docs.where((doc) => _selectedPlanIds.contains(doc.id)).toList();
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: Text('Delete ${selected.length} selected items?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete all')),
      ],
    ));
    if (confirmed != true) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in selected) { batch.delete(doc.reference); }
      await batch.commit();
      if (mounted) setState(() { _selectedPlanIds.clear(); _selectionEnabled = false; });
      if (mounted) snack(context, '${selected.length} items deleted.');
    } catch (error) {
      if (mounted) snack(context, 'Bulk delete failed: $error');
    }
  }

  Future<void> _addReminder() async {
    final title = TextEditingController(), note = TextEditingController();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Add reminder'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Notes')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (title.text.trim().isEmpty) { snack(d, 'Enter a reminder title.'); return; }
          try {
            await FirebaseFirestore.instance.collection('plans').add({
              'title': title.text.trim(), 'note': note.text.trim(), 'done': false,
              'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(), 'createdBy': uid,
            });
            if (d.mounted) Navigator.pop(d);
          } catch (e) { if (d.mounted) snack(d, 'Could not save reminder: $e'); }
        }, child: const Text('Save')),
      ],
    ));
    title.dispose(); note.dispose();
  }

  Future<void> _addProject() async {
    final name = TextEditingController(), budget = TextEditingController();
    final spent = TextEditingController(text: '0'), progress = TextEditingController(text: '0');
    final materials = TextEditingController(), costs = TextEditingController(), note = TextEditingController();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    DateTime deadline = DateTime.now().add(const Duration(days: 30));
    String type = 'build';
    await showDialog<void>(context: context, builder: (d) => StatefulBuilder(
      builder: (d, refresh) => AlertDialog(
        title: const Text('New property plan'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Plan name')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: type, decoration: const InputDecoration(labelText: 'Plan type'),
            items: const [
              DropdownMenuItem(value: 'build', child: Text('Build')),
              DropdownMenuItem(value: 'renovate', child: Text('Renovate')),
              DropdownMenuItem(value: 'expand', child: Text('Expand')),
              DropdownMenuItem(value: 'loanClear', child: Text('Clear loan')),
            ],
            onChanged: (v) => refresh(() => type = v ?? 'build'),
          ),
          const SizedBox(height: 8),
          TextField(controller: budget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Budget (KES)')),
          const SizedBox(height: 8),
          TextField(controller: spent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Already spent (KES)')),
          const SizedBox(height: 8),
          TextField(controller: progress, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Progress (0–100%)')),
          const SizedBox(height: 8),
          TextField(controller: materials, maxLines: 2, decoration: const InputDecoration(labelText: 'Materials (comma separated)')),
          const SizedBox(height: 8),
          TextField(controller: costs, maxLines: 3, decoration: const InputDecoration(labelText: 'Cost split, one per line: Cement=50000')),
          const SizedBox(height: 8),
          TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          ListTile(
            contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event),
            title: const Text('Deadline'), subtitle: Text(dateFormat.format(deadline)),
            onTap: () async {
              final picked = await showDatePicker(context: d, initialDate: deadline,
                firstDate: DateTime.now(), lastDate: DateTime(2035, 12, 31));
              if (picked != null) refresh(() => deadline = picked);
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            final b = double.tryParse(budget.text.trim()), s = double.tryParse(spent.text.trim());
            final p = int.tryParse(progress.text.trim());
            if (name.text.trim().isEmpty || b == null || b <= 0 || s == null || s < 0 || p == null || p < 0 || p > 100) {
              snack(d, 'Enter a name, positive budget, non-negative spending and progress from 0 to 100.');
              return;
            }
            final split = <String, double>{};
            for (final line in costs.text.split('\n')) {
              if (line.trim().isEmpty) continue;
              final pair = line.split('=');
              final amount = pair.length == 2 ? double.tryParse(pair[1].trim()) : null;
              if (pair.length != 2 || pair[0].trim().isEmpty || amount == null || amount < 0) {
                snack(d, 'Cost split format must be Category=Amount, with non-negative amounts.');
                return;
              }
              split[pair[0].trim()] = amount;
            }
            try {
              await FirebaseFirestore.instance.collection('plans').add({
                'title': name.text.trim(), 'note': note.text.trim(), 'done': false,
                'planType': type, 'budget': b, 'spent': s, 'progress': p,
                'deadline': Timestamp.fromDate(DateTime(deadline.year, deadline.month, deadline.day)),
                'materials': materials.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList(),
                'costBreakdown': split, 'isCompleted': false,
                'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(), 'createdBy': uid,
              });
              if (d.mounted) Navigator.pop(d);
              if (mounted) snack(context, 'Property plan saved.');
            } catch (e) { if (d.mounted) snack(d, 'Could not save plan: $e'); }
          }, child: const Text('Save plan')),
        ],
      ),
    ));
    name.dispose(); budget.dispose(); spent.dispose(); progress.dispose();
    materials.dispose(); costs.dispose(); note.dispose();
  }

  Future<void> _share(Map<String, dynamic> data) async {
    final deadline = data['deadline'];
    final date = deadline is Timestamp ? deadline.toDate() : null;
    final b = data['budget'], s = data['spent'];
    final lines = <String>[
      'SkyNest plan: ${data['title'] ?? 'Property project'}',
      'Type: ${_type(data['planType']?.toString() ?? '')}',
      if (b is num) 'Budget: ${currency.format(b)}',
      if (s is num) 'Spent: ${currency.format(s)}',
      if (b is num && s is num) 'Remaining: ${currency.format(b - s)}',
      if (date != null) 'Deadline: ${dateFormat.format(date)}',
      if ((data['note']?.toString() ?? '').isNotEmpty) 'Notes: ${data['note']}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) snack(context, 'Plan details copied. Paste them into a message to share.');
  }

  Future<void> _loanEstimate(double remaining) async {
    final rate = TextEditingController(text: '12');
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Simple loan estimate'),
      content: TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Interest rate (%)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final r = double.tryParse(rate.text.trim());
          if (r == null || r < 0) { snack(d, 'Enter a non-negative interest rate.'); return; }
          Navigator.pop(d);
          snack(context, 'Simple one-year estimate: ${currency.format(remaining * (1 + r / 100))}. Not a lender quote or monthly repayment schedule.');
        }, child: const Text('Calculate')),
      ],
    ));
    rate.dispose();
  }

  Future<void> _complete(DocumentReference<Map<String, dynamic>> ref, bool value) async {
    try { await ref.update({'isCompleted': value, 'done': value, 'updatedAt': FieldValue.serverTimestamp()}); }
    catch (e) { if (mounted) snack(context, 'Could not update plan: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: EmptyView('Please sign in to view your plans.'));
    return Scaffold(
      appBar: AppBar(title: Text(_selectionMode ? '${_selectedPlanIds.length} selected' : 'Plans and reminders'), actions: [
        if (_selectionMode) IconButton(tooltip: 'Delete selected', onPressed: () => _deleteSelected(_currentPlanDocs),
          icon: const Icon(Icons.delete_outline)),
        if (_selectionMode) IconButton(tooltip: 'Clear selection', onPressed: () => setState(() {
          _selectedPlanIds.clear(); _selectionEnabled = false;
        }), icon: const Icon(Icons.close)),
        if (!_selectionMode) IconButton(tooltip: 'Select plans', onPressed: () => setState(() => _selectionEnabled = true),
          icon: const Icon(Icons.checklist_rounded)),
        if (!_selectionMode) IconButton(tooltip: 'Add reminder', onPressed: _addReminder, icon: const Icon(Icons.notifications_active_outlined)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addProject,
        icon: const Icon(Icons.add), label: const Text('New plan')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('plans').where('createdBy', isEqualTo: user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return errorView('Plans could not load: ${snapshot.error}');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.toList()..sort((a, b) {
            final ad = a.data()['deadline'], bd = b.data()['deadline'];
            return (ad is Timestamp ? ad.toDate() : DateTime(9999))
              .compareTo(bd is Timestamp ? bd.toDate() : DateTime(9999));
          });
          _currentPlanDocs = docs;
          if (docs.isEmpty) return const EmptyView('No plans or reminders yet. Tap New plan to begin.');
          final projects = docs.where((d) => d.data()['planType'] != null).toList();
          final totalBudget = projects.fold<double>(0, (v, d) => v + (d.data()['budget'] is num ? (d.data()['budget'] as num).toDouble() : 0));
          final totalSpent = projects.fold<double>(0, (v, d) => v + (d.data()['spent'] is num ? (d.data()['spent'] as num).toDouble() : 0));
          final active = projects.where((d) => d.data()['isCompleted'] != true).length;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            if (projects.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Project overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _metric('Active plans', '$active')),
                  Expanded(child: _metric('Total budget', currency.format(totalBudget))),
                  Expanded(child: _metric('Spent', currency.format(totalSpent))),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: totalBudget <= 0 ? 0 : (totalSpent / totalBudget).clamp(0.0, 1.0)),
                Align(alignment: Alignment.centerRight, child: Text('Remaining: ${currency.format(totalBudget - totalSpent)}')),
              ],
            ))),
            if (projects.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text('Property projects', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ...docs.map((doc) {
              final d = doc.data();
              if (d['planType'] == null) return Card(
                child: GestureDetector(
                  onLongPress: () => setState(() { _selectionEnabled = true; _selectedPlanIds.add(doc.id); }),
                  child: CheckboxListTile(
                    selected: _selectedPlanIds.contains(doc.id),
                    secondary: _selectionMode ? Checkbox(
                      value: _selectedPlanIds.contains(doc.id),
                      onChanged: (_) => setState(() {
                        if (_selectedPlanIds.contains(doc.id)) { _selectedPlanIds.remove(doc.id); }
                        else { _selectedPlanIds.add(doc.id); }
                      }),
                    ) : PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editEntry(doc);
                        if (value == 'delete') _deleteEntry(doc);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                value: d['done'] == true, title: Text(d['title']?.toString() ?? 'Reminder'),
                subtitle: Text([
                  if ((d['note']?.toString() ?? '').isNotEmpty) d['note'].toString(),
                  if (d['createdAt'] is Timestamp) 'Added ${dateFormat.format((d['createdAt'] as Timestamp).toDate())}',
                  if (d['updatedAt'] is Timestamp) 'Updated ${dateFormat.format((d['updatedAt'] as Timestamp).toDate())}',
                ].join(' • ')),
                onChanged: (v) async {
                  try { await doc.reference.update({'done': v == true, 'updatedAt': FieldValue.serverTimestamp()}); }
                  catch (e) { if (mounted) snack(context, 'Could not update reminder: $e'); }
                },
                  ),
                ),
              );
              final type = d['planType']?.toString() ?? 'build';
              final budget = d['budget'] is num ? (d['budget'] as num).toDouble() : 0.0;
              final spent = d['spent'] is num ? (d['spent'] as num).toDouble() : 0.0;
              final remaining = budget - spent;
              final progress = d['progress'] is num ? (d['progress'] as num).toInt().clamp(0, 100) : 0;
              final deadlineValue = d['deadline'];
              final deadline = deadlineValue is Timestamp ? deadlineValue.toDate() : null;
              final days = deadline?.difference(DateTime.now()).inDays;
              final complete = d['isCompleted'] == true;
              final rawMaterials = d['materials'];
              final materials = rawMaterials is List ? rawMaterials.map((v) => v.toString()).toList() : <String>[];
              final rawSplit = d['costBreakdown'];
              final split = rawSplit is Map ? rawSplit : <String, dynamic>{};
              final color = type == 'renovate' ? Colors.teal : type == 'expand' ? Colors.indigo : type == 'loanClear' ? Colors.deepPurple : Colors.orange;
              return Card(margin: const EdgeInsets.only(bottom: 12), clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onLongPress: () => setState(() { _selectionEnabled = true; _selectedPlanIds.add(doc.id); }),
                  child: ExpansionTile(
                  leading: _selectionMode ? Checkbox(
                    value: _selectedPlanIds.contains(doc.id),
                    onChanged: (_) => setState(() {
                      if (_selectedPlanIds.contains(doc.id)) { _selectedPlanIds.remove(doc.id); }
                      else { _selectedPlanIds.add(doc.id); }
                    }),
                  ) : CircleAvatar(backgroundColor: color.withOpacity(0.14),
                    child: Icon(Icons.home_work_outlined, color: color)),

                  title: Text(d['title']?.toString() ?? 'Property plan', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_type(type) + (deadline == null ? '' : ' • ' + dateFormat.format(deadline)) +
                    (d['createdAt'] is Timestamp ? ' • Added ' + dateFormat.format((d['createdAt'] as Timestamp).toDate()) : '') +
                    (d['updatedAt'] is Timestamp ? ' • Updated ' + dateFormat.format((d['updatedAt'] as Timestamp).toDate()) : '')),
                  trailing: Icon(complete ? Icons.check_circle : Icons.expand_more, color: complete ? Colors.green : color),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Progress'), Text('$progress%')]),
                    LinearProgressIndicator(value: progress / 100, color: color),
                    const SizedBox(height: 10),
                    _moneyRow('Budget', budget),
                    _moneyRow('Spent', spent),
                    _moneyRow('Remaining', remaining, color: remaining < 0 ? Colors.red : Colors.green),
                    if (days != null) Padding(padding: const EdgeInsets.only(top: 8),
                      child: Text(days < 0 ? '${-days} days overdue' : '$days days left',
                        style: TextStyle(color: days < 0 ? Colors.red : null))),
                    if (materials.isNotEmpty) ...[
                      const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 10),
                        child: Text('Materials', style: TextStyle(fontWeight: FontWeight.w600)))),
                      Wrap(spacing: 4, children: materials.map((v) => Chip(label: Text(v))).toList()),
                    ],
                    if (split.isNotEmpty) ...[
                      const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 8),
                        child: Text('Cost breakdown', style: TextStyle(fontWeight: FontWeight.w600)))),
                      ...split.entries.map((entry) => _moneyRow(entry.key.toString(), entry.value is num ? (entry.value as num).toDouble() : 0)),
                    ],
                    if ((d['note']?.toString() ?? '').isNotEmpty) Align(alignment: Alignment.centerLeft,
                      child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(d['note'].toString()))),
                    const Divider(height: 22),
                    Wrap(spacing: 6, children: [
                      TextButton.icon(onPressed: () => _editEntry(doc),
                        icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
                      TextButton.icon(onPressed: () => _deleteEntry(doc),
                        icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
                      TextButton.icon(onPressed: remaining > 0 ? () => _loanEstimate(remaining) : null,
                        icon: const Icon(Icons.calculate_outlined), label: const Text('Loan estimate')),
                      TextButton.icon(onPressed: () => _share(d),
                        icon: const Icon(Icons.share_outlined), label: const Text('Copy / share')),
                      TextButton.icon(onPressed: () => _complete(doc.reference, !complete),
                        icon: Icon(complete ? Icons.undo : Icons.check_circle_outline),
                        label: Text(complete ? 'Reopen' : 'Complete')),
                    ]),
                  ],
                  ),
                ),
              );
            }),
          ]);
        },
      ),
    );
  }

  Widget _metric(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);

  Widget _moneyRow(String label, double value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label), Text(currency.format(value), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]),
  );
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  DateTime? _dateOf(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Scaffold(appBar: AppBar(title: const Text('Achievements')),
      body: const EmptyView('Sign in to view achievements.'));
    final uid = user.uid;
    return Scaffold(appBar: AppBar(title: const Text('Achievements')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: uid).snapshots(),
        builder: (context, houses) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('tenants').where('landlordId', isEqualTo: uid).snapshots(),
          builder: (context, tenants) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: uid).snapshots(),
            builder: (context, payments) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('plans').where('createdBy', isEqualTo: uid).snapshots(),
              builder: (context, plans) {
                if (houses.hasError || tenants.hasError || payments.hasError || plans.hasError) {
                  return errorView('Achievement data could not load. Check your connection and try again.');
                }
                if (!houses.hasData || !tenants.hasData || !payments.hasData || !plans.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final houseDocs = houses.data!.docs;
                final tenantDocs = tenants.data!.docs;
                final paymentDocs = payments.data!.docs;
                final planDocs = plans.data!.docs;
                final occupiedDocs = houseDocs.where((d) => d.data()['isOccupied'] == true ||
                  d.data()['status']?.toString().toLowerCase() == 'occupied').toList();
                final receivedPayments = paymentDocs.where((d) {
                  final status = (d.data()['status']?.toString() ?? '').toLowerCase();
                  return status.contains('paid') || status.contains('received');
                }).toList();
                final now = DateTime.now();
                final monthPayments = receivedPayments.where((d) {
                  final date = _dateOf(d.data()['createdAt']);
                  return date != null && date.year == now.year && date.month == now.month;
                }).toList();
                final expectedRent = occupiedDocs.fold<double>(0,
                  (sum, d) => sum + ((d.data()['rent'] as num?)?.toDouble() ?? 0));
                final collected = monthPayments.fold<double>(0,
                  (sum, d) => sum + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
                final balances = tenantDocs.map((d) {
                  final data = d.data();
                  final value = data['balance'] ?? data['outstandingBalance'];
                  return value is num ? value.toDouble() : null;
                }).whereType<double>().toList();
                final completedPlans = planDocs.where((d) =>
                  d.data()['isCompleted'] == true || d.data()['done'] == true).length;
                final achievements = <Map<String, dynamic>>[
                  {'title': 'First Rent', 'description': 'Record your first confirmed rent payment.',
                    'points': 10, 'icon': Icons.payments_outlined, 'color': Colors.green,
                    'unlocked': receivedPayments.isNotEmpty,
                    'detail': receivedPayments.isNotEmpty ? 'Unlocked' : 'Waiting for a confirmed payment'},
                  {'title': 'Super Landlord', 'description': 'Have five occupied houses.',
                    'points': 50, 'icon': Icons.star_rounded, 'color': Colors.amber,
                    'unlocked': occupiedDocs.length >= 5,
                    'detail': occupiedDocs.length.toString() + ' of 5 occupied houses'},
                  {'title': 'No Arrears', 'description': 'All tenants with recorded balances have no outstanding arrears.',
                    'points': 30, 'icon': Icons.check_circle_outline, 'color': Colors.blue,
                    'unlocked': balances.isNotEmpty && balances.every((v) => v <= 0),
                    'detail': balances.isEmpty ? 'Add tenant balance information to qualify' :
                      balances.where((v) => v > 0).length.toString() + ' tenant balance(s) above zero'},
                  {'title': 'Builder', 'description': 'Complete a property plan.',
                    'points': 100, 'icon': Icons.construction, 'color': Colors.orange,
                    'unlocked': completedPlans > 0,
                    'detail': completedPlans.toString() + ' completed plan(s)'},
                  {'title': '100% Collection', 'description': 'Collect at least the recorded rent total for occupied houses this month.',
                    'points': 40, 'icon': Icons.emoji_events_outlined, 'color': Colors.purple,
                    'unlocked': expectedRent > 0 && collected >= expectedRent,
                    'detail': expectedRent <= 0 ? 'Add rent amounts to occupied houses' :
                      currency.format(collected) + ' of ' + currency.format(expectedRent) + ' recorded'},
                ];
                final unlocked = achievements.where((a) => a['unlocked'] == true).toList();
                final points = unlocked.fold<int>(0, (sum, a) => sum + (a['points'] as int));
                final level = points < 20 ? 'Beginner' : points < 100 ? 'Pro' : 'Tycoon';
                return ListView(padding: const EdgeInsets.all(16), children: [
                  Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
                    const CircleAvatar(radius: 27, child: Icon(Icons.emoji_events, size: 30)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 4),
                      Text(points.toString() + ' points • ' + level,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                      Text(unlocked.length.toString() + ' of ' + achievements.length.toString() + ' badges unlocked',
                        style: Theme.of(context).textTheme.bodySmall),
                    ])),
                  ]))),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Your badges', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text(unlocked.length.toString() + '/' + achievements.length.toString()),
                  ]),
                  const SizedBox(height: 8),
                  ...achievements.map((a) {
                    final isUnlocked = a['unlocked'] == true;
                    final color = a['color'] as Color;
                    return Card(margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        leading: CircleAvatar(backgroundColor: isUnlocked ? color.withOpacity(0.16) : Colors.grey.withOpacity(0.12),
                          child: Icon(a['icon'] as IconData, color: isUnlocked ? color : Colors.grey)),
                        title: Text(a['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['description'] as String),
                          const SizedBox(height: 3),
                          Text(a['detail'] as String, style: TextStyle(fontSize: 11,
                            color: isUnlocked ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurfaceVariant)),
                        ]),
                        isThreeLine: true,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline,
                            color: isUnlocked ? color : Colors.grey, size: 19),
                          const SizedBox(height: 3),
                          Text(a['points'].toString() + ' pts',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      ));
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: unlocked.isEmpty ? null : () async {
                      final summary = 'My SkyNest achievements: ' + points.toString() + ' points • ' + level + '\n' +
                        unlocked.map((a) => '• ' + a['title'].toString() + ' (+' + a['points'].toString() + ' pts)').join('\n');
                      await Clipboard.setData(ClipboardData(text: summary));
                      if (context.mounted) snack(context, 'Achievement summary copied. You can paste and share it.');
                    },
                    icon: const Icon(Icons.share_outlined), label: const Text('Copy achievement summary')),
                  const SizedBox(height: 8),
                  Text('Badges update from saved houses, tenant balances, payment records and completed plans. Monthly collection compares confirmed payments recorded this month with the current rent total of occupied houses.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});
  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  static const List<Color> customColors = [
    Color(0xFF673AB7), Color(0xFF00897B), Color(0xFFEF6C00),
    Color(0xFFAD1457), Color(0xFF3949AB), Color(0xFF558B2F),
    Color(0xFF6D4C41), Color(0xFF546E7A),
  ];

  Future<void> _apply(ThemeOption option) async {
    await themeManager.set(option.theme, option.name);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(option.name + ' applied and saved.')));
  }

  Future<void> _applyCustom(Color color) async {
    await themeManager.set(Themes.custom(color), 'Custom', customColor: color);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom colour applied and saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final options = Themes.options;
    final selectedColor = themeManager.customColorValue == null ? null : Color(themeManager.customColorValue!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your style'),
        actions: [
          IconButton(
            tooltip: 'Share SkyNest themes',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Clipboard.setData(const ClipboardData(text: 'Explore the beautiful themes in SkyNest Rental Management.')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
            ),
            child: Text('Make SkyNest feel like your space.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 5),
          Text('Choose a complete colour palette. Your selection is saved on this device and restored next time you open the app.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.dark_mode_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dark appearance', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Switch to the Midnight Luxury palette', style: TextStyle(fontSize: 12)),
                ])),
                Switch(
                  value: themeManager.value.brightness == Brightness.dark,
                  onChanged: (enabled) {
                    final option = Themes.options.firstWhere((item) => item.name == (enabled ? 'Midnight Luxury' : 'Classic Blue'));
                    _apply(option);
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile.adaptive(
              secondary: const Icon(Icons.photo_library_outlined),
              title: const Text('Live photo slideshow', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Rotate real property and lifestyle photos behind app screens'),
              value: themeManager.slideshowEnabled,
              onChanged: themeManager.setSlideshowEnabled,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 11, mainAxisSpacing: 11, childAspectRatio: 1.12),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = themeManager.selectedName == option.name;
              var hovered = false;
              return StatefulBuilder(
                builder: (context, setTileState) => MouseRegion(
                  onEnter: (_) => setTileState(() => hovered = true),
                  onExit: (_) => setTileState(() => hovered = false),
                  child: AnimatedScale(
                    scale: hovered ? 1.035 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: selected || hovered ? 5 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                  side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant, width: selected ? 2.3 : 1),
                ),
                child: InkWell(
                  onTap: () => _apply(option),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [option.primary, option.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                        child: Stack(fit: StackFit.expand, children: [
                          Image.network(_menuImageFor(option.name), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => DecoratedBox(decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [option.primary, option.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            )),
                          ),
                          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Color(0x22000000), Color(0x99000000)],
                          ))),
                          Positioned(right: 12, top: 10, child: Icon(option.icon, size: 40, color: Colors.white.withOpacity(0.28))),
                          Positioned(left: 12, bottom: 8, child: Icon(Icons.apartment_rounded, size: 56, color: Colors.white.withOpacity(0.88))),
                          if (selected) const Positioned(right: 9, bottom: 9, child: Icon(Icons.check_circle, color: Colors.white, size: 23)),
                          if (option.isPremium) const Positioned(left: 9, top: 9, child: Icon(Icons.workspace_premium, color: Colors.white, size: 19)),
                        ]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(option.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text(option.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                        if (option.isPremium) const Padding(padding: EdgeInsets.only(top: 4), child: Text('PREMIUM STYLE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFB8860B)))),
                      ]),
                    ),
                  ]),
                ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text('Custom colour', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Pick a colour to build a matching SkyNest palette.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: customColors.map((color) {
            final selected = selectedColor?.value == color.value;
            return InkWell(
              onTap: () => _applyCustom(color),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 43, height: 43,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3)),
                child: selected ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            );
          }).toList()),
          if (selectedColor != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Current custom colour: #' + selectedColor.value.toRadixString(16).padLeft(8, '0').toUpperCase(), style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class PamphletsScreen extends StatefulWidget {
  const PamphletsScreen({super.key});
  @override
  State<PamphletsScreen> createState() => _PamphletsScreenState();
}

class _PamphletsScreenState extends State<PamphletsScreen> {
  final Set<String> selectedIds = <String>{};
  String typeFilter = 'all';

  String _typeLabel(String value) {
    switch (value) {
      case 'rentNotice': return 'Rent notice';
      case 'eviction': return 'Tenancy notice';
      case 'appreciation': return 'Appreciation';
      case 'rules': return 'House rules';
      default: return 'Other';
    }
  }

  Color _typeColor(String value) {
    switch (value) {
      case 'rentNotice': return Colors.red;
      case 'eviction': return Colors.deepOrange;
      case 'appreciation': return Colors.green;
      case 'rules': return Colors.blue;
      default: return Colors.blueGrey;
    }
  }

  Future<void> _createPamphlet() async {
    final title = TextEditingController();
    final message = TextEditingController();
    final swahili = TextEditingController();
    final copies = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    String type = 'rentNotice';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Create pamphlet'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Pamphlet type'),
                items: const [
                  DropdownMenuItem(value: 'rentNotice', child: Text('Rent notice')),
                  DropdownMenuItem(value: 'eviction', child: Text('Tenancy notice')),
                  DropdownMenuItem(value: 'appreciation', child: Text('Appreciation')),
                  DropdownMenuItem(value: 'rules', child: Text('House rules')),
                ],
                onChanged: (v) => refresh(() => type = v ?? 'rentNotice'),
              ),
              const SizedBox(height: 10),
              TextFormField(controller: message, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Message (English)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the message' : null),
              const SizedBox(height: 10),
              TextFormField(controller: swahili, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Swahili version (optional)')),
              const SizedBox(height: 10),
              TextFormField(controller: copies, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of copies'), validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 1 || n > 500 ? 'Enter 1–500 copies' : null;
              }),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, {
                'title': title.text.trim(), 'type': type, 'message': message.text.trim(),
                'swahiliMessage': swahili.text.trim(), 'copies': int.parse(copies.text.trim()),
              });
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    title.dispose(); message.dispose(); swahili.dispose(); copies.dispose();
    if (result == null || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { snack(context, 'Sign in to save pamphlets.'); return; }
    try {
      await FirebaseFirestore.instance.collection('pamphlets').add({
        ...result, 'landlordId': user.uid, 'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(), 'isPrinted': false,
      });
      await recordActivity(user.uid, 'Created pamphlet: ' + result['title'].toString());
      if (mounted) snack(context, 'Pamphlet saved.');
    } catch (e) {
      if (mounted) snack(context, 'Could not save pamphlet: ' + e.toString());
    }
  }

  pw.Document _buildPdf(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final pdf = pw.Document();
    for (final doc in docs) {
      final data = doc.data();
      final copies = ((data['copies'] is num ? (data['copies'] as num).toInt() : 1)).clamp(1, 500);
      for (var copy = 0; copy < copies; copy++) {
        pdf.addPage(pw.Page(
          margin: const pw.EdgeInsets.all(42),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('SKYNEST', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
              pw.SizedBox(height: 24),
              pw.Text(data['title']?.toString() ?? 'Property notice', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(_typeLabel(data['type']?.toString() ?? ''), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(),
              pw.SizedBox(height: 18),
              pw.Text(data['message']?.toString() ?? '', style: const pw.TextStyle(fontSize: 13, lineSpacing: 5)),
              if ((data['swahiliMessage']?.toString() ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Text('Kiswahili', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text(data['swahiliMessage'].toString(), style: const pw.TextStyle(fontSize: 12, lineSpacing: 4)),
              ],
              pw.Spacer(),
              pw.Divider(),
              pw.Text('Issued ' + DateFormat('dd MMM yyyy').format(DateTime.now()), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ));
      }
    }
    return pdf;
  }

  Future<void> _printDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) return;
    try {
      final pdf = _buildPdf(docs);
      final printed = await Printing.layoutPdf(onLayout: (_) => pdf.save(), name: 'SkyNest_Pamphlets.pdf');
      if (printed) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in docs) {
          batch.update(doc.reference, {'isPrinted': true, 'printedAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
        if (mounted) snack(context, 'Print job sent for ' + docs.length.toString() + ' pamphlet(s).');
      }
    } catch (e) {
      if (mounted) snack(context, 'Printing failed: ' + e.toString());
    }
  }

  Future<void> _shareDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      final pdf = _buildPdf([doc]);
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'SkyNest_Pamphlet.pdf');
    } catch (e) {
      if (mounted) snack(context, 'Could not share pamphlet: ' + e.toString());
    }
  }

  Future<void> _deleteDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete pamphlet?'),
        content: Text('Delete "' + (doc.data()['title']?.toString() ?? 'this pamphlet') + '"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await doc.reference.delete();
      final landlordId = doc.data()['landlordId']?.toString();
      if (landlordId != null && landlordId.isNotEmpty) {
        await recordActivity(landlordId, 'Deleted pamphlet: ' + (doc.data()['title']?.toString() ?? 'Untitled'));
      }
      if (mounted) setState(() => selectedIds.remove(doc.id));
    } catch (e) {
      if (mounted) snack(context, 'Could not delete pamphlet: ' + e.toString());
    }
  }

  bool _addingStarterPamphlets = false;

  Future<void> _addStarterPamphlets() async {
    if (_addingStarterPamphlets) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _addingStarterPamphlets = true);
    const templates = <Map<String, dynamic>>[
      {
        'title': 'Monthly Rent Reminder',
        'type': 'rentNotice',
        'message': 'Dear Tenant, this is a friendly reminder that monthly rent is due. Kindly make payment using the agreed method and share your payment confirmation. If you have already paid, please disregard this notice. Thank you.',
        'swahiliMessage': 'Mpendwa Mpangaji, tunakukumbusha kwa upole kuwa kodi ya mwezi inapaswa kulipwa. Tafadhali lipa kwa njia tuliyokubaliana na utume uthibitisho wa malipo. Ikiwa tayari umelipa, puuza ujumbe huu. Asante.',
      },
      {
        'title': 'Property House Rules',
        'type': 'rules',
        'message': 'Welcome. Please keep shared areas clean, dispose of waste responsibly, avoid excessive noise, protect shared property and report maintenance or safety concerns promptly. Respect the privacy and comfort of neighbours.',
        'swahiliMessage': 'Karibu. Tafadhali weka maeneo ya pamoja katika hali ya usafi, tupa taka ipasavyo, epuka kelele nyingi, tunza mali ya pamoja na ripoti hitilafu au hatari mapema. Heshimu faragha na utulivu wa majirani.',
      },
      {
        'title': 'Maintenance Notice',
        'type': 'rentNotice',
        'message': 'Dear Residents, maintenance work is scheduled at the property. There may be temporary noise or limited access to the affected area. We apologise for any inconvenience and appreciate your cooperation.',
        'swahiliMessage': 'Wakazi wapendwa, kazi ya matengenezo imepangwa kufanyika katika nyumba. Kunaweza kuwa na kelele za muda au matumizi ya eneo husika yakapunguzwa. Tunaomba radhi kwa usumbufu na tunashukuru kwa ushirikiano wenu.',
      },
      {
        'title': 'Tenant Appreciation',
        'type': 'appreciation',
        'message': 'Thank you for being a valued member of our residential community. Your cooperation in keeping the property safe, clean and respectful makes a positive difference. We appreciate you.',
        'swahiliMessage': 'Asante kwa kuwa sehemu muhimu ya jumuiya yetu ya makazi. Ushirikiano wako katika kudumisha usalama, usafi na heshima unaleta tofauti nzuri. Tunakuthamini.',
      },
    ];
    try {
      final collection = FirebaseFirestore.instance.collection('pamphlets');
      final batch = FirebaseFirestore.instance.batch();
      for (final template in templates) {
        final ref = collection.doc();
        batch.set(ref, {
          ...template,
          'landlordId': user.uid,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'isPrinted': false,
          'copies': 1,
        });
      }
      await batch.commit();
      await recordActivity(user.uid, 'Added four SkyNest starter pamphlet templates');
      if (mounted) snack(context, 'Four starter pamphlets added. You can edit their wording before printing.');
    } catch (error) {
      if (mounted) snack(context, 'Starter pamphlets could not be added. Check your connection and permissions.');
    } finally {
      if (mounted) setState(() => _addingStarterPamphlets = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Scaffold(appBar: AppBar(title: const Text('Pamphlets')), body: const EmptyView('Sign in to manage pamphlets.'));
    final stream = FirebaseFirestore.instance.collection('pamphlets').where('landlordId', isEqualTo: user.uid).snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Pamphlets')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createPamphlet, icon: const Icon(Icons.add), label: const Text('New pamphlet')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return errorView('Pamphlets could not load: ' + snapshot.error.toString());
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.toList()..sort((a, b) {
            final ad = a.data()['createdAt']; final bd = b.data()['createdAt'];
            final at = ad is Timestamp ? ad.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final bt = bd is Timestamp ? bd.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return bt.compareTo(at);
          });
          final filtered = docs.where((doc) => typeFilter == 'all' || doc.data()['type'] == typeFilter).toList();
          final selectedDocs = filtered.where((doc) => selectedIds.contains(doc.id)).toList();
          return Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [
              Expanded(child: Text(docs.length.toString() + ' saved pamphlet(s)', style: const TextStyle(fontWeight: FontWeight.w700))),
              DropdownButton<String>(
                value: typeFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All types')),
                  DropdownMenuItem(value: 'rentNotice', child: Text('Rent notice')),
                  DropdownMenuItem(value: 'eviction', child: Text('Tenancy')),
                  DropdownMenuItem(value: 'appreciation', child: Text('Appreciation')),
                  DropdownMenuItem(value: 'rules', child: Text('House rules')),
                ],
                onChanged: (v) => setState(() { typeFilter = v ?? 'all'; selectedIds.clear(); }),
              ),
            ])),
            if (filtered.isNotEmpty) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    if (selectedIds.length == filtered.length) { selectedIds.clear(); }
                    else { selectedIds..clear()..addAll(filtered.map((d) => d.id)); }
                  }),
                  icon: const Icon(Icons.checklist),
                  label: Text(selectedIds.length == filtered.length ? 'Clear selection' : 'Select all'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(onPressed: selectedDocs.isEmpty ? null : () => _printDocs(selectedDocs), icon: const Icon(Icons.print), label: Text('Print (' + selectedDocs.length.toString() + ')')),
              ]),
            ),
            Expanded(child: filtered.isEmpty
              ? Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.menu_book_rounded, size: 38, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 16),
                    Text('Your pamphlet shelf is ready', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('Start with four editable templates: rent reminder, house rules, maintenance notice and tenant appreciation. You can also create your own from scratch.', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _addingStarterPamphlets ? null : _addStarterPamphlets,
                      icon: _addingStarterPamphlets
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded),
                      label: Text(_addingStarterPamphlets ? 'Adding templates…' : 'Add 4 starter pamphlets'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(onPressed: _createPamphlet, icon: const Icon(Icons.add), label: const Text('Create a custom pamphlet')),
                  ],
                )))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index]; final data = doc.data();
                    final type = data['type']?.toString() ?? '';
                    final printed = data['isPrinted'] == true;
                    final copies = data['copies'] is num ? (data['copies'] as num).toInt() : 1;
                    final date = data['createdAt'] is Timestamp ? dateFormat.format((data['createdAt'] as Timestamp).toDate()) : 'Just created';
                    return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Checkbox(value: selectedIds.contains(doc.id), onChanged: (v) => setState(() { if (v == true) selectedIds.add(doc.id); else selectedIds.remove(doc.id); })),
                        Container(width: 4, height: 112, decoration: BoxDecoration(color: _typeColor(type), borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(data['title']?.toString() ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Chip(visualDensity: VisualDensity.compact, label: Text(printed ? 'Printed' : 'Draft', style: const TextStyle(fontSize: 10)), backgroundColor: printed ? Colors.green.shade100 : Colors.orange.shade100),
                          ]),
                          Text(_typeLabel(type), style: TextStyle(color: _typeColor(type), fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(data['message']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                          if ((data['swahiliMessage']?.toString() ?? '').isNotEmpty)
                            Text(data['swahiliMessage'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(copies.toString() + ' copies • ' + date, style: Theme.of(context).textTheme.bodySmall),
                          Row(children: [
                            IconButton(tooltip: 'Print', onPressed: () => _printDocs([doc]), icon: const Icon(Icons.print, size: 19)),
                            IconButton(tooltip: 'Share PDF', onPressed: () => _shareDoc(doc), icon: const Icon(Icons.share, size: 19)),
                            IconButton(tooltip: 'Delete', onPressed: () => _deleteDoc(doc), icon: const Icon(Icons.delete_outline, size: 19)),
                          ]),
                        ])),
                      ]),
                    ));
                  },
                )),
          ]);
        },
      ),
    );
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
      final random = math.Random.secure();
      final code = List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
      final propertyIds = <String>[];
      if (role == 'caretaker') {
        final houses = await FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: uid).get();
        propertyIds.addAll(houses.docs.map((doc) => doc.id));
      }
      await FirebaseFirestore.instance.collection('invitations').doc(code).set({
        'role': role, 'landlordId': uid, 'createdBy': uid, 'propertyIds': propertyIds,
        'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });
      await recordActivity(uid, 'Created a ' + role + ' invitation');
      if (mounted) setState(() => latestCode = code);
      if (mounted) snack(context, 'Invitation created. It expires in 24 hours.');
    } catch (e) { if (mounted) snack(context, 'Could not create invitation: ' + e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Caretakers & invitations')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Invite a tenant or caretaker to join your property account. Codes are single-use and expire after 24 hours.'),
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
        const SizedBox(height: 5),
        const Text('This invitation expires after 24 hours.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700)),
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
  String priority = 'medium';
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
        'priority': priority, 'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
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
          DropdownButtonFormField<String>(
            value: priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium', child: Text('Normal')),
              DropdownMenuItem(value: 'high', child: Text('High')),
            ],
            onChanged: saving ? null : (value) => setState(() => priority = value ?? 'medium'),
          ),
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
                final priorityValue = (d['priority']?.toString() ?? 'medium').toLowerCase();
                final priorityColor = priorityValue == 'high' ? Colors.red : priorityValue == 'low' ? Colors.grey : Colors.orange;
                final subjectValue = (d['subject']?.toString() ?? '').toLowerCase();
                final issueIcon = subjectValue.contains('water') ? Icons.water_drop
                  : subjectValue.contains('electric') || subjectValue.contains('stima') ? Icons.bolt
                  : Icons.report_problem_outlined;
                final created = d['createdAt'];
                final openDays = created is Timestamp ? DateTime.now().difference(created.toDate()).inDays : null;
                return Dismissible(
                  key: ValueKey('complaint-' + doc.id),
                  direction: role == 'tenant' || d['status'] == 'resolved' ? DismissDirection.none : DismissDirection.startToEnd,
                  confirmDismiss: (_) async {
                    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
                      title: const Text('Resolve complaint?'),
                      content: const Text('Mark this complaint as resolved? The status change will be recorded.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
                        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('RESOLVE')),
                      ],
                    ));
                    if (confirmed == true) {
                      await updateStatus(doc.id, 'resolved');
                      HapticFeedback.mediumImpact();
                    }
                    return false;
                  },
                  background: Container(
                    alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(16)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 7),
                      Text('Resolve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  child: Card(
                    color: priorityColor.withOpacity(0.07),
                    child: ExpansionTile(
                      leading: Stack(clipBehavior: Clip.none, children: [
                        Icon(issueIcon, size: 30, color: priorityColor),
                        if (d['escalated'] == true) const Positioned(right: -8, top: -8,
                          child: Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 17)),
                      ]),
                      title: Text(d['subject']?.toString() ?? 'Complaint', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text((d['createdByName'] ?? 'User').toString() + ' • ' +
                        (d['status'] ?? 'open').toString() + ' • ' + priorityValue.toUpperCase() +
                        (openDays == null ? '' : ' • Open $openDays days')),
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
                      ]),
                  ),
                );
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
  final Set<String> selectedGroupIds = <String>{};
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
      await ref.collection('members').doc(uid).set({'joinedAt': FieldValue.serverTimestamp(), 'role': p['role'] ?? 'tenant', 'displayName': (p['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Member').toString()});
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
                return ListView(children: snap.data!.docs.map((doc) {
                  final data = doc.data();
                  final members = (data['memberIds'] as List?) ?? const [];
                  final isMember = members.contains(uid);
                  final selected = selectedGroupIds.contains(doc.id);
                  final due = data['totalDue'];
                  final hasUnread = (data['unreadCount'] as num?)?.toInt() ?? 0;
                  final groupColor = data['colorValue'] is int
                    ? Color(data['colorValue'] as int) : Theme.of(context).colorScheme.primary;
                  final paid = (data['paidAmount'] as num?)?.toDouble();
                  final expected = (data['expectedAmount'] as num?)?.toDouble();
                  final rawProgress = (data['collectionProgress'] as num?)?.toDouble();
                  final progress = (rawProgress ?? (paid != null && expected != null && expected > 0 ? paid / expected : 0.0)).clamp(0.0, 1.0).toDouble();
                  final seenBy = data['seenBy'] is List ? (data['seenBy'] as List).length : ((data['seenCount'] as num?)?.toInt() ?? 0);
                  final broadcastOnly = data['broadcastOnly'] == true;
                  final highDue = due is num && due > 0;
                  final tile = Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF1F1F1)),
                      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 20, offset: Offset(0, 4))]),
                    child: ClipRRect(borderRadius: BorderRadius.circular(20), child: IntrinsicHeight(child: Row(children: [
                      Container(width: 4, color: highDue ? const Color(0xFFEF4444) : groupColor),
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 11), child: Row(children: [
                        SizedBox(width: 72, child: Stack(clipBehavior: Clip.none, children: [
                          Row(children: [
                            _GroupAvatar(seed: members.isNotEmpty ? members[0].toString() : 'empty', color: groupColor),
                            Transform.translate(offset: const Offset(-11, 0), child: _GroupAvatar(seed: members.length > 1 ? members[1].toString() : 'member', color: groupColor.withOpacity(.82))),
                            Transform.translate(offset: const Offset(-22, 0), child: _GroupAvatar(seed: members.length > 2 ? members[2].toString() : 'group', color: groupColor.withOpacity(.64))),
                          ]),
                          if (members.isNotEmpty) const Positioned(left: 25, bottom: 0, child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Padding(padding: EdgeInsets.all(1), child: CircleAvatar(radius: 4, backgroundColor: Color(0xFF22C55E))))),
                          if (selected) const Positioned(left: 15, top: 7, child: CircleAvatar(radius: 13, backgroundColor: Colors.white,
                            child: Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 25))),
                        ])),
                        const SizedBox(width: 2),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(data['name']?.toString() ?? 'Group', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
                          const SizedBox(height: 7),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            _GroupInfoChip(icon: Icons.people_alt_outlined, label: members.length.toString() + ' members'),
                            if (due is num) _GroupInfoChip(icon: Icons.payments_outlined, label: 'Due ' + currency.format(due), danger: highDue),
                          ]),
                          const SizedBox(height: 9),
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, minHeight: 3,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: AlwaysStoppedAnimation<Color>(highDue ? const Color(0xFFEF4444) : const Color(0xFF3B82F6)))),
                        ])),
                        const SizedBox(width: 9),
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Stack(clipBehavior: Clip.none, children: [
                            Container(width: 38, height: 38, decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                              child: Icon(broadcastOnly ? Icons.lock_outline : Icons.campaign_rounded, color: const Color(0xFF2563EB), size: 20)),
                            if (hasUnread > 0) const Positioned(right: -1, top: -1, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFF2563EB))),
                          ]),
                          const SizedBox(height: 6),
                          if (!isMember)
                            TextButton(
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              onPressed: () async {
                                try {
                                  final groupRef = FirebaseFirestore.instance.collection('groups').doc(doc.id);
                                  await groupRef.update({'memberIds': FieldValue.arrayUnion([uid])});
                                  await groupRef.collection('members').doc(uid).set({'joinedAt': FieldValue.serverTimestamp(), 'role': p['role'] ?? 'tenant', 'displayName': (p['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Member').toString()});
                                  if (context.mounted) snack(context, 'Joined group.');
                                } catch (e) { if (context.mounted) snack(context, 'Could not join group: ' + e.toString()); }
                              },
                              child: const Text('JOIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                            )
                          else
                            Text(seenBy > 0 ? 'Seen ' + seenBy.toString() + '/' + members.length.toString() : members.length.toString() + ' members',
                              style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                        ]),
                      ]))),
                    ]))),
                  );
                  return Dismissible(
                    key: ValueKey('group-tile-' + doc.id),
                    direction: isMember ? DismissDirection.startToEnd : DismissDirection.none,
                    confirmDismiss: (_) async {
                      if (isMember) {
                        HapticFeedback.selectionClick();
                        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                          GroupChatScreen(groupId: doc.id, groupName: data['name']?.toString() ?? 'Group')));
                      }
                      return false;
                    },
                    background: Container(alignment: Alignment.centerLeft, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      padding: const EdgeInsets.only(left: 20),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.campaign_rounded, color: Colors.white), SizedBox(width: 8),
                        Text('Broadcast', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ])),
                    child: GestureDetector(
                      onLongPress: () {
                        HapticFeedback.selectionClick();
                        setState(() { if (selected) { selectedGroupIds.remove(doc.id); } else { selectedGroupIds.add(doc.id); } });
                      },
                      onTap: () {
                        if (selectedGroupIds.isNotEmpty) {
                          setState(() { if (selected) { selectedGroupIds.remove(doc.id); } else { selectedGroupIds.add(doc.id); } });
                          return;
                        }
                        if (!isMember) { snack(context, 'Join this group first.'); return; }
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                          GroupChatScreen(groupId: doc.id, groupName: data['name']?.toString() ?? 'Group')));
                      },
                      child: tile,
                    ),
                  );
                }).toList());
              },
            );
          },
        )),
      ]),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  final String seed;
  final Color color;
  const _GroupAvatar({required this.seed, required this.color});
  @override
  Widget build(BuildContext context) {
    final initials = seed == 'empty' ? '' : seed.trim().isEmpty ? '?' : seed.trim().substring(0, 1).toUpperCase();
    return Container(width: 36, height: 36,
      decoration: BoxDecoration(color: color.withOpacity(.14), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      alignment: Alignment.center,
      child: initials.isEmpty ? Icon(Icons.groups_outlined, size: 19, color: color)
        : Text(initials, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)));
  }
}

class _GroupInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _GroupInfoChip({required this.icon, required this.label, this.danger = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(color: danger ? const Color(0xFFFEF2F2) : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: danger ? const Color(0xFFDC2626) : const Color(0xFF6B7280)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: danger ? FontWeight.w800 : FontWeight.w600,
        color: danger ? const Color(0xFFDC2626) : const Color(0xFF4B5563))),
    ]),
  );
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
  bool _encryptionReady = false;
  String? _encryptionSetupError;

  @override
  void initState() {
    super.initState();
    _prepareEncryption();
  }

  Future<void> _prepareEncryption() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await SkyNestMessageEncryption.instance.prepareDevice(uid);
      if (mounted) setState(() => _encryptionReady = true);
    } catch (error) {
      if (mounted) setState(() => _encryptionSetupError = error.toString());
    }
  }

  @override
  void dispose() { message.dispose(); super.dispose(); }

  Future<void> send() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = message.text.trim();
    if (user == null || text.isEmpty || sending) return;
    setState(() => sending = true);
    message.clear();
    try {
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
      final groupSnapshot = await groupRef.get();
      final groupData = groupSnapshot.data();
      if (groupData == null) throw StateError('This group is no longer available.');
      final rawMemberIds = groupData['memberIds'];
      final memberIds = rawMemberIds is List
          ? rawMemberIds.map((value) => value.toString()).where((value) => value.isNotEmpty).toList()
          : <String>[user.uid];
      if (!memberIds.contains(user.uid)) {
        throw StateError('You are no longer a member of this group.');
      }
      final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final senderName = (profile.data()?['displayName'] ?? user.displayName ?? 'Member').toString();
      final encrypted = await SkyNestMessageEncryption.instance.encryptGroupMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        plaintext: text,
        memberIds: memberIds,
      );
      await groupRef.collection('messages').add({
        ...encrypted,
        'senderId': user.uid,
        'senderName': senderName,
        'senderPhotoUrl': profile.data()?['photoUrl'] ?? user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) snack(context, 'Message not sent: ' + e.toString());
      message.text = text;
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendGroupAttachment(File file, String fileName, String mimeType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || sending) return;
    setState(() => sending = true);
    Reference? uploadedRef;
    try {
      final size = await file.length();
      if (size <= 0 || size > 10 * 1024 * 1024) {
        throw StateError('Choose a file smaller than 10 MB.');
      }
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
      final groupSnapshot = await groupRef.get();
      final groupData = groupSnapshot.data();
      if (groupData == null) throw StateError('This group is no longer available.');
      final rawMemberIds = groupData['memberIds'];
      final memberIds = rawMemberIds is List
          ? rawMemberIds.map((value) => value.toString()).where((value) => value.isNotEmpty).toList()
          : <String>[];
      if (!memberIds.contains(user.uid)) throw StateError('You are no longer a member of this group.');

      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final uniqueName = DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName;
      final storagePath = 'group_attachments/' + widget.groupId + '/' + user.uid + '/' + uniqueName;
      uploadedRef = FirebaseStorage.instance.ref().child(storagePath);
      await uploadedRef!.putFile(file, SettableMetadata(
        contentType: mimeType,
        cacheControl: 'private,max-age=3600',
      ));
      final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final senderName = (profile.data()?['displayName'] ?? user.displayName ?? 'Member').toString();
      final encrypted = await SkyNestMessageEncryption.instance.encryptGroupMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        plaintext: 'Shared attachment: ' + fileName,
        memberIds: memberIds,
      );
      await groupRef.collection('messages').add({
        ...encrypted,
        'senderId': user.uid,
        'senderName': senderName,
        'senderPhotoUrl': profile.data()?['photoUrl'] ?? user.photoURL,
        'attachment': {
          'name': fileName,
          'mimeType': mimeType,
          'storagePath': storagePath,
          'size': size,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) snack(context, 'File shared with the group.');
    } catch (error) {
      if (uploadedRef != null) {
        try { await uploadedRef!.delete(); } catch (_) {}
      }
      if (mounted) snack(context, 'Attachment not sent: ' + error.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _pickGroupImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      await _sendGroupAttachment(File(picked.path), picked.name, picked.mimeType ?? 'image/jpeg');
    } catch (error) {
      if (mounted) snack(context, 'Could not select image: ' + error.toString());
    }
  }

  Future<void> _pickGroupDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      final selected = result?.files.single;
      if (selected == null || selected.path == null) return;
      final extension = selected.extension?.toLowerCase();
      final mimeType = extension == 'pdf'
          ? 'application/pdf'
          : 'application/pdf';
      await _sendGroupAttachment(File(selected.path!), selected.name, mimeType);
    } catch (error) {
      if (mounted) snack(context, 'Could not select document: ' + error.toString());
    }
  }

  Future<void> _openGroupAttachment(Map<String, dynamic> attachment) async {
    final path = attachment['storagePath']?.toString() ?? '';
    final expectedPrefix = 'group_attachments/' + widget.groupId + '/';
    if (!path.startsWith(expectedPrefix)) {
      snack(context, 'This attachment does not belong to the current group.');
      return;
    }
    try {
      final bytes = await FirebaseStorage.instance.ref(path).getData(10 * 1024 * 1024);
      if (bytes == null || bytes.isEmpty) throw StateError('The file is unavailable.');
      final mime = attachment['mimeType']?.toString() ?? '';
      if (mime.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
      } else if (mime == 'application/pdf') {
        await FileSaver.instance.saveToDownloads(
          name: attachment['name']?.toString() ?? 'SkyNest attachment',
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
          subfolder: 'SkyNest Group Files',
        );
        if (mounted) snack(context, 'PDF saved to Downloads.');
      } else {
        throw StateError('This file type is not supported.');
      }
    } catch (error) {
      if (mounted) snack(context, 'Could not open attachment: ' + error.toString());
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

  Future<void> startGroupCall(String type) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final members = await FirebaseFirestore.instance
          .collection('groups').doc(widget.groupId).collection('members').get();
      final peers = members.docs.where((doc) => doc.id != uid).toList();
      if (peers.isEmpty) {
        snack(context, 'No other members are available in this group yet.');
        return;
      }
      final selected = await showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(
              type == 'video' ? 'Start a video call' : 'Start a voice call',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            )),
            ...peers.map((peer) => ListTile(
              leading: CircleAvatar(child: Icon(type == 'video' ? Icons.videocam : Icons.call)),
              title: Text((peer.data()['displayName'] ?? 'Group member').toString()),
              subtitle: Text(peer.id, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(sheetContext, peer),
            )),
          ]),
        ),
      );
      if (selected == null || !mounted) return;
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final callerName = (profile.data()?['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'SkyNest member').toString();
      final calleeName = (selected.data()['displayName'] ?? 'SkyNest member').toString();
      final call = await FirebaseFirestore.instance.collection('calls').add({
        'groupId': widget.groupId,
        'callerId': uid,
        'calleeId': selected.id,
        'callerName': callerName,
        'calleeName': calleeName,
        'type': type,
        'status': 'preparing',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => SkyNestCallScreen(callId: call.id, isCaller: true),
      ));
    } catch (error) {
      if (mounted) snack(context, 'Could not start call: $error');
    }
  }

  Future<void> startPrivateMessage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final members = await FirebaseFirestore.instance
          .collection('groups').doc(widget.groupId).collection('members').get();
      final peers = members.docs.where((doc) => doc.id != uid).toList();
      if (peers.isEmpty) {
        snack(context, 'No other group members are available for a private chat.');
        return;
      }
      final selected = await showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Start a private conversation',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            ...peers.map((peer) => ListTile(
              leading: CircleAvatar(
                backgroundImage: (peer.data()['photoUrl']?.toString().isNotEmpty ?? false)
                    ? NetworkImage(peer.data()['photoUrl'].toString()) : null,
                child: (peer.data()['photoUrl']?.toString().isNotEmpty ?? false)
                    ? null : const Icon(Icons.person_outline_rounded),
              ),
              title: Text((peer.data()['displayName'] ?? 'Group member').toString()),
              subtitle: Text('Private · only you and this member'),
              trailing: const Icon(Icons.lock_outline_rounded),
              onTap: () => Navigator.pop(sheetContext, peer),
            )),
          ]),
        ),
      );
      if (selected == null || !mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => SkyNestDirectMessageScreen(
          peerId: selected.id,
          peerName: (selected.data()['displayName'] ?? 'Group member').toString(),
          peerPhotoUrl: selected.data()['photoUrl']?.toString(),
        ),
      ));
    } catch (error) {
      if (mounted) snack(context, 'Could not open private messaging: $error');
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
          tooltip: 'Private message',
          onPressed: startPrivateMessage,
          icon: const Icon(Icons.mark_chat_unread_rounded),
        ),
        IconButton(
          tooltip: 'Voice call',
          onPressed: () => startGroupCall('voice'),
          icon: const Icon(Icons.call_rounded),
        ),
        IconButton(
          tooltip: 'Video call',
          onPressed: () => startGroupCall('video'),
          icon: const Icon(Icons.videocam_rounded),
        ),
        IconButton(
          tooltip: 'Leave group',
          onPressed: leaveGroup,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(.55),
        child: Row(children: [
          Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _encryptionReady
                ? 'New messages are encrypted on this device before upload.'
                : (_encryptionSetupError == null ? 'Preparing secure messaging…' : 'Secure messaging setup needs attention.'),
            style: Theme.of(context).textTheme.bodySmall,
          )),
        ]),
      ),
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
              return TweenAnimationBuilder<double>(
                key: ValueKey<String>(doc.id),
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(offset: Offset(mine ? (1 - value) * 12 : (value - 1) * 12, (1 - value) * 5), child: child),
                ),
                child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  child: Card(
                    color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 9, 7, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (!mine && (data['senderPhotoUrl']?.toString().isNotEmpty ?? false)) ...[
                            CircleAvatar(radius: 11, backgroundImage: NetworkImage(data['senderPhotoUrl'].toString())),
                            const SizedBox(width: 6),
                          ],
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
                        if (data['encryptionVersion'] == 1)
                          FutureBuilder<String>(
                            future: SkyNestMessageEncryption.instance.decryptGroupMessage(
                              groupId: widget.groupId,
                              senderId: data['senderId']?.toString() ?? '',
                              recipientId: uid ?? '',
                              message: data,
                            ),
                            builder: (context, decrypted) => Text(
                              decrypted.hasData
                                  ? decrypted.data!
                                  : decrypted.hasError
                                      ? 'Unable to decrypt this message on this device.'
                                      : 'Decrypting secure message…',
                            ),
                          )
                        else
                          Text('Legacy message (not end-to-end encrypted): ${data['text']?.toString() ?? ''}'),
                        if (data['attachment'] is Map)
                          Builder(builder: (context) {
                            final attachment = Map<String, dynamic>.from(data['attachment'] as Map);
                            final mime = attachment['mimeType']?.toString() ?? '';
                            final isImage = mime.startsWith('image/');
                            return InkWell(
                              onTap: () => _openGroupAttachment(attachment),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 220,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).colorScheme.surface.withOpacity(.65),
                                ),
                                child: Row(children: [
                                  Icon(isImage ? Icons.image_rounded : Icons.picture_as_pdf_rounded, size: 28),
                                  const SizedBox(width: 9),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(attachment['name']?.toString() ?? 'Shared file',
                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${((attachment['size'] as num?)?.toInt() ?? 0) ~/ 1024} KB · Tap to open',
                                      style: Theme.of(context).textTheme.labelSmall),
                                  ])),
                                  const Icon(Icons.open_in_new_rounded, size: 17),
                                ]),
                              ),
                            );
                          }),
                        if (data['createdAt'] is Timestamp)
                          Align(alignment: Alignment.centerRight, child: Text(
                            DateFormat('HH:mm').format((data['createdAt'] as Timestamp).toDate()),
                            style: Theme.of(context).textTheme.labelSmall,
                          )),
                      ]),
                    ),
                  ),
                ),
                ),
              );
            },
          );
        },
      )),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
        PopupMenuButton<String>(
          enabled: !sending,
          tooltip: 'Attach image or document',
          icon: const Icon(Icons.attach_file_rounded),
          onSelected: (value) {
            if (value == 'image') _pickGroupImage();
            if (value == 'document') _pickGroupDocument();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Photo'))),
            PopupMenuItem(value: 'document', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF document'))),
          ],
        ),
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
  String template = 'Custom', urgency = 'Normal';
  int expiryDays = 7;
  bool mandatoryRead = false, saving = false;

  @override
  void dispose() { title.dispose(); body.dispose(); targetUids.dispose(); super.dispose(); }

  void applyTemplate(String? value) {
    if (value == null) return;
    setState(() => template = value);
    const templates = <String, List<String>>{
      'Eviction': ['Tenancy notice', 'This is a formal tenancy notice. Please review your tenancy agreement and contact the property manager promptly to discuss the next steps.'],
      'Rent hike': ['Rent adjustment notice', 'Please note the proposed rent adjustment. The effective date and applicable details will be communicated in accordance with your tenancy agreement and Kenyan law.'],
      'Meeting': ['Tenant meeting', 'You are invited to a tenants meeting. Please contact the property manager for the meeting time, venue and agenda.'],
    };
    final selected = templates[value];
    if (selected != null) {
      title.text = selected[0];
      body.text = selected[1];
    }
  }

  Future<void> publish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || title.text.trim().isEmpty || body.text.trim().isEmpty) {
      snack(context, 'Enter a notice title and message.');
      return;
    }
    setState(() => saving = true);
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = profile.data() ?? <String, dynamic>{};
      final landlordId = p['role'] == 'landlord' ? uid : p['landlordId']?.toString();
      if (landlordId == null || landlordId.isEmpty) throw StateError('Your account is not linked to a landlord.');
      final explicitTargets = targetUids.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList();
      final linkedAccounts = await FirebaseFirestore.instance.collection('users')
        .where('landlordId', isEqualTo: landlordId).where('status', isEqualTo: 'active').get();
      final linkedIds = linkedAccounts.docs.map((d) => d.id).toSet();
      if (explicitTargets.any((id) => !linkedIds.contains(id))) {
        throw StateError('One or more selected tenant IDs do not belong to this property account.');
      }
      final recipients = explicitTargets.isNotEmpty ? explicitTargets : linkedAccounts.docs.map((d) => d.id).toList();
      final expiresAt = expiryDays == 0 ? null : Timestamp.fromDate(DateTime.now().add(Duration(days: expiryDays)));
      final notice = <String, dynamic>{
        'title': title.text.trim(), 'body': body.text.trim(), 'landlordId': landlordId,
        'createdBy': uid, 'createdAt': FieldValue.serverTimestamp(),
        'audience': explicitTargets.isEmpty ? 'all' : 'selected',
        'template': template, 'urgency': urgency, 'mandatoryRead': mandatoryRead,
        'expiresAt': expiresAt,
      };
      final noticeRef = await FirebaseFirestore.instance.collection('notices').add(notice);
      final batch = FirebaseFirestore.instance.batch();
      for (final recipient in recipients) {
        final ref = FirebaseFirestore.instance.collection('users').doc(recipient)
          .collection('notices').doc(noticeRef.id);
        batch.set(ref, {...notice, 'isRead': false, 'readAt': null});
      }
      await batch.commit();
      title.clear(); body.clear(); targetUids.clear();
      await recordActivity(landlordId, 'Published a property notice');
      if (mounted) snack(context, 'Notice published to \${recipients.length} account(s).');
    } catch (e) {
      if (mounted) snack(context, 'Could not publish notice: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> acknowledgeNotice(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(data['title']?.toString() ?? 'Notice'),
      content: SingleChildScrollView(child: Text(data['body']?.toString() ?? '')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE')),
        FilledButton(onPressed: () async {
          try {
            await ref.update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (mounted) snack(context, 'Notice marked as read.');
          } catch (e) {
            if (mounted) snack(context, 'Could not acknowledge notice: ' + e.toString());
          }
        }, child: const Text('MARK AS READ')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Property notices')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, profile) {
          if (!profile.hasData) return const Center(child: CircularProgressIndicator());
          final p = profile.data?.data() ?? <String, dynamic>{};
          final isTenant = p['role'] == 'tenant';
          final landlordId = isTenant ? p['landlordId']?.toString() : (p['role'] == 'landlord' ? uid : p['landlordId']?.toString());
          if (landlordId == null || landlordId.isEmpty) return const EmptyView('No landlord linked.');
          final noticeStream = isTenant
            ? FirebaseFirestore.instance.collection('users').doc(uid).collection('notices').snapshots()
            : FirebaseFirestore.instance.collection('notices').where('landlordId', isEqualTo: landlordId).snapshots();
          return Column(children: [
            if (!isTenant) Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                DropdownButtonFormField<String>(
                  value: template,
                  decoration: const InputDecoration(labelText: 'Notice template'),
                  items: const [
                    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                    DropdownMenuItem(value: 'Eviction', child: Text('Tenancy notice')),
                    DropdownMenuItem(value: 'Rent hike', child: Text('Rent adjustment')),
                    DropdownMenuItem(value: 'Meeting', child: Text('Tenant meeting')),
                  ],
                  onChanged: applyTemplate,
                ),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Notice title')),
                TextField(controller: body, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
                TextField(controller: targetUids, decoration: const InputDecoration(labelText: 'Specific tenant UIDs (comma-separated; blank = all active tenants)')),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    value: urgency,
                    decoration: const InputDecoration(labelText: 'Urgency'),
                    items: const [
                      DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
                      DropdownMenuItem(value: 'Critical', child: Text('Critical')),
                    ],
                    onChanged: (v) => setState(() => urgency = v ?? 'Normal'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<int>(
                    value: expiryDays,
                    decoration: const InputDecoration(labelText: 'Auto-hide after'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 day')),
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 0, child: Text('Never')),
                    ],
                    onChanged: (v) => setState(() => expiryDays = v ?? 7),
                  )),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require tenant acknowledgement'),
                  subtitle: const Text('Tenants must open and acknowledge this notice. This does not block app launch.'),
                  value: mandatoryRead,
                  onChanged: (v) => setState(() => mandatoryRead = v),
                ),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: saving ? null : publish,
                  child: Text(saving ? 'Publishing...' : 'PUBLISH NOTICE'),
                )),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: noticeStream,
              builder: (context, snap) {
                if (snap.hasError) return errorView('Notices could not load: ' + snap.error.toString());
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs.where((doc) {
                  final expiry = doc.data()['expiresAt'];
                  return expiry is! Timestamp || expiry.toDate().isAfter(DateTime.now());
                }).toList();
                if (docs.isEmpty) return const EmptyView('No active notices.');
                return ListView(children: docs.map((doc) {
                  final data = doc.data();
                  final read = data['isRead'] == true;
                  final level = data['urgency']?.toString() ?? 'Normal';
                  final color = level == 'Critical' ? Colors.red : level == 'Urgent' ? Colors.orange : Colors.blue;
                  final created = data['createdAt'];
                  final createdLabel = created is Timestamp ? DateFormat('d MMM, h:mm a').format(created.toDate()) : 'Recently';
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(Icons.campaign_outlined, color: color),
                      ),
                      title: Text(data['title']?.toString() ?? 'Notice'),
                      subtitle: Text('\${level.toUpperCase()} • $createdLabel • ' + (read ? 'Read' : 'Not seen')),
                      isThreeLine: true,
                      trailing: isTenant ? (read
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : FilledButton.tonal(
                            onPressed: () => acknowledgeNotice(doc.reference, data),
                            child: Text(data['mandatoryRead'] == true ? 'READ' : 'OPEN'),
                          ))
                        : const Icon(Icons.chevron_right),
                      onTap: isTenant ? null : () => showDialog<void>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: Text(data['title']?.toString() ?? 'Notice'),
                          content: Text(data['body']?.toString() ?? ''),
                          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('CLOSE'))],
                        ),
                      ),
                    ),
                  );
                }).toList());
              },
            )),
          ]);
        },
      ),
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

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends State<ReportsScreen> {
  late Future<List<QuerySnapshot<Map<String, dynamic>>>> reportData;
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void initState() {
    super.initState();
    _load();
  }
  void _load() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    reportData = Future.wait([
      FirebaseFirestore.instance.collection('payments').where('createdBy', isEqualTo: uid).get(),
      FirebaseFirestore.instance.collection('houses').where('createdBy', isEqualTo: uid).get(),
      FirebaseFirestore.instance.collection('tenants').where('landlordId', isEqualTo: uid).get(),
    ]);
  }
  String _monthLabel(DateTime date) => DateFormat('MMMM yyyy').format(date);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Property reports'), actions: [
      IconButton(tooltip: 'Refresh reports', icon: const Icon(Icons.refresh),
        onPressed: () => setState(_load)),
    ]),
    body: FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: reportData,
      builder: (context, snap) {
        if (snap.hasError) return errorView('Reports could not load: ' + snap.error.toString());
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final payments = snap.data![0].docs;
        final houses = snap.data![1].docs;
        final tenants = snap.data![2].docs;
        final start = selectedMonth;
        final end = DateTime(start.year, start.month + 1);
        final previousStart = DateTime(start.year, start.month - 1);
        bool isVerifiedPayment(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final status = (doc.data()['status']?.toString() ?? '').toLowerCase();
          return status.contains('paid') || status.contains('received') || status.contains('verified');
        }
        final currentPayments = payments.where((doc) {
          final date = doc.data()['createdAt'];
          return isVerifiedPayment(doc) && date is Timestamp &&
            !date.toDate().isBefore(start) && date.toDate().isBefore(end);
        }).toList();
        final previousPayments = payments.where((doc) {
          final date = doc.data()['createdAt'];
          return isVerifiedPayment(doc) && date is Timestamp &&
            !date.toDate().isBefore(previousStart) && date.toDate().isBefore(start);
        }).toList();
        double total(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
          docs.fold<double>(0, (sum, doc) => sum + ((doc.data()['amount'] as num?)?.toDouble() ?? 0));
        final collected = total(currentPayments);
        final previous = total(previousPayments);
        final change = previous <= 0 ? null : ((collected - previous) / previous) * 100;
        final occupied = houses.where((doc) => doc.data()['isOccupied'] == true).length;
        final occupancy = houses.isEmpty ? 0.0 : occupied / houses.length;
        final houseTotals = <String, double>{};
        final tenantTotals = <String, double>{};
        for (final doc in currentPayments) {
          final data = doc.data();
          final amount = (data['amount'] as num?)?.toDouble() ?? 0;
          final house = data['houseNo']?.toString() ?? 'Unknown';
          final tenant = data['tenantName']?.toString() ?? 'Unknown';
          houseTotals[house] = (houseTotals[house] ?? 0) + amount;
          tenantTotals[tenant] = (tenantTotals[tenant] ?? 0) + amount;
        }
        final topHouse = houseTotals.entries.isEmpty ? null : houseTotals.entries.reduce((a, b) => a.value >= b.value ? a : b);
        final topTenant = tenantTotals.entries.isEmpty ? null : tenantTotals.entries.reduce((a, b) => a.value >= b.value ? a : b);
        final maxBar = [collected, previous].reduce((a, b) => a > b ? a : b);
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            IconButton(onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1)),
              icon: const Icon(Icons.chevron_left)),
            Expanded(child: Center(child: Text(_monthLabel(selectedMonth),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
            IconButton(onPressed: selectedMonth.month == DateTime.now().month && selectedMonth.year == DateTime.now().year
              ? null : () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1)),
              icon: const Icon(Icons.chevron_right)),
          ]))),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.auto_awesome, color: Colors.amber), SizedBox(width: 7), Text('Monthly collection')]),
            const SizedBox(height: 8),
            Text(currency.format(collected), style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),
            if (change != null) Row(children: [
              Icon(change >= 0 ? Icons.trending_up : Icons.trending_down, color: change >= 0 ? Colors.green : Colors.red),
              Text((change >= 0 ? '+' : '') + change.toStringAsFixed(1) + '% vs previous month',
                style: TextStyle(color: change >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Selected month', style: TextStyle(fontSize: 11)),
                const SizedBox(height: 5),
                LinearProgressIndicator(value: maxBar == 0 ? 0 : collected / maxBar, minHeight: 9),
              ])),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Previous month', style: TextStyle(fontSize: 11)),
                const SizedBox(height: 5),
                LinearProgressIndicator(value: maxBar == 0 ? 0 : previous / maxBar, minHeight: 9, color: Colors.blueGrey),
              ])),
            ]),
          ]))),
          Row(children: [
            Expanded(child: _ReportMetric(title: 'Properties', value: houses.length.toString(), icon: Icons.home_work_outlined)),
            const SizedBox(width: 9),
            Expanded(child: _ReportMetric(title: 'Tenants', value: tenants.length.toString(), icon: Icons.people_alt_outlined)),
            const SizedBox(width: 9),
            Expanded(child: _ReportMetric(title: 'Occupied', value: (occupancy * 100).toStringAsFixed(0) + '%', icon: Icons.apartment_outlined)),
          ]),
          const SizedBox(height: 12),
          if (topHouse != null) Card(child: ListTile(
            leading: const Icon(Icons.emoji_events_outlined, color: Colors.amber),
            title: const Text('Top earning house'),
            subtitle: Text('House ' + topHouse.key),
            trailing: Text(currency.format(topHouse.value), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          if (topTenant != null) Card(child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined, color: Colors.deepPurple),
            title: const Text('Best payment contribution'),
            subtitle: Text(topTenant.key),
            trailing: Text(currency.format(topTenant.value), style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 8),
          Text('Figures are calculated from saved payment records for the selected month. Pending submissions are not treated as verified collections.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]);
      },
    ),
  );
}
class _ReportMetric extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const _ReportMetric({required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
    Icon(icon, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 6),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
    Text(title, style: const TextStyle(fontSize: 10)),
  ])));
}

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  String _query = '';
  String _actorFilter = 'all';
  bool _suspiciousOnly = false;

  bool _isSuspicious(Map<String, dynamic> data) {
    if (data['isSuspicious'] == true) return true;
    final action = (data['action'] ?? '').toString().toLowerCase();
    return ['deleted', 'removed', 'rejected', 'suspended', 'revoked', 'failed'].any(action.contains);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: EmptyView('Sign in to view activity.'));
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log'), actions: [
        IconButton(tooltip: _suspiciousOnly ? 'Show all activity' : 'Show flagged activity',
          onPressed: () => setState(() => _suspiciousOnly = !_suspiciousOnly),
          icon: Icon(_suspiciousOnly ? Icons.shield : Icons.shield_outlined)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
            hintText: 'Search action, actor or location', border: OutlineInputBorder()),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [const Text('Actor: '), const SizedBox(width: 8), Expanded(
            child: DropdownButton<String>(isExpanded: true, value: _actorFilter, items: const [
              DropdownMenuItem(value: 'all', child: Text('Everyone')),
              DropdownMenuItem(value: 'landlord', child: Text('Landlord')),
              DropdownMenuItem(value: 'caretaker', child: Text('Caretaker')),
              DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'unknown', child: Text('Unclassified')),
            ], onChanged: (value) => setState(() => _actorFilter = value ?? 'all')))])),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('activityLogs').where('landlordId', isEqualTo: uid).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return errorView('Activity log could not load.');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs.toList()..sort((a, b) {
              final at = a.data()['createdAt']; final bt = b.data()['createdAt'];
              final ad = at is Timestamp ? at.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              final bd = bt is Timestamp ? bt.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
              return bd.compareTo(ad);
            });
            final filtered = docs.where((doc) {
              final data = doc.data();
              final role = (data['actorRole'] ?? 'unknown').toString().toLowerCase();
              final haystack = [data['action'], data['actorName'], data['actorId'], data['location']]
                .map((value) => (value ?? '').toString().toLowerCase()).join(' ');
              return (_actorFilter == 'all' || role == _actorFilter) &&
                (!_suspiciousOnly || _isSuspicious(data)) && (_query.isEmpty || haystack.contains(_query));
            }).toList();
            if (docs.isEmpty) return const EmptyView('No recorded activity yet.');
            if (filtered.isEmpty) return const EmptyView('No activity matches these filters.');
            return ListView.builder(padding: const EdgeInsets.only(bottom: 16), itemCount: filtered.length,
              itemBuilder: (context, index) {
                final data = filtered[index].data(); final flagged = _isSuspicious(data);
                final createdAt = data['createdAt'];
                final dateLabel = createdAt is Timestamp ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toDate()) : 'Time unavailable';
                final actor = (data['actorName'] ?? 'Account').toString();
                final role = (data['actorRole'] ?? 'Unclassified').toString();
                final location = (data['location'] ?? '').toString();
                return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(leading: CircleAvatar(
                    backgroundColor: flagged ? Colors.red.withOpacity(0.12) : Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(flagged ? Icons.warning_amber_rounded : Icons.history,
                      color: flagged ? Colors.red : Theme.of(context).colorScheme.primary)),
                    title: Text((data['action'] ?? 'Activity').toString()),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 5),
                      child: Text('$actor • $role\n$dateLabel${location.isEmpty ? '' : ' • $location'}')),
                    isThreeLine: true,
                    trailing: flagged ? const Tooltip(message: 'Potentially sensitive activity', child: Icon(Icons.flag, color: Colors.red)) : null));
              });
          })),
      ]),
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
          'actorRole': profile?.data()?['role'] ?? 'unknown',
          'action': 'Account ' + status + ': ' + (data['displayName'] ?? data['email'] ?? id).toString(),
          'isSuspicious': status == 'rejected',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (context.mounted) snack(context, 'Account ' + status + '.');
    } catch (e) { if (context.mounted) snack(context, 'Could not update account: ' + e.toString()); }
  }
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(appBar: AppBar(title: const Text('Tenant & caretaker approvals')),
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
    final profileData = profile.data() ?? <String, dynamic>{};
    final normalizedAction = action.toLowerCase();
    final suspicious = ['deleted', 'removed', 'rejected', 'suspended', 'revoked', 'failed'].any(normalizedAction.contains);
    await FirebaseFirestore.instance.collection('activityLogs').add({
      'landlordId': landlordId, 'actorId': user.uid,
      'actorName': profileData['displayName'] ?? user.displayName ?? 'Account',
      'actorRole': profileData['role'] ?? 'unknown',
      'action': action, 'isSuspicious': suspicious,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Activity logging must never block the primary tenant/property operation.
  }
}

Future<void> confirmDelete(BuildContext context, String prompt, Future<void> Function() action) async {
  final yes = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
    title: Row(children: [
      TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.65, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.deepOrange),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Text('Please confirm')),
    ]), content: Text(prompt),
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
