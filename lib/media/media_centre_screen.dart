import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AudioPlayer skyNestMediaPlayer = AudioPlayer();
final ValueNotifier<String?> skyNestNowPlaying = ValueNotifier<String?>(null);

/// Media library for local files and direct, user-supplied media URLs.
/// Web pages are never misrepresented as playable media or download links.
class MediaCentreScreen extends StatefulWidget {
  const MediaCentreScreen({super.key});

  @override
  State<MediaCentreScreen> createState() => _MediaCentreScreenState();
}

class _MediaCentreScreenState extends State<MediaCentreScreen> {
  final TextEditingController _url = TextEditingController();
  final List<PlatformFile> _localMedia = [];
  final List<PlatformFile> _downloadedMedia = [];
  final Set<String> _favourites = {};
  final Map<String, List<String>> _playlists = {};
  List<String> _recentlyPlayed = [];
  String? _playingName;
  String _filter = 'all';
  bool _busy = false;

  static const _audioExtensions = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'};
  static const _videoExtensions = {'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp'};

  @override
  void initState() {
    super.initState();
    _loadSavedLibrary();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _loadSavedLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('skynest_media_downloads_v1') ?? [];
      final savedLocal = prefs.getStringList('skynest_media_local_v1') ?? [];
      final files = <PlatformFile>[];
      final localFiles = <PlatformFile>[];
      for (final entry in savedLocal) {
        try {
          final data = jsonDecode(entry) as Map<String, dynamic>;
          final path = data['path']?.toString();
          final name = data['name']?.toString();
          if (path != null && path.isNotEmpty && name != null && name.isNotEmpty) {
            localFiles.add(PlatformFile(name: name, size: (data['size'] as num?)?.toInt() ?? 0, path: path));
          }
        } catch (_) {}
      }
      for (final entry in saved) {
        try {
          final data = jsonDecode(entry) as Map<String, dynamic>;
          final path = data['path']?.toString();
          final name = data['name']?.toString();
          if (path != null && path.isNotEmpty && name != null && name.isNotEmpty) {
            files.add(PlatformFile(name: name, size: (data['size'] as num?)?.toInt() ?? 0, path: path));
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _localMedia
          ..clear()
          ..addAll(localFiles);
        _downloadedMedia
          ..clear()
          ..addAll(files);
        _favourites
          ..clear()
          ..addAll(prefs.getStringList('skynest_media_favourites_v1') ?? []);
        _recentlyPlayed = prefs.getStringList('skynest_media_recent_v1') ?? [];
        _playlists
          ..clear()
          ..addAll(() {
            final raw = prefs.getString('skynest_media_playlists_v1');
            if (raw == null) return <String, List<String>>{};
            try {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              return decoded.map((key, value) => MapEntry(
                key, (value as List).map((item) => item.toString()).toList()));
            } catch (_) {
              return <String, List<String>>{};
            }
          }());
      });
    } catch (error) {
      debugPrint('Saved media library could not be loaded: $error');
    }
  }

  Future<void> _saveLibraryPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('skynest_media_local_v1', _localMedia
      .where((file) => file.path != null)
      .map((file) => jsonEncode({'name': file.name, 'path': file.path, 'size': file.size}))
      .toList());
    await prefs.setStringList('skynest_media_downloads_v1', _downloadedMedia
      .where((file) => file.path != null)
      .map((file) => jsonEncode({'name': file.name, 'path': file.path, 'size': file.size}))
      .toList());
    await prefs.setStringList('skynest_media_favourites_v1', _favourites.toList());
    await prefs.setStringList('skynest_media_recent_v1', _recentlyPlayed);
    await prefs.setString('skynest_media_playlists_v1', jsonEncode(_playlists));
  }

  Future<void> _recordPlayed(PlatformFile file) async {
    final path = file.path;
    if (path == null) return;
    setState(() {
      _recentlyPlayed.remove(path);
      _recentlyPlayed.insert(0, path);
      if (_recentlyPlayed.length > 30) _recentlyPlayed.removeLast();
    });
    await _saveLibraryPreferences();
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Playlist name', hintText: 'e.g. Evening favourites'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (_playlists.keys.any((item) => item.toLowerCase() == name.toLowerCase())) {
      _message('A playlist with that name already exists.');
      return;
    }
    setState(() => _playlists[name] = []);
    await _saveLibraryPreferences();
  }

  Future<void> _addToPlaylist(PlatformFile file) async {
    if (_playlists.isEmpty) {
      await _createPlaylist();
      if (_playlists.isEmpty) return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Add to playlist')),
            ..._playlists.keys.map((name) => ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(name),
              subtitle: Text('${_playlists[name]!.length} items'),
              onTap: () => Navigator.pop(sheetContext, name),
            )),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Create a new playlist'),
              onTap: () => Navigator.pop(sheetContext, '__create__'),
            ),
          ],
        ),
      ),
    );
    if (selected == '__create__') {
      await _createPlaylist();
      if (_playlists.isEmpty) return;
      await _addToPlaylist(file);
      return;
    }
    if (selected == null || file.path == null) return;
    setState(() {
      final items = _playlists[selected]!;
      if (!items.contains(file.path)) items.add(file.path!);
    });
    await _saveLibraryPreferences();
    _message('Added to $selected.');
  }

  Future<void> _showPlaylist(String name) async {
    final paths = _playlists[name] ?? [];
    final files = [..._localMedia, ..._downloadedMedia]
      .where((file) => file.path != null && paths.contains(file.path)).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${paths.length} saved items'),
              trailing: IconButton(
                tooltip: 'Delete playlist',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  setState(() => _playlists.remove(name));
                  await _saveLibraryPreferences();
                },
              ),
            ),
            if (files.isEmpty) const ListTile(title: Text('Select the original files again to play this playlist.')),
            ...files.map((file) => ListTile(
              leading: Icon(_isAudio(file.name) ? Icons.music_note : Icons.movie_outlined),
              title: Text(file.name),
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _playLocal(file);
                },
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFavourite(PlatformFile file) async {
    final path = file.path;
    if (path == null) return;
    setState(() {
      if (!_favourites.add(path)) _favourites.remove(path);
    });
    await _saveLibraryPreferences();
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool _isAudio(String name) => _audioExtensions.contains(_extension(name));
  bool _isVideo(String name) => _videoExtensions.contains(_extension(name));

  Future<void> _pickLocal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      final accepted = result.files.where((file) =>
        file.path != null && (_isAudio(file.name) || _isVideo(file.name))).toList();
      if (!mounted) return;
      setState(() {
        for (final file in accepted) {
          if (!_localMedia.any((item) => item.path == file.path)) _localMedia.add(file);
        }
      });
      await _saveLibraryPreferences();
      if (accepted.isEmpty) _message('No supported audio or video files were selected.');
    } catch (error) {
      _message('Could not open phone media: $error');
    }
  }

  Future<void> _playLocal(PlatformFile file) async {
    final path = file.path;
    if (path == null) {
      _message('This file is not available through a local file path. Select it again from storage.');
      return;
    }
    if (_isAudio(file.name)) {
      try {
        await skyNestMediaPlayer.stop();
        await skyNestMediaPlayer.play(DeviceFileSource(path));
        if (mounted) setState(() => _playingName = file.name);
        skyNestNowPlaying.value = file.name;
        await _recordPlayed(file);
      } catch (error) {
        _message('Could not play this audio file: $error');
      }
    } else if (_isVideo(file.name)) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _MediaVideoScreen.file(path: path, title: file.name),
      ));
    }
  }

  Uri? _validHttpUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> _playOnline() async {
    final uri = _validHttpUri(_url.text);
    if (uri == null) {
      _message('Enter a valid HTTPS or HTTP media link.');
      return;
    }
    final name = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
    if (_isAudio(name)) {
      try {
        await skyNestMediaPlayer.stop();
        await skyNestMediaPlayer.play(UrlSource(uri.toString()));
        if (mounted) setState(() => _playingName = name);
        skyNestNowPlaying.value = name;
      } catch (error) {
        _message('This link could not be streamed as audio: $error');
      }
    } else if (_isVideo(name)) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _MediaVideoScreen.network(url: uri, title: name),
      ));
    } else {
      _message('This looks like a web page, not a direct audio/video file. Open the provider link instead.');
    }
  }

  Future<void> _openProvider() async {
    final uri = _validHttpUri(_url.text);
    if (uri == null) {
      _message('Enter a valid provider website link first.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('The provider link could not be opened.');
    }
  }

  Future<void> _downloadDirect() async {
    final uri = _validHttpUri(_url.text);
    if (uri == null) {
      _message('Enter a valid direct media download link.');
      return;
    }
    final name = uri.pathSegments.isEmpty ? 'skynest_media' : uri.pathSegments.last;
    if (!_isAudio(name) && !_isVideo(name)) {
      _message('Only direct audio/video file links can be downloaded here. Provider web pages are not download links.');
      return;
    }
    setState(() => _busy = true);
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download server returned HTTP ${response.statusCode}.');
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      if (!contentType.startsWith('audio/') && !contentType.startsWith('video/') &&
          contentType != 'application/octet-stream') {
        throw const FormatException('The server did not return an audio/video file.');
      }
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response) {
        total += chunk.length;
        if (total > 250 * 1024 * 1024) {
          throw const FormatException('This download exceeds the 250 MB safety limit.');
        }
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save media to phone storage',
        fileName: name,
        bytes: data,
      );
      if (savedPath == null) {
        _message('Download cancelled. No file was saved.');
      } else {
        final saved = PlatformFile(name: name, size: data.length, path: savedPath);
        if (mounted) setState(() {
          _downloadedMedia.removeWhere((item) => item.path == savedPath);
          _downloadedMedia.insert(0, saved);
        });
        await _saveLibraryPreferences();
        _message('Saved to phone storage: $savedPath');
      }
    } catch (error) {
      _message('Download failed: $error');
    } finally {
      client?.close(force: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  List<PlatformFile> get _visibleMedia => [..._localMedia, ..._downloadedMedia].where((file) {
    if (_filter == 'audio') return _isAudio(file.name);
    if (_filter == 'video') return _isVideo(file.name);
    return true;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyNest Media Centre'),
        actions: [
          IconButton(
            tooltip: 'Add media from phone storage',
            onPressed: _busy ? null : _pickLocal,
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [const Color(0xFF07152F), colors.primary.withOpacity(.92)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.graphic_eq_rounded, color: Colors.cyanAccent, size: 30),
                SizedBox(height: 9),
                Text('Your music. Your videos. Your library.',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('Play files stored on your phone offline, stream direct media links, or save permitted downloads to storage.',
                  style: TextStyle(color: Colors.white70, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All'), icon: Icon(Icons.library_music_outlined)),
              ButtonSegment(value: 'audio', label: Text('Songs'), icon: Icon(Icons.music_note_rounded)),
              ButtonSegment(value: 'video', label: Text('Videos'), icon: Icon(Icons.video_library_outlined)),
            ],
            selected: {_filter},
            onSelectionChanged: (value) => setState(() => _filter = value.first),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.folder_open_rounded)),
                  title: const Text('Phone storage'),
                  subtitle: const Text('Select audio and video files stored on this device'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickLocal,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.download_for_offline_outlined)),
                  title: const Text('Save a direct media link'),
                  subtitle: const Text('Downloads are saved through Android’s storage picker'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _url.text.isNotEmpty ? _downloadDirect() : _message('Enter a media link below first.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('ONLINE MEDIA', style: Theme.of(context).textTheme.labelLarge?.copyWith(
            letterSpacing: 1.1, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.link_rounded),
              hintText: 'Paste a real media or provider URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: _playOnline, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play direct link')),
              OutlinedButton.icon(onPressed: _openProvider, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Open provider')),
              OutlinedButton.icon(
                onPressed: _busy ? null : _downloadDirect,
                icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
                label: Text(_busy ? 'Downloading…' : 'Download'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('PLAYLISTS', style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.1, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant))),
              TextButton.icon(onPressed: _createPlaylist,
                icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New playlist')),
            ],
          ),
          if (_playlists.isEmpty)
            Text('Create playlists to organise your offline and local music.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else
            ..._playlists.entries.map((entry) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.queue_music_rounded)),
                title: Text(entry.key),
                subtitle: Text('${entry.value.length} saved items'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showPlaylist(entry.key),
              ),
            )),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('ON THIS DEVICE', style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.1, fontWeight: FontWeight.w800, color: colors.onSurfaceVariant))),
              Text('${_visibleMedia.length} files · ${_downloadedMedia.length} downloaded', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (_visibleMedia.isEmpty)
            Card(child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                Icon(Icons.library_music_outlined, size: 42, color: colors.onSurfaceVariant),
                const SizedBox(height: 8),
                const Text('Your local library is empty'),
                const SizedBox(height: 4),
                Text('Choose songs or videos from phone storage to begin.',
                  textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: _pickLocal, icon: const Icon(Icons.folder_open), label: const Text('Browse phone storage')),
              ]),
            ))
          else
            ..._visibleMedia.map((file) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(_isAudio(file.name) ? Icons.music_note : Icons.movie_outlined)),
                title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_isAudio(file.name) ? 'Audio file · offline' : 'Video file · offline'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: _favourites.contains(file.path) ? 'Remove favourite' : 'Add favourite',
                    icon: Icon(_favourites.contains(file.path) ? Icons.favorite : Icons.favorite_border,
                      color: _favourites.contains(file.path) ? Colors.pinkAccent : null),
                    onPressed: () => _toggleFavourite(file),
                  ),
                  IconButton(
                    tooltip: 'Add to playlist',
                    icon: const Icon(Icons.playlist_add_rounded),
                    onPressed: () => _addToPlaylist(file),
                  ),
                  IconButton(
                    tooltip: _playingName == file.name ? 'Playing' : 'Play',
                    icon: Icon(_playingName == file.name ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded),
                    onPressed: () => _playLocal(file),
                  ),
                ]),
                onTap: () => _playLocal(file),
              ),
            )),
          if (_playingName != null)
            Card(
              color: colors.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.equalizer_rounded),
                title: const Text('Now playing'),
                subtitle: Text(_playingName!, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Pause',
                  icon: const Icon(Icons.pause_rounded),
                  onPressed: () => skyNestMediaPlayer.pause(),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Online playback and downloads require genuine direct media URLs. A provider’s normal web page is opened externally; SkyNest does not bypass provider restrictions or DRM.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _MediaVideoScreen extends StatefulWidget {
  const _MediaVideoScreen.file({required this.path, required this.title}) : url = null;
  const _MediaVideoScreen.network({required this.url, required this.title}) : path = null;
  final String? path;
  final Uri? url;
  final String title;

  @override
  State<_MediaVideoScreen> createState() => _MediaVideoScreenState();
}

class _MediaVideoScreenState extends State<_MediaVideoScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = widget.path != null
      ? VideoPlayerController.file(File(widget.path!))
      : VideoPlayerController.networkUrl(widget.url!);
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      controller.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      backgroundColor: Colors.black,
      body: Center(
        child: _error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Text('Video could not be played: $_error', style: const TextStyle(color: Colors.white)))
          : controller == null || !controller.value.isInitialized
            ? const CircularProgressIndicator()
            : AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(controller),
                    VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                    Positioned(
                      bottom: 28,
                      child: IconButton.filledTonal(
                        iconSize: 34,
                        onPressed: () => setState(() {
                          controller.value.isPlaying ? controller.pause() : controller.play();
                        }),
                        icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}


/// Small in-app player that stays visible while the user navigates SkyNest.
class SkyNestGlobalMiniPlayer extends StatelessWidget {
  const SkyNestGlobalMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: skyNestNowPlaying,
      builder: (context, title, _) {
        if (title == null || title.isEmpty) return const SizedBox.shrink();
        return Material(
          color: const Color(0xF20A1830),
          elevation: 12,
          borderRadius: BorderRadius.circular(18),
          child: StreamBuilder<PlayerState>(
            stream: skyNestMediaPlayer.onPlayerStateChanged,
            initialData: PlayerState.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data == PlayerState.playing;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.graphic_eq_rounded, color: Colors.cyanAccent),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: const Text('SkyNest Media', style: TextStyle(color: Colors.white70, fontSize: 11)),
                trailing: IconButton(
                  tooltip: playing ? 'Pause playback' : 'Resume playback',
                  color: Colors.white,
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: () => playing ? skyNestMediaPlayer.pause() : skyNestMediaPlayer.resume(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
