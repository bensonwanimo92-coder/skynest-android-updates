import 'package:chuka/control_centre/control_centre_screen.dart';
import '../lib/control_centre/notification_centre.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('Control Centre saves visible modules and their order', (tester) async {
    List<String>? savedOrder;
    Set<String>? savedHidden;

    await tester.pumpWidget(MaterialApp(
      home: ControlCentreScreen(
        moduleTitles: const ['Houses', 'Payments', 'Reports'],
        initialOrder: const ['Payments', 'Houses', 'Reports'],
        initialHidden: const {'Reports'},
        onSave: (order, hidden) async {
          savedOrder = List<String>.from(order);
          savedHidden = Set<String>.from(hidden);
        },
        onOpenNotifications: () {},
        onOpenActivityLog: () {},
        onOpenAutomations: () {},
        onOpenBackup: () {},
        onOpenGlobalSearch: () {},
        onOpenRecycleBin: () {},
      ),
    ));

    expect(find.text('SkyNest Control Centre'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Save dashboard layout'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save dashboard layout'));
    await tester.pumpAndSettle();

    expect(savedOrder, ['Payments', 'Houses', 'Reports']);
    expect(savedHidden, {'Reports'});
    expect(find.byType(ControlCentreScreen), findsNothing);
  });

  testWidgets('Control Centre quick access opens notification management', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: ControlCentreScreen(
        moduleTitles: const ['Houses'],
        initialOrder: const [],
        initialHidden: const {},
        onSave: (_, __) async {},
        onOpenNotifications: () => opened = true,
        onOpenActivityLog: () {},
        onOpenAutomations: () {},
        onOpenBackup: () {},
        onOpenGlobalSearch: () {},
        onOpenRecycleBin: () {},
      ),
    ));

    await tester.tap(find.text('Notification centre'));
    expect(opened, isTrue);
  }); 
  test('clearing the inbox moves only inbox items to Trash', () async {
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Inbox item', body: 'Move me');
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Saved item', body: 'Keep me');
    final records = await SkyNestNotificationStore.load('account-a');
    final savedId = records.firstWhere((item) => item.title == 'Saved item').id;
    await SkyNestNotificationStore.updateStatus('account-a', {savedId}, 'saved');

    await SkyNestNotificationStore.moveFolderToTrash('account-a', 'inbox');
    final updated = await SkyNestNotificationStore.load('account-a');
    expect(updated.firstWhere((item) => item.title == 'Inbox item').status, 'trash');
    expect(updated.firstWhere((item) => item.title == 'Saved item').status, 'saved');
  });

  test('emptying Trash permanently removes only trashed notifications', () async {
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Trash item', body: 'Delete me');
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Inbox item', body: 'Keep me');
    final records = await SkyNestNotificationStore.load('account-a');
    final trashId = records.firstWhere((item) => item.title == 'Trash item').id;
    await SkyNestNotificationStore.updateStatus('account-a', {trashId}, 'trash');

    await SkyNestNotificationStore.emptyTrash('account-a');
    final remaining = await SkyNestNotificationStore.load('account-a');
    expect(remaining.map((item) => item.title), ['Inbox item']);
  });

}
