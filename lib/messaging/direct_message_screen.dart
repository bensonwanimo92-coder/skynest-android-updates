import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../security/message_encryption.dart';
import 'voice_message_bubble.dart';

class SkyNestDirectMessageScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String? peerPhotoUrl;

  const SkyNestDirectMessageScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerPhotoUrl,
  });

  @override
  State<SkyNestDirectMessageScreen> createState() => _SkyNestDirectMessageScreenState();
}

class _SkyNestDirectMessageScreenState extends State<SkyNestDirectMessageScreen> {
  final TextEditingController _message = TextEditingController();
  bool _sending = false;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ImagePicker _chatImagePicker = ImagePicker();
  bool _recordingVoice = false;
  Timer? _voiceLimit;
  bool _ready = false;
  String? _setupError;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _conversationId {
    final ids = <String>[_uid, widget.peerId]..sort();
    return ids.join('__');
  }

  DocumentReference<Map<String, dynamic>> get _conversation =>
      FirebaseFirestore.instance.collection('directConversations').doc(_conversationId);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await SkyNestMessageEncryption.instance.prepareDevice(_uid);
      final profile = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final existing = await _conversation.get();
      if (existing.exists) {
        final participants = (existing.data()?['participantIds'] as List<dynamic>? ?? <dynamic>[])
            .map((value) => value.toString()).toSet();
        if (!participants.contains(_uid) || !participants.contains(widget.peerId) || participants.length != 2) {
          throw StateError('This private conversation has invalid membership.');
        }
        await _conversation.update({'updatedAt': FieldValue.serverTimestamp()});
      } else {
        await _conversation.set({
          'participantIds': <String>[_uid, widget.peerId]..sort(),
          'participantNames': <String, String>{
            _uid: (profile.data()?['displayName'] ?? 'Member').toString(),
            widget.peerId: widget.peerName,
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _setupError = error.toString());
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending || !_ready) return;
    _message.clear();
    await _sendEncryptedPayload(text, restoreText: text);
  }

  Future<void> _sendEncryptedPayload(String payload, {String? restoreText}) async {
    if (payload.isEmpty || _sending || !_ready) return;
    setState(() => _sending = true);
    try {
      final encrypted = await SkyNestMessageEncryption.instance.encryptGroupMessage(
        groupId: _conversationId,
        senderId: _uid,
        plaintext: payload,
        memberIds: <String>[_uid, widget.peerId],
      );
      final profile = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      await _conversation.collection('messages').add({
        ...encrypted,
        'senderId': _uid,
        'senderName': (profile.data()?['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Member').toString(),
        'senderPhotoUrl': profile.data()?['photoUrl'] ?? FirebaseAuth.instance.currentUser?.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _conversation.set({'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (error) {
      if (restoreText != null) _message.text = restoreText;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message not sent: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
      await _finishVoiceRecording();
      return;
    }
    if (!_ready || _sending) return;
    try {
      if (!await _voiceRecorder.hasPermission()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for voice notes.')),
        );
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/skynest_private_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050),
        path: path,
      );
      if (mounted) setState(() => _recordingVoice = true);
      _voiceLimit?.cancel();
      _voiceLimit = Timer(const Duration(seconds: 30), _finishVoiceRecording);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start voice recording: $error')),
      );
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (!_recordingVoice) return;
    _voiceLimit?.cancel();
    final path = await _voiceRecorder.stop();
    if (mounted) setState(() => _recordingVoice = false);
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length > 700 * 1024) throw StateError('Voice note is too large. Keep recordings shorter.');
      await _sendEncryptedPayload(VoiceMessageBubble.encode(bytes));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice note could not be sent: $error')),
      );
    }
  }

  Future<void> _sendImageAttachment() async {
    if (!_ready || _sending) return;
    try {
      final picked = await _chatImagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 78, maxWidth: 1280,
      );
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      if (bytes.length > 700 * 1024) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a smaller image (under 700 KB after compression).')),
        );
        return;
      }
      await _sendEncryptedPayload(EncryptedImageMessage.encodeImage(bytes));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image could not be attached: $error')),
      );
    }
  }

  Future<String> _decrypt(Map<String, dynamic> data) {
    return SkyNestMessageEncryption.instance.decryptGroupMessage(
      groupId: _conversationId,
      senderId: data['senderId'].toString(),
      recipientId: _uid,
      message: data,
    );
  }

  @override
  void dispose() {
    _voiceLimit?.cancel();
    _message.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF071326),
    appBar: AppBar(
      backgroundColor: const Color(0xFF071326),
      foregroundColor: Colors.white,
      title: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundImage: (widget.peerPhotoUrl?.isNotEmpty ?? false)
              ? NetworkImage(widget.peerPhotoUrl!) : null,
          child: (widget.peerPhotoUrl?.isNotEmpty ?? false)
              ? null : Text(widget.peerName.isEmpty ? '?' : widget.peerName[0].toUpperCase()),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.peerName, style: const TextStyle(fontSize: 16)),
          const Text('Private conversation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
        ])),
      ]),
    ),
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFF142B50),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _ready ? 'End-to-end encrypted between you and ' + widget.peerName + '.'
                : (_setupError == null ? 'Preparing secure private messaging…' : 'Secure setup failed: ' + _setupError!),
            style: Theme.of(context).textTheme.bodySmall,
          )),
        ]),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _conversation.collection('messages').orderBy('createdAt').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Private messages could not load. Check your access and connection.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF58E5F2)));
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('This is a private conversation. Send the first message.', style: TextStyle(color: Colors.white70)));
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final mine = data['senderId'] == _uid;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
                    child: Card(
                      color: mine ? const Color(0xFF174A83) : const Color(0xFF172640),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: FutureBuilder<String>(
                          future: _decrypt(data),
                          builder: (context, decrypted) {
                            if (decrypted.hasData) {
                              final clear = decrypted.data!;
                              if (VoiceMessageBubble.isVoiceMessage(clear)) {
                                return VoiceMessageBubble(payload: clear);
                              }
                              if (VoiceMessageBubble.isImageMessage(clear)) {
                                return EncryptedImageMessage(payload: clear);
                              }
                              return Text(clear, style: const TextStyle(color: Colors.white));
                            }
                            return Text(decrypted.hasError ? 'Unable to decrypt this message on this device.' : 'Decrypting…',
                              style: const TextStyle(color: Colors.white70));
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _message,
              enabled: _ready && !_sending,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Write a private message…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'Attach encrypted photo',
              onPressed: _ready && !_sending ? _sendImageAttachment : null,
              icon: const Icon(Icons.image_outlined, color: Color(0xFF58E5F2)),
            ),
            const SizedBox(width: 2),
            IconButton(
              tooltip: _recordingVoice ? 'Stop and send voice note' : 'Record voice note (30 seconds max)',
              onPressed: _ready && !_sending ? _toggleVoiceRecording : null,
              icon: Icon(_recordingVoice ? Icons.stop_circle_rounded : Icons.mic_rounded,
                color: _recordingVoice ? Colors.redAccent : const Color(0xFF58E5F2)),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: 'Send private message',
              onPressed: _ready && !_sending ? _send : null,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]),
  );
}
