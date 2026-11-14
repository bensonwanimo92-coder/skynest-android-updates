import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class VoiceMessageBubble extends StatefulWidget {
  static const prefix = 'SKYNEST_VOICE_V1:';
  static const imagePrefix = 'SKYNEST_IMAGE_V1:';
  final String payload;
  const VoiceMessageBubble({super.key, required this.payload});

  static bool isVoiceMessage(String value) => value.startsWith(prefix);
  static String encode(Uint8List bytes) => '$prefix${base64Encode(bytes)}';
  static bool isImageMessage(String value) => value.startsWith(imagePrefix);
  static String encodeImage(Uint8List bytes) => '$imagePrefix${base64Encode(bytes)}';

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final AudioPlayer _player;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        final encoded = widget.payload.substring(VoiceMessageBubble.prefix.length);
        final bytes = base64Decode(encoded);
        await _player.play(BytesSource(bytes));
      }
    } catch (error) {
      debugPrint('Voice note playback failed: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: _failed ? null : _toggle,
      icon: Icon(_failed ? Icons.error_outline : (_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
        color: Theme.of(context).colorScheme.primary, size: 30),
    ),
    const SizedBox(width: 4),
    Icon(Icons.graphic_eq_rounded, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 7),
    Text(_failed ? 'Audio unavailable' : 'Voice message',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
  ]);
}


class EncryptedImageMessage extends StatelessWidget {
  final String payload;
  const EncryptedImageMessage({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    try {
      final encoded = payload.substring(VoiceMessageBubble.imagePrefix.length);
      final bytes = base64Decode(encoded);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(bytes, width: 230, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Padding(
            padding: EdgeInsets.all(12), child: Text('Image could not be displayed.')),
        ),
      );
    } catch (_) {
      return const Text('Image attachment is unavailable.');
    }
  }
}
