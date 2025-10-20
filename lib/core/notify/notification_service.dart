import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static final NotificationService _i = NotificationService._();
  NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'vyntra_vpn_status';

  Future<void> init() async {
    const AndroidInitializationSettings android = AndroidInitializationSettings('ic_notification');
    const InitializationSettings init = InitializationSettings(android: android);
    await _plugin.initialize(init,
      onDidReceiveNotificationResponse: (resp) async {
        if (resp.payload == 'disconnect' || resp.actionId == 'disconnect') {
          const platform = MethodChannel('vyntra.vpn.actions');
          try { await platform.invokeMethod('disconnect'); } catch (_) {}
        }
      }
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      'VPN Status',
      description: 'Shows the current VPN connection status',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  Future<void> showConnected({required String title, required String body}) async {
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      _channelId,
      'VPN Status',
      channelDescription: 'Shows the current VPN connection status',
      ongoing: true,
      onlyAlertOnce: true,
      importance: Importance.low,
      priority: Priority.low,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('disconnect', 'Disconnect', showsUserInterface: false, cancelNotification: false)
      ],
      styleInformation: const BigTextStyleInformation(''),
    );
    await _plugin.show(1, title, body, NotificationDetails(android: android), payload: '');
  }

  Future<void> updateConnectedNotification({
    required String title,
    required String body,
    String? uploadSpeed,
    String? downloadSpeed,
    String? sessionTime,
  }) async {
    String notificationBody = body;
    if (uploadSpeed != null && downloadSpeed != null) {
      notificationBody += '\n📊 ↑ $uploadSpeed ↓ $downloadSpeed';
    }
    if (sessionTime != null) {
      notificationBody += '\n⏱️ $sessionTime';
    }

    final AndroidNotificationDetails android = AndroidNotificationDetails(
      _channelId,
      'VPN Status',
      channelDescription: 'Shows the current VPN connection status',
      ongoing: true,
      onlyAlertOnce: true,
      importance: Importance.low,
      priority: Priority.low,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('disconnect', 'Disconnect', showsUserInterface: false, cancelNotification: false)
      ],
      styleInformation: BigTextStyleInformation(notificationBody),
    );
    await _plugin.show(1, title, notificationBody, NotificationDetails(android: android), payload: '');
  }

  Future<void> showDisconnected() async {
    await _plugin.cancel(1);
  }

  Future<void> updateStatus({required String title, required String body}) async {
    await showConnected(title: title, body: body);
  }
}
