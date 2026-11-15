import 'package:flutter/material.dart';

/// Central place for user-controlled dashboard organisation.
/// Persistence is owned by the dashboard so this screen stays easy to test.
class ControlCentreScreen extends StatefulWidget {
  const ControlCentreScreen({
    super.key,
    required this.moduleTitles,
    required this.initialOrder,
    required this.initialHidden,
    required this.onSave,
    required this.onOpenNotifications,
    required this.onOpenActivityLog,
    required this.onOpenAutomations,
    required this.onOpenBackup,
    required this.onOpenGlobalSearch,
    required this.onOpenRecycleBin,
  });

  final List<String> moduleTitles;
  final List<String> initialOrder;
  final Set<String> initialHidden;
  final Future<void> Function(List<String> order, Set<String> hidden) onSave;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenActivityLog;
  final VoidCallback onOpenAutomations;
  final VoidCallback onOpenBackup;
  final VoidCallback onOpenGlobalSearch;
  final VoidCallback onOpenRecycleBin;

  @override
  State<ControlCentreScreen> createState() => _ControlCentreScreenState();
}

class _ControlCentreScreenState extends State<ControlCentreScreen> {
  late List<String> _order;
  late Set<String> _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final supplied = widget.initialOrder.where(widget.moduleTitles.contains).toList();
    _order = [...supplied, ...widget.moduleTitles.where((name) => !supplied.contains(name))];
    _hidden = widget.initialHidden.where(widget.moduleTitles.contains).toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_order, _hidden);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save dashboard preferences: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    setState(() {
      _order = List<String>.from(widget.moduleTitles);
      _hidden.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkyNest Control Centre'),
        actions: [
          TextButton(onPressed: _saving ? null : _reset, child: const Text('Reset')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .55)!],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tune_rounded, color: Colors.white, size: 28),
                SizedBox(height: 10),
                Text('Your SkyNest, your rules',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('Arrange the dashboard, hide modules you do not use, and bring them back whenever you need them.',
                  style: TextStyle(color: Colors.white, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('QUICK ACCESS', style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              ListTile(
                leading: CircleAvatar(backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.notifications_active_outlined, color: colors.primary)),
                title: const Text('Notification centre'),
                subtitle: const Text('Save, archive, restore and delete notifications'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onOpenNotifications,
              ),
              const Divider(height: 1, indent: 64),
              if (widget.moduleTitles.contains('Automation centre')) ListTile(
                leading: CircleAvatar(backgroundColor: colors.tertiaryContainer,
                  child: Icon(Icons.auto_awesome_rounded, color: colors.tertiary)),
                title: const Text('Automation centre'),
                subtitle: const Text('Create and manage scheduled reminders'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onOpenAutomations,
              ),
              if (widget.moduleTitles.contains('Recycle Bin')) ...[
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: CircleAvatar(backgroundColor: colors.errorContainer,
                    child: Icon(Icons.delete_sweep_outlined, color: colors.error)),
                  title: const Text('Recycle Bin'),
                  subtitle: const Text('Restore deleted records or remove them permanently'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenRecycleBin,
                ),
              ],
              if (widget.moduleTitles.contains('Global search')) ...[
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: CircleAvatar(backgroundColor: colors.secondaryContainer,
                    child: Icon(Icons.search_rounded, color: colors.secondary)),
                  title: const Text('Global search'),
                  subtitle: const Text('Find property, tenant, payment and plan records'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenGlobalSearch,
                ),
              ],
              if (widget.moduleTitles.contains('Backup & export')) ...[
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: CircleAvatar(backgroundColor: colors.primaryContainer,
                    child: Icon(Icons.cloud_download_outlined, color: colors.primary)),
                  title: const Text('Backup & export'),
                  subtitle: const Text('Download a portable copy of your business records'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenBackup,
                ),
              ],
              if (widget.moduleTitles.contains('Activity log')) ...[
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: CircleAvatar(backgroundColor: colors.secondaryContainer,
                    child: Icon(Icons.history_rounded, color: colors.secondary)),
                  title: const Text('Activity history'),
                  subtitle: const Text('Review account and property activity'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onOpenActivityLog,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('DASHBOARD MODULES',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w800))),
            Text('${_order.length - _hidden.length} visible',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.primary)),
          ]),
          const SizedBox(height: 5),
          Text('Drag the handle to change the order. Switch a module off to hide it without deleting its records.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final title = _order[index];
                final visible = !_hidden.contains(title);
                return ListTile(
                  key: ValueKey(title),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_indicator_rounded),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(visible ? 'Shown on dashboard' : 'Hidden — records are safe'),
                  trailing: Switch(
                    value: visible,
                    onChanged: (value) => setState(() {
                      if (value) {
                        _hidden.remove(title);
                      } else {
                        _hidden.add(title);
                      }
                    }),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
              ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Saving preferences…' : 'Save dashboard layout'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Text('Hiding a tile never deletes property, tenant, payment or other business data.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
