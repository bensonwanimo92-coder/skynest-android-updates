import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class MarketplaceDiscoveryScreen extends StatefulWidget {
  const MarketplaceDiscoveryScreen({super.key});
  @override
  State<MarketplaceDiscoveryScreen> createState() => _MarketplaceDiscoveryScreenState();
}

class _MarketplaceDiscoveryScreenState extends State<MarketplaceDiscoveryScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  String _category = 'All';
  static final _money = NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0);

  @override
  void initState() { super.initState(); _future = _load(); }

  int _rank(Map<String, dynamic> item) {
    switch ((item['advertiserTier'] ?? 'basic').toString()) {
      case 'premium': return 0;
      case 'standard': return 1;
      default: return 2;
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final listings = FirebaseFirestore.instance.collection('publicListings');
    final now = Timestamp.now();
    Query<Map<String, dynamic>> tier(String value) => listings
      .where('status', isEqualTo: 'approved')
      .where('advertiserTier', isEqualTo: value)
      .where('expiresAt', isGreaterThan: now)
      .orderBy('expiresAt').orderBy('createdAt', descending: true).limit(25);
    final snapshots = await Future.wait([
      tier('premium').get(), tier('standard').get(), tier('basic').get(),
      listings.where('status', isEqualTo: 'approved')
        .where('expiresAt', isGreaterThan: now)
        .orderBy('expiresAt').orderBy('createdAt', descending: true).limit(25).get(),
    ]);
    final unique = <String, Map<String, dynamic>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final data = <String, dynamic>{'id': doc.id, ...doc.data()};
        data['advertiserTier'] ??= 'basic';
        unique[doc.id] = data;
      }
    }
    final result = unique.values.toList();
    result.sort((a, b) {
      final priority = _rank(a).compareTo(_rank(b));
      if (priority != 0) return priority;
      final ad = a['createdAt'] is Timestamp ? (a['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
      final bd = b['createdAt'] is Timestamp ? (b['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
      return bd.compareTo(ad);
    });
    return result;
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
    catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')));
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> data) {
    final term = _search.trim().toLowerCase();
    return data.where((item) {
      final cat = (item['category'] ?? '').toString();
      final text = [item['title'], item['description'], item['county'], item['town'],
        item['estate'], item['businessName'], cat].whereType<Object>().join(' ').toLowerCase();
      return (_category == 'All' || cat == _category) && (term.isEmpty || text.contains(term));
    }).toList();
  }

  Widget _card(Map<String, dynamic> item, ColorScheme colors) {
    final media = (item['media'] is List ? item['media'] as List : const [])
      .whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final photos = media.where((m) => m['kind'] == 'image' && m['url'] is String)
      .map((m) => m['url'] as String).toList();
    if (photos.isEmpty && item['photoUrls'] is List) {
      photos.addAll((item['photoUrls'] as List).whereType<String>());
    }
    Map<String, dynamic>? clip;
    for (final m in media) { if (m['kind'] == 'video' && m['url'] is String) { clip = m; break; } }
    final tier = (item['advertiserTier'] ?? 'basic').toString();
    final title = (item['title'] ?? 'SkyNest advert').toString();
    final location = [item['town'], item['estate'], item['county']]
      .whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
    final amount = (item['price'] as num?)?.toDouble() ?? 0;
    final phone = (item['contactPhone'] ?? '').toString();
    final tierColor = tier == 'premium' ? const Color(0xFFB88625) : colors.secondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias, elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (photos.isNotEmpty)
          SizedBox(height: 185, child: PageView.builder(
            itemCount: photos.length.clamp(1, 8).toInt(),
            itemBuilder: (_, index) => Image.network(photos[index], fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: colors.surfaceContainerHighest,
                child: const Icon(Icons.image_not_supported_outlined, size: 40))),
          ))
        else
          Container(height: 130, width: double.infinity, color: colors.surfaceContainerHighest,
            child: Icon(Icons.photo_outlined, size: 44, color: colors.onSurfaceVariant)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text((item['category'] ?? 'ADVERT').toString() + ' · ' +
                (item['county'] ?? 'KENYA').toString(),
                style: TextStyle(fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w800,
                  color: colors.onSurfaceVariant))),
              if (tier == 'premium' || tier == 'standard')
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: tierColor.withOpacity(.13),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(tier.toUpperCase() + ' PLACEMENT',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: tierColor))),
            ]),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (location.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(location, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
            if ((item['description'] ?? '').toString().isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(item['description'].toString(), maxLines: 3, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(_money.format(amount),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colors.primary))),
              if (clip != null) OutlinedButton.icon(
                onPressed: () => _open(clip!['url'].toString()),
                icon: const Icon(Icons.play_circle_outline, size: 18), label: const Text('Tour')),
              if (phone.isNotEmpty) ...[
                const SizedBox(width: 7),
                FilledButton.icon(onPressed: () => _open('tel:' + phone),
                  icon: const Icon(Icons.call, size: 17), label: const Text('Contact')),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const categories = ['All', 'Residential', 'Commercial', 'Land', 'Development',
      'Vehicles', 'Restaurants', 'Hospitality', 'Products', 'Services', 'Luxury'];
    return Scaffold(
      appBar: AppBar(title: const Text('Tenant Discovery'),
        actions: [IconButton(onPressed: _refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(hintText: 'Search advert or location',
              prefixIcon: const Icon(Icons.search_rounded), filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
        SizedBox(height: 46, child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal,
          itemCount: categories.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ChoiceChip(label: Text(categories[i]),
            selected: _category == categories[i], onSelected: (_) => setState(() => _category = categories[i])))),
        const SizedBox(height: 8),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future, builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 10), const Text('Marketplace listings could not be loaded.'),
                  const SizedBox(height: 10), Text(snapshot.error.toString(), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                ])));
            }
            final items = _filter(snapshot.data ?? []);
            if (items.isEmpty) {
              return Center(child: Padding(padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.travel_explore_rounded, size: 52, color: colors.onSurfaceVariant),
                  const SizedBox(height: 10),
                  const Text('No approved adverts found yet.', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('New adverts appear here after moderation.', textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant)),
                ])));
            }
            return RefreshIndicator(onRefresh: () async => _refresh(),
              child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: items.length, itemBuilder: (_, i) => _card(items[i], colors)));
          })),
      ]),
    );
  }
}
