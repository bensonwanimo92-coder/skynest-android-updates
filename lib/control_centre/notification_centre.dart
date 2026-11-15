import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SkyNestNotificationRecord {
  final String id;
  final String title;
  final String body;
  final String? payload;
  final DateTime createdAt;
  final String status;
  final bool isRead;

  const SkyNestNotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.status,
    required this.isRead,
    this.payload,
  });

  factory SkyNestNotificationRecord.fromMap(Map<String, dynamic> map) {
    return SkyNestNotificationRecord(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'SkyNest update',
      body: map['body']?.toString() ?? '',
      payload: map['payload']?.toString(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: map['status']?.toString() ?? 'inbox',
      isRead: map['isRead'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'status': status,
    'isRead': isRead,
  };

  SkyNestNotificationRecord copyWith({String? status, bool? isRead}) => SkyNestNotificationRecord(
    id: id,
    title: title,
    body: body,
    payload: payload,
    createdAt: createdAt,
    status: status ?? this.status,
    isRead: isRead ?? this.isRead,
  );
}

/// Device-local notification history. Records are scoped to the signed-in
/// account and support reversible deletion through the Trash folder.
class SkyNestNotificationStore {
  static String _key(String ownerId) => 'skynest_notification_history_v1_$ownerId';

  static Future<List<SkyNestNotificationRecord>> load(String ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(ownerId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((item) =>
        SkyNestNotificationRecord.fromMap(Map<String, dynamic>.from(item))).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(String ownerId, List<SkyNestNotificationRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(ownerId), jsonEncode(records.map((item) => item.toMap()).toList()));
  }

  static Future<void> add({
    required String ownerId,
    required String title,
    required String body,
    String? payload,
  }) async {
    final records = await load(ownerId);
    final now = DateTime.now();
    records.insert(0, SkyNestNotificationRecord(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      payload: payload,
      createdAt: now,
      status: 'inbox',
      isRead: false,
    ));
    // Keep the local inbox bounded so it cannot grow without limit.
    await _write(ownerId, records.take(500).toList());
  }

  static Future<void> updateStatus(String ownerId, Set<String> ids, String status) async {
    final records = await load(ownerId);
    await _write(ownerId, records.map((item) => ids.contains(item.id)
      ? item.copyWith(status: status)
      : item).toList());
  }

  static Future<void> markRead(String ownerId, Set<String> ids, bool value) async {
    final records = await load(ownerId);
    await _write(ownerId, records.map((item) => ids.contains(item.id)
      ? item.copyWith(isRead: value)
      : item).toList());
  }

  static Future<void> permanentlyDelete(String ownerId, Set<String> ids) async {
    final records = await load(ownerId);
    await _write(ownerId, records.where((item) => !ids.contains(item.id)).toList());
  }
}

class NotificationCentreScreen extends StatefulWidget {
  final String ownerId;
  const NotificationCentreScreen({super.key, required this.ownerId});

  @override
  State<NotificationCentreScreen> createState() => _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends State<NotificationCentreScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<SkyNestNotificationRecord> _records = [];
  final Set<String> _selected = {};
  String _query = '';
  bool _loading = true;
  bool _selectionMode = false;

  static const _folders = ['inbox', 'saved', 'archived', 'trash'];
  String get _folder => _folders[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() => _selected.clear());
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await SkyNestNotificationStore.load(widget.ownerId);
    if (!mounted) return;
    setState(() {
      _records = items;
      _loading = false;
      _selected.removeWhere((id) => !items.any((item) => item.id == id));
    });
  }

  Future<void> _changeStatus(Set<String> ids, String status) async {
    await SkyNestNotificationStore.updateStatus(widget.ownerId, ids, status);
    if (!mounted) return;
    setState(() { _selected.clear(); _selectionMode = false; });
    await _load();
  }

  Future<void> _deleteForever(Set<String> ids) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('This permanently removes ${ids.length} notification(s) from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete permanently')),
        ],
      ),
    );
    if (yes != true) return;
    await SkyNestNotificationStore.permanentlyDelete(widget.ownerId, ids);
    if (!mounted) return;
    setState(() { _selected.clear(); _selectionMode = false; });
    await _load();
  }

  Future<void> _markSelected(bool read) async {
    await SkyNestNotificationStore.markRead(widget.ownerId, _selected, read);
    if (!mounted) return;
    setState(() => _selected.clear());
    await _load();
  }

  Future<void> _actOnOne(SkyNestNotificationRecord item, String action) async {
    switch (action) {
      case 'save':
        await _changeStatus({item.id}, 'saved');
        break;
      case 'archive':
        await _changeStatus({item.id}, 'archived');
        break;
      case 'delete':
        await _changeStatus({item.id}, 'trash');
        break;
      case 'restore':
        await _changeStatus({item.id}, 'inbox');
        break;
      case 'delete_forever':
        await _deleteForever({item.id});
        break;
      case 'read':
        await SkyNestNotificationStore.markRead(widget.ownerId, {item.id}, true);
        await _load();
        break;
      case 'unread':
        await SkyNestNotificationStore.markRead(widget.ownerId, {item.id}, false);
        await _load();
        break;
    }
  }

  List<SkyNestNotificationRecord> get _visible {
    final q = _query.trim().toLowerCase();
    return _records.where((item) => item.status == _folder &&
      (q.isEmpty || item.title.toLowerCase().contains(q) || item.body.toLowerCase().contains(q)))
      .toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int _count(String folder) => _records.where((item) => item.status == folder).length;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selected.length} selected' : 'Notification centre'),
        actions: [
          if (_selectionMode) ...[
            IconButton(tooltip: 'Select all', onPressed: () => setState(() {
              _selected.addAll(visible.map((item) => item.id));
            }), icon: const Icon(Icons.select_all_rounded)),
            IconButton(tooltip: 'Cancel selection', onPressed: () => setState(() {
              _selected.clear(); _selectionMode = false;
            }), icon: const Icon(Icons.close_rounded)),
          ] else
            IconButton(tooltip: 'Select notifications', onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist_rounded)),
            IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: 'Inbox ${_count('inbox')}'),
            Tab(text: 'Saved ${_count('saved')}'),
            Tab(text: 'Archived ${_count('archived')}'),
            Tab(text: 'Trash ${_count('trash')}'),
          ],
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search notifications',
              suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () => setState(() => _query = ''), icon: const Icon(Icons.clear)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (_selectionMode && _selected.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              if (_folder != 'trash') ...[
                ActionChip(avatar: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('Save'),
                  onPressed: () => _changeStatus(_selected, 'saved')),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.archive_outlined, size: 18), label: const Text('Archive'),
                  onPressed: () => _changeStatus(_selected, 'archived')),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.delete_outline, size: 18), label: const Text('Move to trash'),
                  onPressed: () => _changeStatus(_selected, 'trash')),
              ] else ...[
                ActionChip(avatar: const Icon(Icons.restore, size: 18), label: const Text('Restore'),
                  onPressed: () => _changeStatus(_selected, 'inbox')),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.delete_forever_outlined, size: 18), label: const Text('Delete forever'),
                  onPressed: () => _deleteForever(_selected)),
              ],
              const SizedBox(width: 6),
              ActionChip(avatar: const Icon(Icons.mark_email_read_outlined, size: 18), label: const Text('Mark read'),
                onPressed: () => _markSelected(true)),
            ]),
          ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: visible.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 90),
                      Icon(_folder == 'trash' ? Icons.delete_outline : Icons.notifications_none_rounded,
                        size: 58, color: colors.outline),
                      const SizedBox(height: 12),
                      Center(child: Text(_query.isEmpty ? 'No notifications in this folder.' : 'No matching notifications.',
                        style: TextStyle(color: colors.onSurfaceVariant))),
                      if (_folder == 'trash') const Center(child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Deleted notifications stay here until you remove them permanently.'),
                      )),
                    ])
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final selected = _selected.contains(item.id);
                        return Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            onLongPress: () => setState(() {
                              _selectionMode = true;
                              _selected.add(item.id);
                            }),
                            onTap: _selectionMode
                              ? () => setState(() => selected ? _selected.remove(item.id) : _selected.add(item.id))
                              : () => _actOnOne(item, item.isRead ? 'unread' : 'read'),
                            leading: _selectionMode
                              ? Checkbox(value: selected, onChanged: (value) => setState(() {
                                  if (value == true) { _selected.add(item.id); } else { _selected.remove(item.id); }
                                }))
                              : CircleAvatar(
                                  backgroundColor: item.isRead ? colors.surfaceContainerHighest : colors.primaryContainer,
                                  child: Icon(item.isRead ? Icons.notifications_none : Icons.notifications_active_outlined,
                                    color: item.isRead ? colors.onSurfaceVariant : colors.primary),
                                ),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const SizedBox(height: 4),
                              Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 5),
                              Text(MaterialLocalizations.of(context).formatShortDate(item.createdAt),
                                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                            ]),
                            trailing: _selectionMode ? null : PopupMenuButton<String>(
                              tooltip: 'Notification actions',
                              onSelected: (action) => _actOnOne(item, action),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: item.isRead ? 'unread' : 'read',
                                  child: Text(item.isRead ? 'Mark unread' : 'Mark read')),
                                if (_folder != 'saved') const PopupMenuItem(value: 'save', child: Text('Save')),
                                if (_folder != 'archived') const PopupMenuItem(value: 'archive', child: Text('Archive')),
                                if (_folder != 'trash') const PopupMenuItem(value: 'delete', child: Text('Move to trash')),
                                if (_folder == 'trash') ...[
                                  const PopupMenuItem(value: 'restore', child: Text('Restore to inbox')),
                                  const PopupMenuItem(value: 'delete_forever', child: Text('Delete permanently')),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
        ),
      ]),
    );
  }
}
