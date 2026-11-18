import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


/// Daily plans are stored in the existing owner-scoped plans collection so
/// they inherit the same Firestore ownership rules as ordinary plans.
class DailyPlanNotebookScreen extends StatefulWidget {
  const DailyPlanNotebookScreen({super.key, this.projectPlansBuilder});
  final WidgetBuilder? projectPlansBuilder;

  @override
  State<DailyPlanNotebookScreen> createState() => _DailyPlanNotebookScreenState();
}

class _DailyPlanNotebookScreenState extends State<DailyPlanNotebookScreen> {
  DateTime _day = DateTime.now();
  int _pageIndex = 0;
  String _dateKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  Future<void> _editPage({DocumentSnapshot<Map<String, dynamic>>? page, int pageNumber = 1}) async {
    final title = TextEditingController(text: page?.data()?['title']?.toString() ?? 'Daily plan');
    final body = TextEditingController(text: page?.data()?['body']?.toString() ?? '');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(page == null ? 'Add notebook page $pageNumber' : 'Edit notebook page'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Page heading')),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 9,
                  maxLines: 18,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Write your daily plans',
                    hintText: 'Tasks, appointments, follow-ups, notes and priorities…',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Add a heading and some plan notes before saving.')),
                );
                return;
              }
              final data = <String, dynamic>{
                'recordType': 'daily_note',
                'title': title.text.trim(),
                'body': body.text.trim(),
                'dateKey': _dateKey(_day),
                'pageNumber': pageNumber,
                'createdBy': uid,
                'updatedAt': FieldValue.serverTimestamp(),
              };
              try {
                if (page == null) {
                  final existing = await FirebaseFirestore.instance.collection('plans')
                      .where('createdBy', isEqualTo: uid).get();
                  final countForDay = existing.docs.where((doc) =>
                    doc.data()['recordType'] == 'daily_note' && doc.data()['dateKey'] == _dateKey(_day)).length;
                  data['pageNumber'] = countForDay + 1;
                  data['createdAt'] = FieldValue.serverTimestamp();
                  await FirebaseFirestore.instance.collection('plans').add(data);
                  if (mounted) setState(() => _pageIndex = countForDay);
                } else {
                  await page.reference.update(data);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Could not save this page: $error')),
                  );
                }
              }
            },
            child: const Text('Save page'),
          ),
        ],
      ),
    );
    title.dispose();
    body.dispose();
  }

  Future<void> _changeDay(int offset) async {
    setState(() {
      _day = DateTime(_day.year, _day.month, _day.day + offset);
      _pageIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Sign in to use your notebook.')));
    final dateKey = _dateKey(_day);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily plans notebook'),
        actions: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => _changeDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Choose date',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() { _day = picked; _pageIndex = 0; });
            },
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => _changeDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Project plans and reminders',
            onPressed: widget.projectPlansBuilder == null ? null : () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: widget.projectPlansBuilder!),
            ),
            icon: const Icon(Icons.account_tree_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPage(pageNumber: _pageIndex + 1),
        icon: const Icon(Icons.add),
        label: const Text('New page'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('plans')
            .where('createdBy', isEqualTo: user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Notebook could not load: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final pages = snapshot.data!.docs.where((doc) =>
            doc.data()['recordType'] == 'daily_note' && doc.data()['dateKey'] == dateKey).toList()
            ..sort((a, b) => ((a.data()['pageNumber'] as num?)?.toInt() ?? 0)
                .compareTo((b.data()['pageNumber'] as num?)?.toInt() ?? 0));
          if (pages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories_outlined, size: 58, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 14),
                    Text(DateFormat('EEEE, d MMMM yyyy').format(_day),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('This notebook is empty. Add a page to record today’s plans, tasks and follow-ups.',
                      textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: () => _editPage(), icon: const Icon(Icons.add), label: const Text('Create first page')),
                  ],
                ),
              ),
            );
          }
          final index = _pageIndex.clamp(0, pages.length - 1).toInt();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(DateFormat('EEEE, d MMMM yyyy').format(_day),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    Text('PAGE ${index + 1} / ${pages.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.1)),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  itemCount: pages.length,
                  onPageChanged: (value) => setState(() => _pageIndex = value),
                  itemBuilder: (context, i) {
                    final doc = pages[i];
                    final data = doc.data();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.menu_book_rounded, color: Theme.of(context).colorScheme.primary),
                                const Spacer(),
                                IconButton(tooltip: 'Edit page', onPressed: () => _editPage(
                                  page: doc, pageNumber: (data['pageNumber'] as num?)?.toInt() ?? i + 1,
                                ), icon: const Icon(Icons.edit_outlined)),
                              ]),
                              const Divider(height: 24),
                              Text(data['title']?.toString() ?? 'Daily plan',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 18),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    data['body']?.toString() ?? '',
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65),
                                  ),
                                ),
                              ),
                              const Divider(height: 24),
                              Row(children: [
                                Text('SkyNest • Daily notebook',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => _editPage(page: doc, pageNumber: i + 1),
                                  icon: const Icon(Icons.edit_note_rounded),
                                  label: const Text('Edit notes'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 82),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: index == 0 ? null : () => setState(() => _pageIndex = index - 1),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                  const SizedBox(width: 24),
                  IconButton(onPressed: index >= pages.length - 1 ? null : () => setState(() => _pageIndex = index + 1),
                    icon: const Icon(Icons.arrow_forward_ios_rounded)),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
