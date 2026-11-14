import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Records short group voice notes and stores them in the group's private
/// Firebase Storage folder. Membership checks and encrypted Firestore message
/// metadata are handled by the calling chat screen.
class SkyNestVoiceService {
  SkyNestVoiceService._();
  static final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  static bool _ready = false;
  static String? _activePath;

  static Future<void> _ensureReady() async {
    if (_ready) return;
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) throw StateError('Microphone permission is required to record a voice note.');
    await _recorder.openRecorder();
    _ready = true;
  }

  static Future<void> startRecording() async {
    await _ensureReady();
    if (_recorder.isRecording) return;
    final directory = await getTemporaryDirectory();
    _activePath = directory.path + '/skynest_voice_' + DateTime.now().millisecondsSinceEpoch.toString() + '.aac';
    await _recorder.startRecorder(toFile: _activePath, codec: Codec.aacADTS, sampleRate: 22050, bitRate: 64000);
  }

  static Future<String?> stopRecording() async {
    if (!_ready || !_recorder.isRecording) return null;
    await _recorder.stopRecorder();
    final path = _activePath;
    _activePath = null;
    if (path == null || !await File(path).exists()) return null;
    return path;
  }

  static Future<Map<String, dynamic>> uploadVoiceNote({
    required String groupId, required String userId, required String localPath,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    if (size <= 0 || size > 8 * 1024 * 1024) throw StateError('Voice note must be smaller than 8 MB.');
    final fileName = 'voice_' + DateTime.now().millisecondsSinceEpoch.toString() + '.aac';
    final storagePath = 'group_attachments/' + groupId + '/' + userId + '/' + fileName;
    await FirebaseStorage.instance.ref(storagePath).putFile(file, SettableMetadata(
      contentType: 'audio/aac', cacheControl: 'private,max-age=3600',
    ));
    return {'storagePath': storagePath, 'name': 'Voice message', 'mimeType': 'audio/aac', 'size': size};
  }

  static Future<void> dispose() async {
    if (!_ready) return;
    try {
      if (_recorder.isRecording) await _recorder.stopRecorder();
      await _recorder.closeRecorder();
    } catch (_) {}
    _ready = false;
    _activePath = null;
  }
}
