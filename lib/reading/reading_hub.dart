import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

class ReadingHubScreen extends StatefulWidget {
  const ReadingHubScreen({super.key});

  @override
  State<ReadingHubScreen> createState() => _ReadingHubScreenState();
}

class _ReadingHubScreenState extends State<ReadingHubScreen> {
  final TextEditingController _search = TextEditingController();
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  List<_BookResult> _results = <_BookResult>[];
  bool _searching = false;
  bool _downloading = false;
  String? _searchError;
  String _category = 'All';

  static const List<_ReadingIssue> _issues = <_ReadingIssue>[
    _ReadingIssue(
      id: 'story',
      title: 'The Lighthouse Garden',
      subtitle: 'An original illustrated-style short story',
      category: 'Storybooks',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF8E6CCF),
      sections: <_ReadingSection>[
        _ReadingSection('Chapter 1 · The forgotten path', 'At the edge of a quiet coastal village stood an old lighthouse. Its white paint had faded, and wild flowers had covered the narrow path leading to its door. Most people passed it without looking twice. A curious girl named Amina wondered why the lighthouse keeper had left so many empty flower pots on the steps.'),
        _ReadingSection('Chapter 2 · A small beginning', 'One Saturday, Amina carried a tin of water and a packet of seeds to the lighthouse. She cleared the weeds, filled the pots with soil and planted the seeds. Each afternoon she returned with water. Her grandfather told her that gardens, like friendships, grow through patience and small acts of care.'),
        _ReadingSection('Chapter 3 · The storm', 'A week later, a strong storm crossed the bay. The wind scattered leaves and bent the young stems. Amina feared that all her work was lost. At sunrise she found that a few plants had survived behind the stone wall. She tied their stems gently to small sticks and began again.'),
        _ReadingSection('Chapter 4 · A light for everyone', 'By the end of the season, bright flowers lined the path. Neighbours began to help. The lighthouse garden became a place where people shared stories, seeds and tea. Amina learned that a small act can invite a whole community to make something beautiful.'),
        _ReadingSection('Think about it', 'What made Amina continue after the storm? Which small act could improve your neighbourhood? Write a different ending in which the villagers restore the lighthouse itself.'),
      ],
    ),
    _ReadingIssue(
      id: 'history',
      title: 'History: Reading the Past',
      subtitle: 'A practical introduction to people, evidence and change',
      category: 'History',
      icon: Icons.account_balance_rounded,
      color: Color(0xFFB77945),
      sections: <_ReadingSection>[
        _ReadingSection('1 · What is history?', 'History is the study of people and societies in the past. It is more than a list of dates and famous names. It asks how people lived, worked, traded, governed themselves, raised families and responded to change.'),
        _ReadingSection('2 · Evidence matters', 'Historians use letters, photographs, maps, oral accounts, objects, buildings, newspapers and official records. Every source has a point of view. Ask who created it, when it was created, what purpose it served and whose experience may be missing.'),
        _ReadingSection('3 · Oral history', 'Interviews can preserve memories that were never written down. Record the speaker’s words carefully, ask permission before sharing, and compare memories with other evidence. Memory is valuable, but it can change over time.'),
        _ReadingSection('4 · Connecting events', 'A historical event rarely has one cause. Economic pressures, leadership, technology, geography, beliefs and international relationships may interact. Separate immediate triggers from deeper conditions.'),
        _ReadingSection('5 · A local-history project', 'Choose a place in your community. Interview two willing residents from different generations, photograph a public landmark, examine an old map if available, and write a timeline. Clearly label facts, memories and questions that remain unanswered.'),
      ],
    ),
    _ReadingIssue(
      id: 'beauty',
      title: 'Everyday Beauty & Self-Care',
      subtitle: 'A gentle guide to personal care, grooming and confidence',
      category: 'Beauty',
      icon: Icons.spa_rounded,
      color: Color(0xFFB85E83),
      sections: <_ReadingSection>[
        _ReadingSection('1 · A simple routine', 'A practical routine does not need many products. Gentle cleansing, moisturising and sun protection are useful foundations. Introduce new products one at a time and stop using anything that causes persistent irritation.'),
        _ReadingSection('2 · Skin is individual', 'Skin differs in oiliness, sensitivity and response to products. Avoid comparing your skin with edited photographs. For persistent acne, painful rashes, unusual changes or severe irritation, seek advice from a qualified health professional.'),
        _ReadingSection('3 · Hair and grooming', 'Choose a hair-care routine that suits your hair texture and daily activities. Gentle handling, clean tools and avoiding excessive heat can help reduce breakage. Personal grooming is about comfort and choice, not meeting one fixed standard.'),
        _ReadingSection('4 · Beauty on a budget', 'Use products consistently before buying more. Check ingredients, expiry dates and packaging. Do not share eye or lip products, and avoid unverified skin-lightening mixtures or products with undisclosed ingredients.'),
        _ReadingSection('5 · Confidence', 'Rest, hydration, movement, supportive relationships and self-respect matter. Beauty trends change; your worth does not depend on a trend, a brand or a particular appearance.'),
      ],
    ),
    _ReadingIssue(
      id: 'vacation',
      title: 'The Thoughtful Traveller',
      subtitle: 'Vacation planning, nature, culture and responsible travel',
      category: 'Vacation',
      icon: Icons.landscape_rounded,
      color: Color(0xFF318C85),
      sections: <_ReadingSection>[
        _ReadingSection('1 · Choose your experience', 'Decide whether the trip is for rest, wildlife, beaches, history, photography, food or adventure. A clear purpose helps you choose a suitable destination and avoid an exhausting itinerary.'),
        _ReadingSection('2 · Plan the budget', 'Estimate transport, accommodation, meals, entry fees, local travel, connectivity and an emergency reserve. Confirm what is included before paying. Keep copies of essential bookings and emergency contacts.'),
        _ReadingSection('3 · Travel responsibly', 'Respect local customs, wildlife and protected areas. Use marked paths, avoid feeding wild animals, reduce single-use waste and support local guides and businesses where possible.'),
        _ReadingSection('4 · Pack with purpose', 'Carry identification, suitable clothing, medication you normally use, a charged phone, power bank, water bottle and basic first-aid supplies. Check weather and local travel advice before departure.'),
        _ReadingSection('5 · Keep the memories', 'Take photographs thoughtfully and ask before photographing people. Leave natural places as you found them. A slower itinerary often creates better memories than trying to visit every attraction.'),
      ],
    ),
    _ReadingIssue(
      id: 'property',
      title: 'Property & Home Living',
      subtitle: 'A practical starter guide to renting, homes and property care',
      category: 'Property',
      icon: Icons.apartment_rounded,
      color: Color(0xFF5275A7),
      sections: <_ReadingSection>[
        _ReadingSection('1 · Before renting', 'Inspect the property in daylight. Check water, electricity, drainage, doors, windows, locks, ventilation and signs of damp. Ask which services are included in the rent and who handles repairs.'),
        _ReadingSection('2 · Put agreements in writing', 'Keep a copy of the tenancy agreement, payment records, inventory and important messages. Confirm the rent amount, due date, deposit terms, notice period and responsibilities for utilities and maintenance. Local law applies, so seek qualified local advice when needed.'),
        _ReadingSection('3 · Caring for a home', 'Report leaks early, keep drains clear, use electrical equipment safely and maintain good ventilation. Record maintenance requests and retain receipts for work you pay for.'),
        _ReadingSection('4 · For property owners', 'Maintain accurate rent records, inspect shared spaces fairly, communicate changes clearly and address safety issues promptly. Apply house rules consistently and respect tenants’ privacy and legal rights.'),
        _ReadingSection('5 · A simple inspection checklist', 'Record the date, room, condition, meter readings where relevant, existing damage and photographs agreed by the parties. Both parties should keep a copy of the signed inspection record.'),
      ],
    ),
    _ReadingIssue(
      id: 'news',
      title: 'News & Media Literacy',
      subtitle: 'How to check sources, headlines, images and claims',
      category: 'News Hubs',
      icon: Icons.newspaper_rounded,
      color: Color(0xFF546E7A),
      sections: <_ReadingSection>[
        _ReadingSection('1 · Pause before sharing', 'A dramatic headline is not proof. Read beyond the headline, identify the publisher and author, and check the publication date. Old stories can circulate as if they happened today.'),
        _ReadingSection('2 · Verify important claims', 'Look for original documents, official statements and independent reporting. Compare more than one credible source. A social-media post repeating a claim is not independent confirmation.'),
        _ReadingSection('3 · Check images and video', 'Images can be cropped, edited or taken from a different event. Search for earlier appearances, inspect visible landmarks and compare the date and location with reliable reports.'),
        _ReadingSection('4 · Separate fact and opinion', 'News reports, analysis, commentary, advertising and satire serve different purposes. Identify which type you are reading and whether the writer provides evidence for conclusions.'),
        _ReadingSection('5 · Build a balanced reading habit', 'Follow more than one reputable outlet, include local and international reporting, and correct yourself when new evidence changes the picture. Be especially careful with health, safety and financial claims.'),
      ],
    ),
  ];

  static const List<_ReadingSource> _sources = <_ReadingSource>[
    _ReadingSource('Project Gutenberg', 'Free classic books and public-domain literature', 'https://www.gutenberg.org/', Icons.menu_book_rounded),
    _ReadingSource('Open Library', 'Search books by title, author or subject', 'https://openlibrary.org/', Icons.library_books_rounded),
    _ReadingSource('Library of Congress', 'Digitised books, maps, photographs and history', 'https://www.loc.gov/books/', Icons.account_balance_rounded),
    _ReadingSource('USModernist Library', 'Downloadable architecture and home-design magazine archive', 'https://www.usmodernist.org/library', Icons.architecture_rounded),
    _ReadingSource('LibriVox', 'Free public-domain audiobooks read by volunteers', 'https://librivox.org/', Icons.headphones_rounded),
    _ReadingSource('Wikisource', 'Free source texts and historical documents', 'https://wikisource.org/', Icons.article_rounded),
    _ReadingSource('BBC News', 'International and regional news coverage', 'https://www.bbc.com/news', Icons.public_rounded),
    _ReadingSource('Reuters', 'International reporting and current affairs', 'https://www.reuters.com/', Icons.language_rounded),
    _ReadingSource('The Conversation', 'Expert-led explainers and analysis', 'https://theconversation.com/', Icons.forum_rounded),
  ];

  Future<void> _searchBooks(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = <_BookResult>[];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final uri = Uri.https('openlibrary.org', '/search.json', <String, String>{
        'q': query,
        'limit': '20',
        'fields': 'key,title,author_name,first_publish_year,cover_i,has_fulltext,ia',
      });
      final request = await _http.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'SkyNestReadingHub/1.0');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Reading search returned HTTP ${response.statusCode}.');
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final docs = (decoded['docs'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_BookResult.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _results = docs;
        _searching = false;
        _searchError = docs.isEmpty ? 'No matching titles found. Try another title, author or subject.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'Search could not connect. Check your internet connection and try again.';
      });
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this reading source.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this reading source.')));
    }
  }

  Future<void> _downloadIssue(_ReadingIssue issue) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final document = pw.Document();
      document.addPage(pw.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 48, 42, 48),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Text('SKYNEST READING  •  ${issue.category.toUpperCase()}',
            style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text('SkyNest Reading  •  ${context.pageNumber}',
            style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
        ),
        build: (context) => <pw.Widget>[
          pw.SizedBox(height: 38),
          pw.Text('SKYNEST  /  READING COLLECTION',
            style: pw.TextStyle(fontSize: 9, letterSpacing: 2, color: PdfColor.fromInt(0xFF2463A6))),
          pw.SizedBox(height: 20),
          pw.Text(issue.title,
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF172B4D))),
          pw.SizedBox(height: 12),
          pw.Text(issue.subtitle, style: const pw.TextStyle(fontSize: 13, lineSpacing: 4)),
          pw.SizedBox(height: 24),
          pw.Container(height: 4, width: 74, color: PdfColor.fromInt(issue.color.value)),
          pw.SizedBox(height: 30),
          pw.Text('A complimentary original reading booklet prepared for the SkyNest community.',
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 4)),
          pw.SizedBox(height: 26),
          ...issue.sections.expand((section) => <pw.Widget>[
            pw.Text(section.heading,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF2463A6))),
            pw.SizedBox(height: 8),
            pw.Text(section.body, style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 5)),
            pw.SizedBox(height: 20),
          ]),
          pw.SizedBox(height: 12),
          pw.Text('Reading note: This is general educational content, not legal, medical, travel or financial advice.',
            style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
        ],
      ));
      final Uint8List bytes = await document.save();
      final fileName = issue.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
      await FileSaver.instance.saveToDownloads(
        name: fileName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
        subfolder: 'SkyNest Reading',
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${issue.title}.pdf saved to Downloads / SkyNest Reading.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF could not be saved. Please check storage space and try again.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _http.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>['All', 'Storybooks', 'News Hubs', 'History', 'Beauty', 'Vacation', 'Property'];
    final issues = _category == 'All'
        ? _issues
        : _issues.where((issue) => issue.category == _category).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading & Media Hub'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reading sources',
            icon: const Icon(Icons.public_rounded),
            onPressed: () => _openUrl('https://openlibrary.org/'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF153B67), Color(0xFF318C85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.auto_stories_rounded, color: Colors.white, size: 34),
              SizedBox(height: 14),
              Text('A world of reading, one place.',
                style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
              SizedBox(height: 7),
              Text('Explore original downloadable PDFs, discover books by title and visit trusted free-reading archives.',
                style: TextStyle(color: Colors.white70, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 22),
          Text('Explore the shelf', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((category) => ChoiceChip(
              label: Text(category),
              selected: _category == category,
              onSelected: (_) => setState(() => _category = category),
            )).toList(),
          ),
          const SizedBox(height: 12),
          ...issues.map((issue) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
                Container(
                  width: 54, height: 68,
                  decoration: BoxDecoration(
                    color: issue.color.withOpacity(.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(issue.icon, color: issue.color, size: 29),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(issue.subtitle, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 5),
                  Text('Original SkyNest PDF  •  ${issue.category}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: issue.color)),
                ])),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Download PDF',
                  onPressed: _downloading ? null : () => _downloadIssue(issue),
                  icon: const Icon(Icons.download_rounded),
                ),
              ]),
            ),
          )),
          const SizedBox(height: 20),
          Text('Search books live', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Search the Open Library catalogue by book name, author or subject. Availability and download rights depend on each title.',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: _searchBooks,
            decoration: InputDecoration(
              hintText: 'e.g. African history, Jane Austen, architecture',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _searching ? null : () => _searchBooks(_search.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          if (_searching) const Padding(
            padding: EdgeInsets.all(22),
            child: Center(child: CircularProgressIndicator()),
          ),
          if (_searchError != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          ..._results.map((book) => Card(
            margin: const EdgeInsets.only(top: 9),
            child: ListTile(
              leading: book.coverId == null
                  ? const CircleAvatar(child: Icon(Icons.menu_book_rounded))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        'https://covers.openlibrary.org/b/id/${book.coverId}-M.jpg',
                        width: 48, height: 62, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 48, child: Icon(Icons.menu_book_rounded)),
                      ),
                    ),
              title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(<String>[
                if (book.authors.isNotEmpty) book.authors.join(', '),
                if (book.year != null) book.year!,
                if (book.hasFullText) 'Full text listed by catalogue',
              ].join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Open catalogue entry',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => _openUrl(book.openUrl),
              ),
              onTap: () => _openUrl(book.openUrl),
            ),
          )),
          const SizedBox(height: 24),
          Text('Free reading & magazine sources', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('These links open the original publisher or archive. Some collections offer direct downloads; others provide online reading or controlled access.',
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          ..._sources.map((source) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Icon(source.icon)),
              title: Text(source.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(source.description),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openUrl(source.url),
            ),
          )),
          const SizedBox(height: 8),
          Text('Copyright note: SkyNest-generated PDFs are original learning booklets. External books and magazines remain subject to each publisher’s licence and local copyright law.',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ReadingIssue {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color color;
  final List<_ReadingSection> sections;
  const _ReadingIssue({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.color,
    required this.sections,
  });
}

class _ReadingSection {
  final String heading;
  final String body;
  const _ReadingSection(this.heading, this.body);
}

class _ReadingSource {
  final String name;
  final String description;
  final String url;
  final IconData icon;
  const _ReadingSource(this.name, this.description, this.url, this.icon);
}

class _BookResult {
  final String key;
  final String title;
  final List<String> authors;
  final String? year;
  final int? coverId;
  final bool hasFullText;
  const _BookResult({
    required this.key,
    required this.title,
    required this.authors,
    required this.year,
    required this.coverId,
    required this.hasFullText,
  });

  String get openUrl => 'https://openlibrary.org$key';

  factory _BookResult.fromJson(Map<String, dynamic> json) => _BookResult(
    key: json['key']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Untitled',
    authors: (json['author_name'] as List<dynamic>? ?? <dynamic>[])
        .map((author) => author.toString()).take(3).toList(),
    year: json['first_publish_year']?.toString(),
    coverId: json['cover_i'] is num ? (json['cover_i'] as num).toInt() : null,
    hasFullText: json['has_fulltext'] == true,
  );
}
