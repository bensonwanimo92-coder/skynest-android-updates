import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight SkyNest message and call sounds.
class SkyNestSoundService {
  SkyNestSoundService._();
  static final AudioPlayer _effects = AudioPlayer();
  static final AudioPlayer _ringtone = AudioPlayer();
  static bool _ringtonePrepared = false;

  static Future<bool> get _enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('skynest_feedback_sound') ?? true;
  }

  static Future<void> playSent() async {
    if (!await _enabled) return;
    try { await _effects.stop(); await _effects.play(AssetSource('sounds/sent.wav'), volume: 0.55); } catch (_) {}
  }

  static Future<void> playReceived() async {
    if (!await _enabled) return;
    try { await _effects.stop(); await _effects.play(AssetSource('sounds/pop.wav'), volume: 0.65); } catch (_) {}
  }

  static Future<void> startRingtone() async {
    if (!await _enabled) return;
    try {
      if (!_ringtonePrepared) { await _ringtone.setReleaseMode(ReleaseMode.loop); _ringtonePrepared = true; }
      await _ringtone.stop();
      await _ringtone.play(AssetSource('sounds/ringing.wav'), volume: 0.7);
    } catch (_) {}
  }

  static Future<void> stopRingtone() async { try { await _ringtone.stop(); } catch (_) {} }

  static Future<void> dispose() async {
    await stopRingtone();
    await _effects.dispose();
    await _ringtone.dispose();
    _ringtonePrepared = false;
  }
}
