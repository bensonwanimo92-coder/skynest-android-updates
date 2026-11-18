import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicDomainLibraryScreen extends StatefulWidget {
  const PublicDomainLibraryScreen({super.key});
  @override
  State<PublicDomainLibraryScreen> createState() => _PublicDomainLibraryScreenState();
}

class _PublicDomainLibraryScreenState extends State<PublicDomainLibraryScreen> {
  final _search = TextEditingController();
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  List<Map<String, dynamic>> _books = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(''); }
  @override
  void dispose() { _search.dispose(); _client.close(force: true); super.dispose(); }

  Future<void> _load(String query) async {
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.https('gutendex.com', '/books/', {
        if (query.trim().isNotEmpty) 'search': query.trim(),
        'page': '1',
      });
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('Book catalogue returned HTTP ${response.statusCode}.');
      final data = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final results = (data['results'] as List? ?? const []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      if (mounted) setState(() { _books = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not reach the public-domain book catalogue. Check your internet connection and retry.'; _loading = false; });
    }
  }

  String _textUrl(Map<String, dynamic> book) {
    final formats = Map<String, dynamic>.from(book['formats'] as Map? ?? {});
    for (final key in ['text/plain; charset=utf-8','text/plain; charset=us-ascii','text/plain']) {
      final value = formats[key]?.toString() ?? '';
      if (value.startsWith('http')) return value;
    }
    for (final entry in formats.entries) {
      if (entry.key.startsWith('text/plain') && entry.value.toString().startsWith('http')) return entry.value.toString();
    }
    return '';
  }

  Future<void> _read(Map<String, dynamic> book) async {
    final url = _textUrl(book);
    if (url.isEmpty) {
      final id = book['id'];
      await launchUrl(Uri.parse('https://www.gutenberg.org/ebooks/$id'), mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _GutenbergReader(title: book['title']?.toString() ?? 'Book', url: url)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Full-Length Novels & Books')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('Read complete public-domain novels and books, not short sample booklets. Search by title, author or subject. Books open in the reader when a plain-text edition is available.', style: TextStyle(height: 1.4)),
        const SizedBox(height: 12),
        TextField(controller: _search, textInputAction: TextInputAction.search,
          decoration: InputDecoration(labelText: 'Search full-length books', hintText: 'Pride and Prejudice, adventure, Dickens…',
            prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _load(_search.text))),
          onSubmitted: _load),
      ])),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Column(children: [Text(_error!), TextButton(onPressed: () => _load(_search.text), child: const Text('RETRY'))])),
      Expanded(child: ListView.builder(itemCount: _books.length, itemBuilder: (context, index) {
        final book = _books[index];
        final authors = (book['authors'] as List? ?? const []).whereType<Map>().map((a) => a['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
        final subjects = (book['subjects'] as List? ?? const []).take(2).join(' · ');
        final count = (book['download_count'] as num?)?.toInt() ?? 0;
        return Card(margin: const EdgeInsets.fromLTRB(12,4,12,4), child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.menu_book_rounded)),
          title: Text(book['title']?.toString() ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${authors.isEmpty ? 'Author unknown' : authors}\n${subjects.isEmpty ? 'Public-domain edition' : subjects}\n$count catalogue downloads', maxLines: 3, overflow: TextOverflow.ellipsis),
          isThreeLine: true, trailing: const Icon(Icons.chrome_reader_mode_outlined),
          onTap: () => _read(book),
        ));
      })),
      const Padding(padding: EdgeInsets.all(10), child: Text('Source: Project Gutenberg / Gutendex. These are public-domain editions; availability and text format vary by title.', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
    ]),
  );
}

class _GutenbergReader extends StatefulWidget {
  const _GutenbergReader({required this.title, required this.url});
  final String title;
  final String url;
  @override
  State<_GutenbergReader> createState() => _GutenbergReaderState();
}
class _GutenbergReaderState extends State<_GutenbergReader> {
  String? _text;
  String? _error;
  @override
  void initState() { super.initState(); _fetch(); }
  Future<void> _fetch() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
      try {
        final request = await client.getUrl(Uri.parse(widget.url));
        final response = await request.close();
        if (response.statusCode != 200) throw HttpException('Book text returned HTTP ${response.statusCode}.');
        final body = await response.transform(utf8.decoder).join();
        if (mounted) setState(() => _text = body);
      } finally { client.close(force: true); }
    } catch (_) { if (mounted) setState(() => _error = 'This edition could not be loaded. Please open the publisher edition online.'); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: _text == null ? Center(child: _error == null ? const CircularProgressIndicator() : Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_error!), TextButton(onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication), child: const Text('OPEN ONLINE')),
    ])) : SelectionArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22,18,22,48),
      child: SelectableText(_text!, style: const TextStyle(fontSize: 16, height: 1.65, fontFamily: 'serif')))),
  );
}
