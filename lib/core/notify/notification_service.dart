import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _i = NotificationService._();
  NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const String _channelId = 'vyntra_vpn_status';

  Future<void> init() async {
    // Request notification permission for Android 13+
    await _requestNotificationPermission();
    
    const AndroidInitializationSettings android = AndroidInitializationSettings('ic_notification');
    const InitializationSettings init = InitializationSettings(android: android);
    await _plugin.initialize(init,
      onDidReceiveNotificationResponse: (resp) async {
        print('🔔 Notification response: ${resp.actionId}, payload: ${resp.payload}');
        if (resp.payload == 'disconnect' || resp.actionId == 'disconnect') {
          // Use the platform channel to emit disconnected stage
          const platform = MethodChannel('vyntra.vpn.actions');
          try { 
            await platform.invokeMethod('disconnect');
            print('✅ Disconnect stage emitted from notification');
            
            // Bring app to foreground after disconnect
            await platform.invokeMethod('bringToForeground');
            print('✅ App brought to foreground');
          } catch (e) {
            print('❌ Failed to emit disconnect stage from notification: $e');
          }
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

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
        print('🔔 Notification permission requested');
      }
    } catch (e) {
      print('❌ Failed to request notification permission: $e');
    }
  }

  Future<void> showConnected({required String title, required String body, String? uploadSpeed, String? downloadSpeed}) async {
    try {
      // Create enhanced body with traffic stats
      String enhancedBody = body;
      if (uploadSpeed != null && downloadSpeed != null) {
        enhancedBody += '\n📊 ↑ $uploadSpeed ↓ $downloadSpeed';
      }
      
      final AndroidNotificationDetails android = AndroidNotificationDetails(
        _channelId,
        'VPN Status',
        channelDescription: 'Shows the current VPN connection status',
        ongoing: true,
        onlyAlertOnce: false, // Allow alerts for each connection
        importance: Importance.high, // Make it more visible
        priority: Priority.high,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('disconnect', 'Disconnect', showsUserInterface: false, cancelNotification: false)
        ],
        styleInformation: BigTextStyleInformation(enhancedBody),
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
      );
      await _plugin.show(1, title, enhancedBody, NotificationDetails(android: android), payload: '');
      print('✅ Single notification shown successfully: $title - $enhancedBody');
    } catch (e) {
      print('❌ Failed to show notification: $e');
    }
  }

  Future<void> updateConnectedNotification({
    required String title,
    required String body,
    String? uploadSpeed,
    String? downloadSpeed,
    String? sessionTime,
  }) async {
    // Use the main showConnected method to maintain single notification
    await showConnected(
      title: title,
      body: body,
      uploadSpeed: uploadSpeed,
      downloadSpeed: downloadSpeed,
    );
  }

  Future<void> showDisconnected() async {
    await _plugin.cancel(1);
  }

  Future<void> updateStatus({required String title, required String body}) async {
    await showConnected(title: title, body: body);
  }
}
