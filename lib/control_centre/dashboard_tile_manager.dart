import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a user's dashboard layout locally, scoped to the signed-in account.
class DashboardTilePreferences {
  static String _orderKey(String ownerId) => 'skynest_dashboard_order_v1_$ownerId';
  static String _hiddenKey(String ownerId) => 'skynest_dashboard_hidden_v1_$ownerId';

  static Future<List<String>> loadOrder(String ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_orderKey(ownerId)) ?? <String>[];
  }

  static Future<Set<String>> loadHidden(String ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenKey(ownerId)) ?? <String>[]).toSet();
  }

  static Future<void> save(String ownerId, List<String> order, Set<String> hidden) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey(ownerId), order);
    await prefs.setStringList(_hiddenKey(ownerId), hidden.toList());
  }

  static Future<void> reset(String ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderKey(ownerId));
    await prefs.remove(_hiddenKey(ownerId));
  }
}

class DashboardTileManagerScreen extends StatefulWidget {
  final String ownerId;
  final List<String> availableTiles;
  final List<String> initialOrder;
  final Set<String> initialHidden;
  final Future<void> Function(List<String> order, Set<String> hidden) onSaved;

  const DashboardTileManagerScreen({
    super.key,
    required this.ownerId,
    required this.availableTiles,
    required this.initialOrder,
    required this.initialHidden,
    required this.onSaved,
  });

  @override
  State<DashboardTileManagerScreen> createState() => _DashboardTileManagerScreenState();
}

class _DashboardTileManagerScreenState extends State<DashboardTileManagerScreen> {
  late List<String> _order;
  late Set<String> _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final known = widget.availableTiles.toSet();
    _order = [
      ...widget.initialOrder.where(known.contains),
      ...widget.availableTiles.where((item) => !widget.initialOrder.contains(item)),
    ];
    _hidden = widget.initialHidden.where(known.contains).toSet();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DashboardTilePreferences.save(widget.ownerId, _order, _hidden);
      await widget.onSaved(_order, _hidden);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save dashboard layout: $error')),
        );
      }
    }
  }

  Future<void> _restore() async {
    setState(() {
      _order = List<String>.from(widget.availableTiles);
      _hidden.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customise dashboard'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _restore,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.65),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tune_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Put your most-used sections first. Hide sections you do not need; you can bring them back at any time.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Text('YOUR DASHBOARD', style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.1, fontWeight: FontWeight.w800,
                )),
                const Spacer(),
                Text('${_order.length - _hidden.length} visible',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary)),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
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
                return Card(
                  key: ValueKey(title),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(visible ? Icons.dashboard_customize_rounded : Icons.visibility_off_outlined,
                      color: visible ? scheme.primary : scheme.outline),
                    title: Text(title, style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: visible ? null : scheme.onSurfaceVariant,
                    )),
                    subtitle: Text(visible ? 'Shown on dashboard' : 'Hidden from dashboard'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: visible,
                          onChanged: (value) => setState(() {
                            if (value) { _hidden.remove(title); } else { _hidden.add(title); }
                          }),
                        ),
                        const Icon(Icons.drag_handle_rounded),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving layout...' : 'Save dashboard layout'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
