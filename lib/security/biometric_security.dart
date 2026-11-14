import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _biometricEnabledKey = 'skynest_biometric_app_lock';

class SkyNestBiometrics {
  SkyNestBiometrics._();
  static final SkyNestBiometrics instance = SkyNestBiometrics._();
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> get supported async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<bool> authenticate({String reason = 'Unlock SkyNest'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> enable() async {
    if (!await supported) return false;
    if (!await authenticate(reason: 'Confirm your identity to enable SkyNest App Lock')) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, true);
    return true;
  }

  Future<void> disable() async {
    if (!await authenticate(reason: 'Confirm your identity to disable SkyNest App Lock')) {
      throw StateError('Authentication was not completed.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, false);
  }
}

class BiometricLockGate extends StatefulWidget {
  const BiometricLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = false;
  bool _authenticating = false;
  bool _wentToBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final enabled = await SkyNestBiometrics.instance.enabled;
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _checking = false;
    });
    if (enabled) await _unlock();
  }

  Future<void> _unlock() async {
    if (_authenticating || !_locked) return;
    _authenticating = true;
    var ok = false;
    try {
      ok = await SkyNestBiometrics.instance.authenticate();
    } finally {
      _authenticating = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // local_auth itself temporarily backgrounds/resumes the app while its
    // system prompt is shown. Do not interpret that transition as the user
    // leaving SkyNest, or a successful scan can immediately re-lock the gate.
    if (_authenticating) return;

    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _wentToBackground && !_checking) {
      _wentToBackground = false;
      SkyNestBiometrics.instance.enabled.then((enabled) {
        if (!mounted || !enabled) return;
        setState(() => _locked = true);
        _unlock();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_locked) return widget.child;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fingerprint_rounded, size: 76),
            const SizedBox(height: 18),
            const Text('SkyNest is locked', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Authenticate to continue. Use your device screen lock if fingerprint is unavailable.'),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _authenticating ? null : _unlock,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Unlock SkyNest'),
            ),
          ]),
        ),
      ),
    );
  }
}

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _enabled = false;
  bool _supported = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final values = await Future.wait([
      SkyNestBiometrics.instance.enabled,
      SkyNestBiometrics.instance.supported,
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = values[0];
      _supported = values[1];
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _loading = true);
    try {
      if (value) {
        final ok = await SkyNestBiometrics.instance.enable();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometric setup was unavailable or cancelled. Check that a fingerprint or screen lock is enrolled.')),
          );
        }
      } else {
        await SkyNestBiometrics.instance.disable();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication failed. App Lock remains enabled.')),
        );
      }
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Security & fingerprint')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Icon(Icons.fingerprint_rounded, size: 64),
      const SizedBox(height: 12),
      const Text('SkyNest App Lock', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      const Text('Protects the app when it opens and returns from the background. Authentication is handled by Android; SkyNest never receives or stores fingerprint images.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      if (_loading) const Center(child: CircularProgressIndicator()) else
        SwitchListTile(
          value: _enabled,
          onChanged: _supported ? _toggle : null,
          secondary: const Icon(Icons.shield_outlined),
          title: const Text('Require biometric / device authentication'),
          subtitle: Text(_supported
            ? 'Fingerprint, face unlock where supported, or device screen-lock fallback.'
            : 'No supported biometric or device authentication is currently available.'),
        ),
      const SizedBox(height: 12),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Recovery'),
        subtitle: Text('If fingerprint recognition fails, use the device PIN, pattern or password when Android offers it. Keep your device screen lock configured.'),
      ),
    ]),
  );
}
