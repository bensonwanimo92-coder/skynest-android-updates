import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Local-first media centre. Online playback accepts direct media URLs only;
/// provider pages that require DRM or a proprietary SDK are opened externally.
class SkyNestMediaCentreScreen extends StatefulWidget {
  const SkyNestMediaCentreScreen({super.key});

  @override
  State<SkyNestMediaCentreScreen> createState() => _SkyNestMediaCentreScreenState();
}

class _SkyNestMediaCentreScreenState extends State<SkyNestMediaCentreScreen> {
  final AudioPlayer _audio = AudioPlayer();
  final TextEditingController _url = TextEditingController();
  final List<File> _localAudio = [];
  final List<File> _localVideo = [];
  final List<File> _downloads = [];
  String? _storagePath;
  String? _playingName;
  bool _downloading = false;
  bool _playing = false;
  String _status = 'Choose media from your phone or paste a direct media link.';

  static const _audioExt = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'};
  static const _videoExt = {'.mp4', '.m4v', '.mov', '.webm', '.mkv'};

  @override
  void initState() {
    super.initState();
    _audio.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _loadStorage();
  }

  @override
  void dispose() {
    _audio.dispose();
    _url.dispose();
    super.dispose();
  }

  String _ext(String path) {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  Future<void> _loadStorage() async {
    try {
      final directory = _storagePath == null
          ? await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()
          : Directory(_storagePath!);
      if (!await directory.exists()) await directory.create(recursive: true);
      final files = directory.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _storagePath = directory.path;
        _downloads
          ..clear()
          ..addAll(files.where((f) => _audioExt.contains(_ext(f.path)) || _videoExt.contains(_ext(f.path))));
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Storage could not be opened: $error');
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose SkyNest downloads folder');
      if (path == null || path.isEmpty) return;
      setState(() => _storagePath = path);
      await _loadStorage();
      if (mounted) setState(() => _status = 'Downloads will be saved to the selected folder.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not select that folder: $error');
    }
  }

  Future<void> _pickLocal(bool audio) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: audio ? FileType.audio : FileType.video,
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      final picked = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
      setState(() {
        final target = audio ? _localAudio : _localVideo;
        for (final file in picked) {
          if (!target.any((old) => old.path == file.path)) target.add(file);
        }
        _status = 'Added ${picked.length} file(s) from phone storage.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not open phone media: $error');
    }
  }

  Future<void> _playAudio(File file) async {
    try {
      await _audio.stop();
      await _audio.play(DeviceFileSource(file.path));
      if (mounted) setState(() {
        _playingName = file.uri.pathSegments.last;
        _status = 'Playing from device storage.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Audio could not be played: $error');
    }
  }

  Future<void> _playOnlineAudio() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => _status = 'Enter a valid direct HTTP or HTTPS media URL.');
      return;
    }
    try {
      await _audio.stop();
      await _audio.play(UrlSource(uri.toString()));
      if (mounted) setState(() {
        _playingName = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
        _status = 'Streaming a direct online audio link.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'This link could not be streamed as audio: $error');
    }
  }

  Future<void> _playVideo(File file) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SkyNestVideoPlayer(file: file),
    ));
  }

  Future<void> _playOnlineVideo() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => _status = 'Enter a valid direct HTTP or HTTPS video URL.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SkyNestVideoPlayer(url: uri),
    ));
  }

  Future<void> _download() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => _status = 'Enter a direct download URL from a source that permits saving.');
      return;
    }
    setState(() { _downloading = true; _status = 'Downloading…'; });
    HttpClient? client;
    try {
      final directory = _storagePath == null
          ? await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()
          : Directory(_storagePath!);
      await directory.create(recursive: true);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('The source returned HTTP ${response.statusCode}.');
      }
      final contentType = response.headers.contentType?.mimeType ?? '';
      if (contentType.isNotEmpty && !contentType.startsWith('audio/') && !contentType.startsWith('video/') && contentType != 'application/octet-stream') {
        throw FormatException('The link returned $contentType, not a direct audio or video file.');
      }
      final nameFromHeader = response.headers.value(HttpHeaders.contentDispositionHeader);
      var name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final match = nameFromHeader == null ? null : RegExp(r'filename="?([^";]+)').firstMatch(nameFromHeader);
      if (match != null) name = match.group(1)!;
      name = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
      if (name.isEmpty || !name.contains('.')) {
        final extension = contentType.startsWith('audio/') ? '.mp3' : contentType.startsWith('video/') ? '.mp4' : '';
        if (extension.isEmpty) throw const FormatException('The link does not identify an audio or video file.');
        name = 'skynest_media_${DateTime.now().millisecondsSinceEpoch}$extension';
      }
      final extension = _ext(name);
      if (!_audioExt.contains(extension) && !_videoExt.contains(extension)) {
        throw const FormatException('Only supported audio and video file types can be downloaded.');
      }
      final destination = File('${directory.path}/$name');
      await response.pipe(destination.openWrite());
      if (!mounted) return;
      setState(() {
        _storagePath = directory.path;
        _downloads.removeWhere((f) => f.path == destination.path);
        _downloads.add(destination);
        _status = 'Saved $name to phone storage.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Download failed: $error');
    } finally {
      client?.close(force: true);
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _deleteDownload(File file) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete downloaded file?'),
        content: Text('Remove ${file.uri.pathSegments.last} from the selected SkyNest download folder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await file.delete();
      await _loadStorage();
      if (mounted) setState(() => _status = 'Downloaded file deleted. Original phone files are not affected.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not delete downloaded file: $error');
    }
  }

  Widget _fileList(List<File> files, {required bool audio, required bool downloaded}) {
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text('No ${audio ? 'songs' : 'videos'} selected yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return Column(children: files.map((file) {
      final name = file.uri.pathSegments.last;
      return ListTile(
        dense: true,
        leading: Icon(audio ? Icons.music_note_rounded : Icons.play_circle_outline_rounded),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(downloaded ? 'Saved on this device' : 'Phone storage'),
        onTap: () => audio ? _playAudio(file) : _playVideo(file),
        trailing: downloaded
            ? IconButton(tooltip: 'Delete download', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteDownload(file))
            : const Icon(Icons.play_arrow_rounded),
      );
    }).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyNest Media Centre'),
        actions: [
          IconButton(tooltip: 'Choose download folder', onPressed: _chooseFolder, icon: const Icon(Icons.folder_open_rounded)),
          IconButton(tooltip: 'Refresh downloads', onPressed: _loadStorage, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF07152F), Color(0xFF173B67)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.graphic_eq_rounded, color: Color(0xFF67E8F9), size: 30),
              const SizedBox(height: 8),
              const Text('Your media, your way', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(_status, style: const TextStyle(color: Colors.white70)),
              if (_playingName != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text(_playingName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => _playing ? _audio.pause() : _audio.resume(), icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 30)),
                  IconButton(onPressed: _audio.stop, icon: const Icon(Icons.stop_circle_outlined, color: Colors.white, size: 28)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Card(child: Column(children: [
            ListTile(title: const Text('Local songs'), subtitle: const Text('Choose music stored on your phone'), leading: const Icon(Icons.library_music), trailing: const Icon(Icons.add), onTap: () => _pickLocal(true)),
            if (_localAudio.isNotEmpty) _fileList(_localAudio, audio: true, downloaded: false),
            const Divider(height: 1),
            ListTile(title: const Text('Local videos'), subtitle: const Text('Choose videos stored on your phone'), leading: const Icon(Icons.video_library), trailing: const Icon(Icons.add), onTap: () => _pickLocal(false)),
            if (_localVideo.isNotEmpty) _fileList(_localVideo, audio: false, downloaded: false),
          ])),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Online media', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              const Text('Paste a genuine direct audio/video URL. Provider pages with DRM or sign-in requirements must be opened in their official app or website.'),
              const SizedBox(height: 10),
              TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(prefixIcon: Icon(Icons.link), hintText: 'https://example.com/media.mp3', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _playOnlineAudio, icon: const Icon(Icons.headphones), label: const Text('Stream song')),
                OutlinedButton.icon(onPressed: _playOnlineVideo, icon: const Icon(Icons.ondemand_video), label: const Text('Play video')),
                FilledButton.icon(onPressed: _downloading ? null : _download, icon: const Icon(Icons.download), label: Text(_downloading ? 'Downloading…' : 'Download')),
              ]),
            ]),
          )),
          const SizedBox(height: 12),
          Card(child: Column(children: [
            ListTile(title: const Text('Downloads'), subtitle: Text(_storagePath ?? 'Device storage'), leading: const Icon(Icons.download_done_rounded), trailing: Text('${_downloads.length}')),
            if (_downloads.where((f) => _audioExt.contains(_ext(f.path))).isNotEmpty)
              _fileList(_downloads.where((f) => _audioExt.contains(_ext(f.path))).toList(), audio: true, downloaded: true),
            if (_downloads.where((f) => _videoExt.contains(_ext(f.path))).isNotEmpty)
              _fileList(_downloads.where((f) => _videoExt.contains(_ext(f.path))).toList(), audio: false, downloaded: true),
            if (_downloads.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Your downloaded songs and videos will appear here.')),
          ])),
        ],
      ),
    );
  }
}

class _SkyNestVideoPlayer extends StatefulWidget {
  const _SkyNestVideoPlayer({this.file, this.url});
  final File? file;
  final Uri? url;

  @override
  State<_SkyNestVideoPlayer> createState() => _SkyNestVideoPlayerState();
}

class _SkyNestVideoPlayerState extends State<_SkyNestVideoPlayer> {
  late final VideoPlayerController _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _controller = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(widget.url!);
    _initialization = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.file?.uri.pathSegments.last ?? 'Online video')),
    backgroundColor: Colors.black,
    body: Center(child: FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('This video could not be played.', style: TextStyle(color: Colors.white));
        if (snapshot.connectionState != ConnectionState.done) return const CircularProgressIndicator();
        return AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            VideoPlayer(_controller),
            VideoProgressIndicator(_controller, allowScrubbing: true),
            Align(alignment: Alignment.center, child: IconButton.filled(
              onPressed: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
              iconSize: 38,
              icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )),
          ]),
        );
      },
    )),
  );
}
