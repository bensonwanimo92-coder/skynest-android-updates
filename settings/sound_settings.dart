import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SkyNestFeedback {
  SkyNestFeedback._();

  static const _soundKey = 'skynest_feedback_sound';
  static const _vibrationKey = 'skynest_feedback_vibration';

  static Future<bool> get soundEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_soundKey) ?? true;

  static Future<bool> get vibrationEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_vibrationKey) ?? true;

  static Future<void> playTap() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_soundKey) ?? true) {
      await SystemSound.play(SystemSoundType.click);
    }
    if (prefs.getBool(_vibrationKey) ?? true) {
      await HapticFeedback.selectionClick();
    }
  }

  static Future<void> playAlert() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_soundKey) ?? true) {
      await SystemSound.play(SystemSoundType.alert);
    }
    if (prefs.getBool(_vibrationKey) ?? true) {
      await HapticFeedback.vibrate();
    }
  }
}

class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key});

  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  bool _sound = true;
  bool _vibration = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sound = prefs.getBool('skynest_feedback_sound') ?? true;
      _vibration = prefs.getBool('skynest_feedback_vibration') ?? true;
      _loading = false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sounds & vibration')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: SwitchListTile.adaptive(
        value: _sound,
        onChanged: _loading ? null : (value) async {
          setState(() => _sound = value);
          await _save('skynest_feedback_sound', value);
          if (value) await SystemSound.play(SystemSoundType.click);
        },
        secondary: const Icon(Icons.volume_up_rounded),
        title: const Text('App sounds'),
        subtitle: const Text('Tap feedback, navigation and call alerts.'),
      )),
      Card(child: SwitchListTile.adaptive(
        value: _vibration,
        onChanged: _loading ? null : (value) async {
          setState(() => _vibration = value);
          await _save('skynest_feedback_vibration', value);
          if (value) await HapticFeedback.selectionClick();
        },
        secondary: const Icon(Icons.vibration_rounded),
        title: const Text('Vibration feedback'),
        subtitle: const Text('Short haptic feedback for taps and call alerts.'),
      )),
      const SizedBox(height: 12),
      const ListTile(
        leading: Icon(Icons.info_outline_rounded),
        title: Text('Call tones'),
        subtitle: Text('Incoming ringtone and outgoing ringback use the phone’s built-in alert tone. They stop when the call is answered, declined or ended.'),
      ),
    ]),
  );
}
