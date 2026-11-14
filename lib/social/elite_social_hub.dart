import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../messaging/direct_message_screen.dart';

const _midnight = Color(0xFF071326);
const _panel = Color(0xFF101F3C);
const _cyan = Color(0xFF58E5F2);
const _violet = Color(0xFF9275FF);

/// Premium community hub for SkyNest groups, people, Moments and video profiles.
/// The parent supplies the existing encrypted group-chat route.
class EliteSocialHubScreen extends StatefulWidget {
  final void Function(BuildContext context, String groupId, String groupName) openGroup;
  const EliteSocialHubScreen({super.key, required this.openGroup});

  @override
  State<EliteSocialHubScreen> createState() => _EliteSocialHubScreenState();
}

class _EliteSocialHubScreenState extends State<EliteSocialHubScreen> {
  final _search = TextEditingController();
  final _picker = ImagePicker();
  String? _landlordId;
  String _role = 'tenant';
  bool _loadingProfile = true;
  bool _uploading = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _role = (data['role'] ?? 'tenant').toString();
        _landlordId = _role == 'landlord' ? user.uid : data['landlordId']?.toString();
        _loadingProfile = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loadingProfile = false);
      debugPrint('Community profile load failed: $error');
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a community group'),
        content: TextField(controller: controller, autofocus: true, maxLength: 48,
          decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Block A Residents')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || _landlordId == null) return;
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final group = FirebaseFirestore.instance.collection('groups').doc();
      await group.set({
        'name': name,
        'createdBy': _uid,
        'landlordId': _landlordId,
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': <String>[_uid],
      });
      await group.collection('members').doc(_uid).set({
        'joinedAt': FieldValue.serverTimestamp(),
        'role': _role,
        'displayName': (profile.data()?['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Member').toString(),
        'photoUrl': profile.data()?['photoUrl'] ?? FirebaseAuth.instance.currentUser?.photoURL,
      });
      if (mounted) _notice('Group created.');
    } catch (error) {
      if (mounted) _notice('Could not create group: $error');
    }
  }

  Future<void> _uploadMoment({required bool video}) async {
    if (_landlordId == null || _uploading) return;
    final picked = video
        ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 45))
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 86, maxWidth: 1800);
    if (picked == null) return;
    final captionController = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(video ? 'Share a video Moment' : 'Share a photo Moment'),
        content: TextField(controller: captionController, maxLength: 160,
          decoration: const InputDecoration(labelText: 'Add a caption (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, captionController.text.trim()), child: const Text('Share')),
        ],
      ),
    );
    captionController.dispose();
    if (caption == null) return;
    setState(() => _uploading = true);
    try {
      final extension = video ? 'mp4' : (picked.name.split('.').last.toLowerCase());
      final path = 'social_media/$_uid/moments/${DateTime.now().microsecondsSinceEpoch}.$extension';
      final task = await FirebaseStorage.instance.ref(path).putFile(
        File(picked.path),
        SettableMetadata(contentType: video ? 'video/mp4' : (picked.mimeType ?? 'image/jpeg')),
      );
      final url = await task.ref.getDownloadURL();
      final profile = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      await FirebaseFirestore.instance.collection('socialMoments').add({
        'ownerId': _uid,
        'ownerName': (profile.data()?['displayName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'SkyNest member').toString(),
        'ownerPhotoUrl': profile.data()?['photoUrl'] ?? FirebaseAuth.instance.currentUser?.photoURL,
        'landlordId': _landlordId,
        'mediaUrl': url,
        'mediaType': video ? 'video' : 'image',
        'caption': caption,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });
      if (mounted) _notice('Moment shared for 24 hours.');
    } catch (error) {
      if (mounted) _notice('Moment upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadProfileVideo() async {
    if (_landlordId == null || _uploading) return;
    final picked = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final path = 'social_media/$_uid/profile/profile_video.mp4';
      final task = await FirebaseStorage.instance.ref(path).putFile(
        File(picked.path), SettableMetadata(contentType: 'video/mp4'),
      );
      final url = await task.ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('socialProfiles').doc(_uid).set({
        'ownerId': _uid,
        'landlordId': _landlordId,
        'videoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _notice('Video profile updated.');
    } catch (error) {
      if (mounted) _notice('Video profile upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(backgroundColor: _midnight, body: Center(child: CircularProgressIndicator(color: _cyan)));
    }
    if (_landlordId == null) {
      return Scaffold(
        backgroundColor: _midnight,
        appBar: AppBar(title: const Text('SkyNest Community'), backgroundColor: _midnight, foregroundColor: Colors.white),
        body: const Center(child: Padding(padding: EdgeInsets.all(28),
          child: Text('Your account needs to be linked to a property community before groups and Moments are available.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _midnight,
        appBar: AppBar(
          backgroundColor: _midnight,
          foregroundColor: Colors.white,
          title: const Text('SkyNest Community', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: _cyan,
            labelColor: _cyan,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.groups_rounded), text: 'Groups'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'People'),
              Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Moments'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _groupsTab(),
          _peopleTab(),
          _momentsTab(),
        ]),
        floatingActionButton: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _uploading
              ? const FloatingActionButton(onPressed: null, child: Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
              : FloatingActionButton.extended(
                  key: const ValueKey('create-community-content'),
                  backgroundColor: _violet,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    final index = DefaultTabController.of(context).index;
                    if (index == 0) _createGroup();
                    if (index == 2) _chooseMomentType();
                    if (index == 1) _uploadProfileVideo();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create'),
                ),
        ),
      ),
    );
  }

  Future<void> _chooseMomentType() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.image_rounded, color: _cyan), title: const Text('Photo Moment', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context, 'image')),
        ListTile(leading: const Icon(Icons.videocam_rounded, color: _violet), title: const Text('Video Moment (up to 45 seconds)', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context, 'video')),
      ])),
    );
    if (choice != null) _uploadMoment(video: choice == 'video');
  }

  Widget _groupsTab() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Container(
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cyan.withOpacity(.22))),
      child: const Padding(padding: EdgeInsets.all(14), child: Row(children: [
        Icon(Icons.forum_rounded, color: _cyan), SizedBox(width: 10),
        Expanded(child: Text('Your property community', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        Icon(Icons.chevron_right_rounded, color: Colors.white54),
      ])),
    )),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('groups').where('landlordId', isEqualTo: _landlordId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _SocialEmpty(icon: Icons.cloud_off_rounded, title: 'Groups unavailable', subtitle: 'Check your connection and group permissions.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _cyan));
        final groups = snapshot.data!.docs;
        if (groups.isEmpty) return const _SocialEmpty(icon: Icons.groups_2_rounded, title: 'Your community starts here', subtitle: 'Create a group for residents, blocks or maintenance teams.');
        groups.sort((a,b) => (b.data()['createdAt'] as Timestamp?)?.compareTo((a.data()['createdAt'] as Timestamp?) ?? Timestamp(0,0)) ?? 0);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final doc = groups[index];
            final data = doc.data();
            final ids = (data['memberIds'] as List? ?? const []).map((e) => e.toString()).toList();
            final isMember = ids.contains(_uid);
            final groupName = (data['name'] ?? 'Community group').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: isMember ? () => widget.openGroup(context, doc.id, groupName) : null,
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF142B50), Color(0xFF0C1B35)]),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: (index.isEven ? _cyan : _violet).withOpacity(.38)),
                    boxShadow: [BoxShadow(color: (index.isEven ? _cyan : _violet).withOpacity(.08), blurRadius: 20, offset: const Offset(0,7))],
                  ),
                  child: Row(children: [
                    Container(width: 54, height: 54, decoration: BoxDecoration(
                      shape: BoxShape.circle, gradient: LinearGradient(colors: [index.isEven ? _cyan : _violet, _violet])),
                      child: const Icon(Icons.groups_rounded, color: _midnight, size: 29)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 5),
                      Text('${ids.length} members · ${isMember ? 'Tap to chat' : 'Join to participate'}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ])),
                    if (isMember) const Icon(Icons.chevron_right_rounded, color: _cyan)
                    else TextButton(onPressed: () => _joinGroup(doc.id), child: const Text('JOIN')),
                  ]),
                ),
              ),
            );
          },
        );
      },
    )),
  ]);

  Future<void> _joinGroup(String groupId) async {
    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final group = FirebaseFirestore.instance.collection('groups').doc(groupId);
      await group.update({'memberIds': FieldValue.arrayUnion([_uid])});
      await group.collection('members').doc(_uid).set({
        'joinedAt': FieldValue.serverTimestamp(), 'role': _role,
        'displayName': (profile.data()?['displayName'] ?? 'Member').toString(),
        'photoUrl': profile.data()?['photoUrl'] ?? FirebaseAuth.instance.currentUser?.photoURL,
      });
      if (mounted) _notice('Joined group.');
    } catch (error) {
      if (mounted) _notice('Could not join group: $error');
    }
  }

  Widget _peopleTab() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 10), child: TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search tenants, owners and staff…',
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.search_rounded, color: _cyan),
        filled: true, fillColor: _panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _cyan.withOpacity(.25))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _cyan.withOpacity(.18))),
      ),
    )),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').where('landlordId', isEqualTo: _landlordId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _SocialEmpty(icon: Icons.lock_outline_rounded, title: 'People directory restricted', subtitle: 'Your account may not have permission to browse this property directory.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _cyan));
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data();
          final q = _search.text.trim().toLowerCase();
          final name = (data['displayName'] ?? '').toString().toLowerCase();
          final role = (data['role'] ?? '').toString().toLowerCase();
          return d.id != _uid && (q.isEmpty || name.contains(q) || role.contains(q));
        }).toList();
        if (docs.isEmpty) return const _SocialEmpty(icon: Icons.person_search_rounded, title: 'No people found', subtitle: 'Try another search or invite residents to SkyNest.');
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 90),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final name = (data['displayName'] ?? 'SkyNest member').toString();
            final photo = data['photoUrl']?.toString();
            final role = (data['role'] ?? 'member').toString();
            final profileUrl = 'socialProfiles/${docs[index].id}';
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(.08))),
              child: ListTile(
                leading: CircleAvatar(radius: 23, backgroundImage: (photo?.isNotEmpty ?? false) ? NetworkImage(photo!) : null,
                  child: (photo?.isNotEmpty ?? false) ? null : Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(role[0].toUpperCase()+role.substring(1), style: const TextStyle(color: Colors.white60)),
                trailing: StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('socialProfiles').doc(docs[index].id).snapshots(),
                  builder: (context, profile) => Icon(
                    profile.data?.data()?['videoUrl'] != null ? Icons.play_circle_fill_rounded : Icons.person_outline_rounded,
                    color: profile.data?.data()?['videoUrl'] != null ? _cyan : Colors.white54,
                  ),
                ),
                onTap: () => _showPersonProfile(docs[index].id, name, photo),
              ),
            );
          },
        );
      },
    )),
  ]);

  Future<void> _showPersonProfile(String userId, String name, String? photo) async {
    final profile = await FirebaseFirestore.instance.collection('socialProfiles').doc(userId).get();
    if (!mounted) return;
    final video = profile.data()?['videoUrl']?.toString();
    final pageContext = context;
    showModalBottomSheet<void>(
      context: context, backgroundColor: _panel, showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(22), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 38, backgroundImage: (photo?.isNotEmpty ?? false) ? NetworkImage(photo!) : null,
            child: (photo?.isNotEmpty ?? false) ? null : const Icon(Icons.person_rounded, size: 36)),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (video != null) _NetworkVideoCard(url: video),
          if (video == null) const Text('No video profile added yet.', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: userId == _uid ? null : () {
              Navigator.pop(context);
              Navigator.push(pageContext, MaterialPageRoute<void>(builder: (_) =>
                SkyNestDirectMessageScreen(peerId: userId, peerName: name, peerPhotoUrl: photo)));
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Send private message'),
          )),
          if (userId == _uid) TextButton.icon(onPressed: () { Navigator.pop(context); _uploadProfileVideo(); },
            icon: const Icon(Icons.video_call_rounded), label: const Text('Update video profile')),
        ],
      ))),
    );
  }

  Future<void> _deleteMoment(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this Moment?'),
        content: const Text('This removes the Moment from your community.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final url = doc.data()['mediaUrl']?.toString();
      if (url != null && url.isNotEmpty) {
        try { await FirebaseStorage.instance.refFromURL(url).delete(); } catch (error) {
          debugPrint('Moment media cleanup skipped: $error');
        }
      }
      await doc.reference.delete();
      if (mounted) _notice('Moment deleted.');
    } catch (error) {
      if (mounted) _notice('Could not delete Moment: $error');
    }
  }

  Widget _momentsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('socialMoments').where('landlordId', isEqualTo: _landlordId).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const _SocialEmpty(icon: Icons.cloud_off_rounded, title: 'Moments unavailable', subtitle: 'Check your connection and community permissions.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _cyan));
      final now = DateTime.now();
      final docs = snapshot.data!.docs.where((d) {
        final expiry = d.data()['expiresAt'];
        return expiry is Timestamp && expiry.toDate().isAfter(now);
      }).toList()
        ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
          .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      if (docs.isEmpty) return const _SocialEmpty(icon: Icons.auto_awesome_rounded, title: 'No Moments yet', subtitle: 'Share a photo or short video with your property community.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final data = docs[index].data();
          final isVideo = data['mediaType'] == 'video';
          final photo = data['ownerPhotoUrl']?.toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: _violet.withOpacity(.28))),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ListTile(
                leading: CircleAvatar(backgroundImage: (photo?.isNotEmpty ?? false) ? NetworkImage(photo!) : null,
                  child: (photo?.isNotEmpty ?? false) ? null : const Icon(Icons.person_outline_rounded)),
                title: Text((data['ownerName'] ?? 'SkyNest member').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text('Moment · expires after 24 hours', style: TextStyle(color: Colors.white54, fontSize: 11)),
                trailing: data['ownerId'] == _uid ? PopupMenuButton<String>(
                  iconColor: Colors.white70,
                  onSelected: (value) { if (value == 'delete') _deleteMoment(docs[index]); },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete Moment'))],
                ) : null,
              ),
              if (!isVideo) Image.network(data['mediaUrl'].toString(), width: double.infinity, height: 240, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 160, child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54))))
              else _NetworkVideoCard(url: data['mediaUrl'].toString()),
              if ((data['caption']?.toString().isNotEmpty ?? false))
                Padding(padding: const EdgeInsets.fromLTRB(15, 11, 15, 15),
                  child: Text(data['caption'].toString(), style: const TextStyle(color: Colors.white, height: 1.35))),
            ]),
          );
        },
      );
    },
  );
}

class _SocialEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SocialEmpty({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _cyan, size: 48),
      const SizedBox(height: 13),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.4)),
    ]),
  ));
}


class _NetworkVideoCard extends StatefulWidget {
  final String url;
  const _NetworkVideoCard({required this.url});
  @override
  State<_NetworkVideoCard> createState() => _NetworkVideoCardState();
}

class _NetworkVideoCardState extends State<_NetworkVideoCard> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object error) {
        debugPrint('Community video playback failed: $error');
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox(height: 150, child: Center(
      child: Text('This video could not be played.', style: TextStyle(color: Colors.white60))));
    if (!_controller.value.isInitialized) return const SizedBox(height: 180,
      child: Center(child: CircularProgressIndicator(color: _cyan)));
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
      child: Stack(alignment: Alignment.center, children: [
        VideoPlayer(_controller),
        IconButton.filledTonal(
          iconSize: 34,
          onPressed: () => setState(() {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
          }),
          icon: Icon(_controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        Positioned(left: 8, right: 8, bottom: 8, child: VideoProgressIndicator(
          _controller, allowScrubbing: true, colors: const VideoProgressColors(
            playedColor: _cyan, bufferedColor: Colors.white38, backgroundColor: Colors.white24),
        )),
      ]),
    );
  }
}
