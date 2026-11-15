import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/control_centre/notification_centre.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('notification history is isolated by signed-in account', () async {
    await SkyNestNotificationStore.add(
      ownerId: 'account-a',
      title: 'Rent update',
      body: 'A payment was received.',
    );

    expect((await SkyNestNotificationStore.load('account-a')).length, 1);
    expect(await SkyNestNotificationStore.load('account-b'), isEmpty);
  });

  test('notifications can be saved, archived, moved to trash and restored', () async {
    await SkyNestNotificationStore.add(
      ownerId: 'account-a',
      title: 'New message',
      body: 'A tenant sent a message.',
    );
    var records = await SkyNestNotificationStore.load('account-a');
    final id = records.single.id;

    await SkyNestNotificationStore.updateStatus('account-a', {id}, 'saved');
    expect((await SkyNestNotificationStore.load('account-a')).single.status, 'saved');

    await SkyNestNotificationStore.updateStatus('account-a', {id}, 'archived');
    expect((await SkyNestNotificationStore.load('account-a')).single.status, 'archived');

    await SkyNestNotificationStore.updateStatus('account-a', {id}, 'trash');
    expect((await SkyNestNotificationStore.load('account-a')).single.status, 'trash');

    await SkyNestNotificationStore.updateStatus('account-a', {id}, 'inbox');
    records = await SkyNestNotificationStore.load('account-a');
    expect(records.single.status, 'inbox');
  });

  test('permanent deletion removes only selected notifications', () async {
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'One', body: 'First');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Two', body: 'Second');
    final records = await SkyNestNotificationStore.load('account-a');
    final firstId = records.firstWhere((item) => item.title == 'Two').id;
    await SkyNestNotificationStore.permanentlyDelete('account-a', {firstId});

    final remaining = await SkyNestNotificationStore.load('account-a');
    expect(remaining.map((item) => item.title), ['One']);
  });

  test('read state can be changed without changing folder placement', () async {
    await SkyNestNotificationStore.add(ownerId: 'account-a', title: 'Notice', body: 'Details');
    final id = (await SkyNestNotificationStore.load('account-a')).single.id;
    await SkyNestNotificationStore.markRead('account-a', {id}, true);
    final record = (await SkyNestNotificationStore.load('account-a')).single;
    expect(record.isRead, isTrue);
    expect(record.status, 'inbox');
  });
}
