import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local foreground notifications. Background delivery remains owned by FCM.
class SkyNestNotificationService {
  SkyNestNotificationService._();
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'skynest_messages_v2', 'SkyNest Messages',
    description: 'New messages and updates from SkyNest groups.',
    importance: Importance.max, playSound: true,
    sound: RawResourceAndroidNotificationSound('pop'),
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    _initialized = true;
  }

  static Future<void> showMessage({required String title, required String body, String? payload}) async {
    if (!_initialized) await initialize();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647), title, body,
      const NotificationDetails(android: AndroidNotificationDetails(
        'skynest_messages_v2', 'SkyNest Messages',
        channelDescription: 'New messages and updates from SkyNest groups.',
        importance: Importance.max, priority: Priority.high, playSound: true,
        sound: RawResourceAndroidNotificationSound('pop'),
      )),
      payload: payload,
    );
  }
}
