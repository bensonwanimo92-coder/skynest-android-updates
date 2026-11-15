import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AutomationCentreScreen extends StatefulWidget {
  const AutomationCentreScreen({super.key});

  @override
  State<AutomationCentreScreen> createState() => _AutomationCentreScreenState();
}

class _AutomationCentreScreenState extends State<AutomationCentreScreen> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  final _collection = FirebaseFirestore.instance.collection('automations');

  Future<void> _editAutomation({DocumentSnapshot<Map<String, dynamic>>? existing}) async {
    final data = existing?.data() ?? <String, dynamic>{};
    final title = TextEditingController(text: data['title']?.toString() ?? '');
    final message = TextEditingController(text: data['message']?.toString() ?? '');
    var frequency = data['frequency']?.toString() ?? 'once';
    var scheduled = (data['nextRunAt'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(hours: 1));
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create reminder' : 'Edit reminder'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                    controller: title,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Reminder title'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a title.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: message,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'What should SkyNest remind you about?'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a reminder message.' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: frequency,
                    decoration: const InputDecoration(labelText: 'Repeat'),
                    items: const [
                      DropdownMenuItem(value: 'once', child: Text('Once')),
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (value) => setDialogState(() => frequency = value ?? 'once'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: scheduled.isBefore(DateTime.now()) ? DateTime.now() : scheduled,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (date == null || !dialogContext.mounted) return;
                      final time = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(scheduled),
                      );
                      if (time == null) return;
                      setDialogState(() => scheduled = DateTime(
                        date.year, date.month, date.day, time.hour, time.minute,
                      ));
                    },
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text('First run: ${MaterialLocalizations.of(context).formatMediumDate(scheduled)} · ${TimeOfDay.fromDateTime(scheduled).format(context)}'),
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                if (!scheduled.isAfter(DateTime.now())) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Choose a future date and time.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save reminder'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && _uid != null) {
      final now = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{
        'ownerId': _uid,
        'title': title.text.trim(),
        'message': message.text.trim(),
        'frequency': frequency,
        'nextRunAt': Timestamp.fromDate(scheduled),
        'enabled': true,
        'updatedAt': now,
      };
      if (existing == null) {
        payload['createdAt'] = now;
        payload['attemptCount'] = 0;
        await _collection.add(payload);
      } else {
        await existing.reference.update(payload);
      }
    }
    title.dispose();
    message.dispose();
  }

  Future<void> _toggle(DocumentSnapshot<Map<String, dynamic>> doc, bool enabled) async {
    final data = doc.data() ?? {};
    var nextRunAt = data['nextRunAt'];
    if (enabled && (nextRunAt is! Timestamp || !nextRunAt.toDate().isAfter(DateTime.now()))) {
      nextRunAt = Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 2)));
    }
    await doc.reference.update({
      'enabled': enabled,
      'nextRunAt': nextRunAt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this automation?'),
        content: const Text('The reminder will be removed. Existing execution history is retained for audit purposes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Sign in to manage automations.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Automation centre')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAutomation(),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('New reminder'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.auto_awesome_rounded, size: 30, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Let SkyNest remember for you', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Schedule one-time or repeating reminders. SkyNest sends them to your registered devices.',
                    style: TextStyle(fontSize: 12, height: 1.35)),
                ])),
              ]),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _collection.where('ownerId', isEqualTo: uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Automations could not load. Check your connection and permissions.'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final at = (a.data()['nextRunAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  final bt = (b.data()['nextRunAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
                  return at.compareTo(bt);
                });
              if (docs.isEmpty) return ListView(children: const [
                SizedBox(height: 100),
                Icon(Icons.notifications_paused_outlined, size: 54),
                SizedBox(height: 12),
                Center(child: Text('No reminders scheduled yet.')),
                Center(child: Text('Create your first reminder to get started.')),
              ]);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final enabled = data['enabled'] == true;
                  final next = (data['nextRunAt'] as Timestamp?)?.toDate();
                  final status = data['lastStatus']?.toString() ?? 'not run yet';
                  final error = data['lastError']?.toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: enabled ? Colors.green.withOpacity(.12) : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(enabled ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
                          color: enabled ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      title: Text(data['title']?.toString() ?? 'Reminder', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(data['message']?.toString() ?? ''),
                          const SizedBox(height: 5),
                          Text(next == null
                            ? 'No next run scheduled'
                            : 'Next: ${MaterialLocalizations.of(context).formatMediumDate(next)} · ${TimeOfDay.fromDateTime(next).format(context)}'),
                          Text('Repeat: ${data['frequency'] ?? 'once'} · Last result: $status'),
                          if (error != null && error.isNotEmpty)
                            Text('Last error: $error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ]),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') await _editAutomation(existing: doc);
                          if (value == 'delete') await _delete(doc);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => _toggle(doc, !enabled),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
