import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'vpn_controller.dart';

class ReconnectWatchdog {
  final VpnController controller;

  StreamSubscription? _connSub;
  StreamSubscription? _stateSub;
  Timer? _backoffTimer;
  int _attempt = 0;
  bool _isInitialized = false;

  ReconnectWatchdog({required this.controller});

  Future<void> start() async {
    _connSub = Connectivity().onConnectivityChanged.listen((_) async {
      if (_isInitialized && controller.current != VpnState.connected) {
        _scheduleReconnect();
      }
    });

    // Listen to VPN state changes
    _stateSub = controller.stream.listen((s) {
      if (_isInitialized && (s == VpnState.disconnected || s == VpnState.failed)) {
        _scheduleReconnect();
      } else if (s == VpnState.connected) {
        _resetBackoff();
      }
    });

    // Mark as initialized after a short delay to prevent auto-reconnect on startup
    Timer(const Duration(seconds: 3), () {
      _isInitialized = true;
    });
  }

  void _scheduleReconnect() {
    _backoffTimer?.cancel();
    final int seconds = _nextBackoffSeconds();
    _backoffTimer = Timer(Duration(seconds: seconds), () async {
      if (controller.current != VpnState.connected) {
        await controller.connect(); // No country parameter
      }
    });
  }

  int _nextBackoffSeconds() {
    _attempt = (_attempt + 1).clamp(1, 6);
    return [2, 4, 8, 12, 20, 30][_attempt - 1];
  }

  void _resetBackoff() {
    _attempt = 0;
    _backoffTimer?.cancel();
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    await _stateSub?.cancel();
    _backoffTimer?.cancel();
  }
}


