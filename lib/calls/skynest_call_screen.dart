import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final GlobalKey<NavigatorState> skyNestNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<bool> skyNestFirebaseReady = ValueNotifier<bool>(false);

/// Incoming-call watcher mounted above the app's routed screens. It remains
/// alive while a user moves between dashboard tabs and chat routes.
class IncomingCallHost extends StatefulWidget {
  final Widget child;
  const IncomingCallHost({super.key, required this.child});

  @override
  State<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends State<IncomingCallHost> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callsSub;
  String? _watchingUid;
  String? _shownCallId;

  @override
  void initState() {
    super.initState();
    skyNestFirebaseReady.addListener(_onFirebaseReady);
    if (skyNestFirebaseReady.value) _onFirebaseReady();
  }

  void _onFirebaseReady() {
    if (!skyNestFirebaseReady.value || _authSub != null) return;
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_watchUser);
    _watchUser(FirebaseAuth.instance.currentUser);
  }

  void _watchUser(User? user) {
    final uid = user?.uid;
    if (_watchingUid == uid) return;
    _watchingUid = uid;
    _callsSub?.cancel();
    _shownCallId = null;
    if (uid == null) return;
    _callsSub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] == 'ringing' && _shownCallId != doc.id) {
          _shownCallId = doc.id;
          _presentIncoming(doc.id, data);
          break;
        }
      }
    }, onError: (Object error) {
      debugPrint('Incoming call listener failed: $error');
    });
  }

  Future<void> _presentIncoming(String callId, Map<String, dynamic> data) async {
    if (!mounted) return;
    final navigator = skyNestNavigatorKey.currentState;
    if (navigator == null) return;
    final callerName = (data['callerName'] ?? 'SkyNest member').toString();
    final isVideo = data['type'] == 'video';
    final accepted = await navigator.push<bool>(
      DialogRoute<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(children: [
          CircleAvatar(
            backgroundColor: Theme.of(dialogContext).colorScheme.primaryContainer,
            child: Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(isVideo ? 'Incoming video call' : 'Incoming voice call')),
        ]),
        content: Text('$callerName is calling you.'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, false),
            icon: const Icon(Icons.call_end_rounded, color: Colors.red),
            label: const Text('Decline'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Answer'),
          ),
        ],
      ),
      ),
    );

    if (!mounted) return;
    final ref = FirebaseFirestore.instance.collection('calls').doc(callId);
    if (accepted == true) {
      try {
        await ref.update({
          'status': 'connecting',
          'answeredAt': FieldValue.serverTimestamp(),
        });
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => SkyNestCallScreen(callId: callId, isCaller: false),
        ));
      } catch (error) {
        debugPrint('Could not answer call: $error');
      }
    } else {
      try {
        await ref.update({
          'status': 'declined',
          'endedAt': FieldValue.serverTimestamp(),
          'endedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      } catch (error) {
        debugPrint('Could not decline call: $error');
      }
    }
    if (mounted) setState(() => _shownCallId = null);
  }

  @override
  void dispose() {
    skyNestFirebaseReady.removeListener(_onFirebaseReady);
    _authSub?.cancel();
    _callsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SkyNestCallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  const SkyNestCallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
  });

  @override
  State<SkyNestCallScreen> createState() => _SkyNestCallScreenState();
}

class _SkyNestCallScreenState extends State<SkyNestCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidateSub;
  bool _ready = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _ending = false;
  bool _released = false;
  bool _renderersInitialized = false;
  Timer? _ringTimeout;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  String _status = 'Connecting…';
  String _peerName = 'SkyNest member';
  bool _isVideo = false;

  Map<String, dynamic> get _rtcConfiguration {
    const turnUrl = String.fromEnvironment('SKYNEST_TURN_URL');
    const turnUsername = String.fromEnvironment('SKYNEST_TURN_USERNAME');
    const turnCredential = String.fromEnvironment('SKYNEST_TURN_CREDENTIAL');
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    if (turnUrl.isNotEmpty && turnUsername.isNotEmpty && turnCredential.isNotEmpty) {
      servers.add({
        'urls': turnUrl,
        'username': turnUsername,
        'credential': turnCredential,
      });
    }
    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };
  }

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _renderersInitialized = true;
      final callRef = FirebaseFirestore.instance.collection('calls').doc(widget.callId);
      final callSnapshot = await callRef.get();
      final data = callSnapshot.data();
      if (data == null) throw StateError('This call is no longer available.');
      _isVideo = data['type'] == 'video';
      _peerName = (widget.isCaller ? data['calleeName'] : data['callerName'])
          ?.toString() ?? 'SkyNest member';

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      _localRenderer.srcObject = _localStream;

      _peer = await createPeerConnection(_rtcConfiguration);
      for (final track in _localStream!.getTracks()) {
        await _peer!.addTrack(track, _localStream!);
      }

      _peer!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams.first;
          if (mounted) setState(() => _status = 'Connected');
        }
      };
      _peer!.onIceConnectionState = (state) {
        if (!mounted) return;
        setState(() {
          if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
            _status = 'Connected';
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
            _status = 'Reconnecting…';
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            _status = 'Connection failed';
          } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
            _status = 'Call ended';
          }
        });
      };

      _peer!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        callRef.collection('candidates').add({
          'senderId': FirebaseAuth.instance.currentUser?.uid,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'createdAt': FieldValue.serverTimestamp(),
        });
      };

      _candidateSub = callRef.collection('candidates').snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final candidate = change.doc.data();
          if (candidate == null ||
              candidate['senderId'] == FirebaseAuth.instance.currentUser?.uid) continue;
          final rawIndex = candidate['sdpMLineIndex'];
          final remoteCandidate = RTCIceCandidate(
            candidate['candidate']?.toString(),
            candidate['sdpMid']?.toString(),
            rawIndex is num ? rawIndex.toInt() : null,
          );
          _addRemoteCandidate(remoteCandidate);
        }
      });

      if (widget.isCaller) {
        final offer = await _peer!.createOffer();
        await _peer!.setLocalDescription(offer);
        await callRef.update({
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'status': 'ringing',
        });
        _ringTimeout?.cancel();
        _ringTimeout = Timer(const Duration(seconds: 45), () async {
          if (!mounted || _ending) return;
          try {
            await callRef.update({
              'status': 'missed',
              'endedAt': FieldValue.serverTimestamp(),
              'endedBy': FirebaseAuth.instance.currentUser?.uid,
            });
          } catch (error) {
            debugPrint('Could not mark unanswered call: $error');
          }
        });
      } else {
        final offerData = data['offer'];
        if (offerData is! Map) throw StateError('The caller offer is missing.');
        await _peer!.setRemoteDescription(RTCSessionDescription(
          offerData['sdp']?.toString(),
          offerData['type']?.toString(),
        ));
        await _flushPendingCandidates();
        final answer = await _peer!.createAnswer();
        await _peer!.setLocalDescription(answer);
        await callRef.update({
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'status': 'active',
        });
      }

      _callSub = callRef.snapshots().listen((snapshot) async {
        final call = snapshot.data();
        if (call == null) return;
        if (widget.isCaller && call['answer'] is Map) {
          _ringTimeout?.cancel();
          final answer = call['answer'] as Map;
          final current = await _peer?.getRemoteDescription();
          if (current == null) {
            await _peer?.setRemoteDescription(RTCSessionDescription(
              answer['sdp']?.toString(),
              answer['type']?.toString(),
            ));
            await _flushPendingCandidates();
          }
        }
        final state = call['status']?.toString();
        if (state == 'declined' || state == 'ended' || state == 'missed') {
          if (mounted && !_ending) {
            setState(() => _status = state == 'declined' ? 'Call declined' : 'Call ended');
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (mounted) Navigator.of(context).maybePop();
          }
        }
      });

      if (mounted) setState(() {
        _ready = true;
        _status = widget.isCaller ? 'Calling…' : 'Joining…';
      });
    } catch (error) {
      debugPrint('WebRTC call setup failed: $error');
      await _releaseMedia();
      if (mounted) {
        setState(() => _status = 'Could not start call');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call setup failed: $error')),
        );
      }
    }
  }

  Future<void> _addRemoteCandidate(RTCIceCandidate candidate) async {
    final remoteDescription = await _peer?.getRemoteDescription();
    if (remoteDescription == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peer?.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in pending) {
      await _peer?.addCandidate(candidate);
    }
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    try {
      await FirebaseFirestore.instance.collection('calls').doc(widget.callId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (error) {
      debugPrint('Call end update failed: $error');
    }
    await _releaseMedia();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _releaseMedia() async {
    if (_released) return;
    _released = true;
    _ringTimeout?.cancel();
    await _callSub?.cancel();
    await _candidateSub?.cancel();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _peer?.close();
    await _peer?.dispose();
    if (_renderersInitialized) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
      _renderersInitialized = false;
    }
  }

  @override
  void dispose() {
    unawaited(_releaseMedia());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101820),
    appBar: AppBar(
      backgroundColor: const Color(0xFF101820),
      foregroundColor: Colors.white,
      title: Text(_peerName),
    ),
    body: Stack(fit: StackFit.expand, children: [
      if (_isVideo && _remoteRenderer.srcObject != null)
        RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
      else
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 54,
            backgroundColor: Colors.white.withOpacity(.12),
            child: Icon(_isVideo ? Icons.videocam_rounded : Icons.person_rounded,
                size: 54, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(_peerName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.white70)),
        ])),
      if (_isVideo && _localRenderer.srcObject != null)
        Positioned(
          right: 16, top: 18, width: 116, height: 164,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: RTCVideoView(_localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),
        ),
      if (_isVideo && _remoteRenderer.srcObject != null)
        Positioned(left: 18, top: 22, child: Text(_status, style: const TextStyle(color: Colors.white70))),
      Positioned(
        left: 0, right: 0, bottom: 28,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _CallControl(icon: _muted ? Icons.mic_off : Icons.mic, label: 'Mute', active: _muted,
            onTap: () {
              setState(() => _muted = !_muted);
              for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
                track.enabled = !_muted;
              }
            }),
          if (_isVideo) ...[
            _CallControl(icon: _cameraOff ? Icons.videocam_off : Icons.videocam, label: 'Camera', active: _cameraOff,
              onTap: () {
                setState(() => _cameraOff = !_cameraOff);
                for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
                  track.enabled = !_cameraOff;
                }
              }),
            _CallControl(icon: Icons.cameraswitch_rounded, label: 'Flip',
              onTap: () async {
                final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
                if (tracks.isEmpty || _released) return;
                try {
                  await Helper.switchCamera(tracks.first);
                } catch (error) {
                  debugPrint('Camera switch failed: $error');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not switch camera: $error')),
                    );
                  }
                }
              }),
          ],
          _CallControl(icon: _speakerOn ? Icons.volume_up : Icons.hearing, label: 'Speaker', active: _speakerOn,
            onTap: () async {
              setState(() => _speakerOn = !_speakerOn);
              await Helper.setSpeakerphoneOn(_speakerOn);
            }),
          FloatingActionButton(
            heroTag: 'end-call',
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            onPressed: _endCall,
            child: const Icon(Icons.call_end_rounded),
          ),
        ]),
      ),
      if (!_ready)
        const Positioned(top: 12, left: 0, right: 0,
          child: Center(child: CircularProgressIndicator(color: Colors.white))),
    ]),
  );
}

class _CallControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CallControl({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: active ? Colors.white : Colors.white.withOpacity(.16),
          child: Icon(icon, color: active ? Colors.black : Colors.white),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    ),
  );
}
