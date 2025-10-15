import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'vpn_controller.dart';

class ReconnectWatchdog {
  final VpnController controller;
  final Future<String?> Function() currentProfileProvider;

  StreamSubscription? _connSub;
  Timer? _backoffTimer;
  int _attempt = 0;

  ReconnectWatchdog({required this.controller, required this.currentProfileProvider});

  Future<void> start() async {
    _connSub = Connectivity().onConnectivityChanged.listen((_) async {
      // On any connectivity change, if not connected, try to reconnect with backoff
      if (controller.current != VpnState.connected) {
        _scheduleReconnect();
      }
    });

    controller.state.listen((s) {
      if (s == VpnState.disconnected || s == VpnState.failed) {
        _scheduleReconnect();
      } else if (s == VpnState.connected) {
        _resetBackoff();
      }
    });
  }

  void _scheduleReconnect() {
    _backoffTimer?.cancel();
    final int seconds = _nextBackoffSeconds();
    _backoffTimer = Timer(Duration(seconds: seconds), () async {
      final String? profile = await currentProfileProvider();
      if (profile != null && controller.current != VpnState.connected) {
        await controller.connect(profile);
      }
    });
  }

  int _nextBackoffSeconds() {
    _attempt = (_attempt + 1).clamp(1, 6); // cap backoff
    return [2, 4, 8, 12, 20, 30][_attempt - 1];
  }

  void _resetBackoff() {
    _attempt = 0;
    _backoffTimer?.cancel();
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _backoffTimer?.cancel();
  }
}


