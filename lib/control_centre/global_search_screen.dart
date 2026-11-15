import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class _SearchResult {
  const _SearchResult({
    required this.collection,
    required this.id,
    required this.title,
    required this.subtitle,
  });
  final String collection;
  final String id;
  final String title;
  final String subtitle;
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, required this.onOpenCollection});
  final ValueChanged<String> onOpenCollection;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  List<_SearchResult> _results = [];
  bool _searching = false;
  String? _error;
  String _searchedFor = '';

  static const _sources = <(String, String)>[
    ('houses', 'createdBy'),
    ('tenants', 'landlordId'),
    ('payments', 'createdBy'),
    ('plans', 'createdBy'),
    ('calendarEvents', 'landlordId'),
    ('activityLogs', 'landlordId'),
    ('complaints', 'landlordId'),
  ];

  String _searchableText(Map<String, dynamic> data) => [
    'houseNo', 'name', 'phone', 'tenantName', 'title', 'note', 'action',
    'actorName', 'subject', 'details', 'status', 'transactionCode', 'method',
  ].map((key) => data[key]?.toString() ?? '').join(' ').toLowerCase();

  String _title(String collection, Map<String, dynamic> data) {
    switch (collection) {
      case 'houses': return 'House ${data['houseNo'] ?? '—'}';
      case 'tenants': return data['name']?.toString() ?? 'Tenant record';
      case 'payments': return 'Payment · ${data['tenantName'] ?? 'Tenant'}';
      case 'plans': return data['title']?.toString() ?? 'Plan';
      case 'calendarEvents': return data['title']?.toString() ?? 'Calendar event';
      case 'activityLogs': return data['action']?.toString() ?? 'Activity';
      case 'complaints': return data['subject']?.toString() ?? 'Complaint';
      default: return collection;
    }
  }

  String _subtitle(String collection, Map<String, dynamic> data) {
    switch (collection) {
      case 'houses':
        return 'Rent: ${data['rent'] ?? '—'} · ${data['status'] ?? (data['isOccupied'] == true ? 'occupied' : 'vacant')}';
      case 'tenants':
        return '${data['phone'] ?? 'No phone'} · House ${data['houseNo'] ?? '—'}';
      case 'payments':
        return 'House ${data['houseNo'] ?? '—'} · ${data['status'] ?? 'Unspecified status'}';
      case 'plans':
        return data['note']?.toString() ?? 'Property plan';
      case 'calendarEvents':
        return data['note']?.toString() ?? 'Calendar event';
      case 'activityLogs':
        return '${data['actorName'] ?? 'Account'} · ${data['actorRole'] ?? 'user'}';
      case 'complaints':
        return data['status']?.toString() ?? 'Complaint';
      default: return '';
    }
  }

  Future<void> _search() async {
    final user = FirebaseAuth.instance.currentUser;
    final query = _controller.text.trim().toLowerCase();
    if (user == null || query.length < 2 || _searching) return;
    setState(() { _searching = true; _error = null; _searchedFor = query; });
    try {
      final db = FirebaseFirestore.instance;
      final snapshots = await Future.wait(_sources.map((source) =>
        db.collection(source.$1).where(source.$2, isEqualTo: user.uid).limit(300).get(),
      ));
      final matches = <_SearchResult>[];
      for (var i = 0; i < _sources.length; i++) {
        final collection = _sources[i].$1;
        for (final doc in snapshots[i].docs) {
          final data = doc.data();
          if (_searchableText(data).contains(query)) {
            matches.add(_SearchResult(
              collection: collection,
              id: doc.id,
              title: _title(collection, data),
              subtitle: _subtitle(collection, data),
            ));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _results = matches.take(100).toList();
        if (snapshots.any((snapshot) => snapshot.size == 300)) {
          _error = 'Some categories reached the 300-record search window. Refine your search if a record is missing.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _results = []; _error = 'Search failed. Check your connection and account permissions. $error'; });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Global Search')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search houses, tenants, payments, plans…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _searching ? null : _search,
                icon: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward_rounded),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (_searchedFor.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(children: [
              Expanded(child: Text('Results for “$_searchedFor”',
                style: Theme.of(context).textTheme.labelLarge)),
              Text('${_results.length}', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800)),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
          ),
        Expanded(
          child: _searching
            ? const Center(child: CircularProgressIndicator())
            : _searchedFor.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.manage_search_rounded, size: 54, color: colors.primary),
                    const SizedBox(height: 12),
                    const Text('Search across your property records',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 5),
                    Text('Enter at least two characters to find houses, tenants, payments, plans, events and activity.',
                      textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                  ]),
                ))
              : _results.isEmpty
                ? const Center(child: Text('No matching records found.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return Card(child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          child: Icon(_iconFor(result.collection), color: colors.primary),
                        ),
                        title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_labelFor(result.collection)} · ${result.subtitle}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => widget.onOpenCollection(result.collection),
                      ));
                    },
                  ),
        ),
      ]),
    );
  }

  IconData _iconFor(String collection) {
    switch (collection) {
      case 'houses': return Icons.home_work_outlined;
      case 'tenants': return Icons.people_outline_rounded;
      case 'payments': return Icons.payments_outlined;
      case 'plans': return Icons.assignment_outlined;
      case 'calendarEvents': return Icons.calendar_month_outlined;
      case 'activityLogs': return Icons.history_rounded;
      case 'complaints': return Icons.report_problem_outlined;
      default: return Icons.search_rounded;
    }
  }

  String _labelFor(String collection) {
    switch (collection) {
      case 'houses': return 'House';
      case 'tenants': return 'Tenant';
      case 'payments': return 'Payment';
      case 'plans': return 'Plan';
      case 'calendarEvents': return 'Event';
      case 'activityLogs': return 'Activity';
      case 'complaints': return 'Complaint';
      default: return collection;
    }
  }
}
