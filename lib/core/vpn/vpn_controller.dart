import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
// TODO: Add WireGuard/Shadowsocks plugins when finalized.
import 'session_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../notify/notification_service.dart';

enum VpnState { disconnected, connecting, connected, reconnecting, failed }

class VpnController {
  final OpenVPN _engine = OpenVPN();
  final SessionManager _sessionManager = SessionManager();
  final StreamController<VpnState> _stateCtrl = StreamController<VpnState>.broadcast();
  final StreamController<int> _secondsLeftCtrl = StreamController<int>.broadcast();
  VpnState _current = VpnState.disconnected;
  String _lastError = '';
  bool _sessionStarted = false;
  Timer? _countdown;

  // MethodChannel/EventChannel backend (matches reference VpnEngine)
  static const String _eventChannelVpnStage = 'vpnStage';
  static const String _methodChannelVpnControl = 'vpnControl';
  final EventChannel _stageChannel = const EventChannel(_eventChannelVpnStage);
  final MethodChannel _controlChannel = const MethodChannel(_methodChannelVpnControl);
  StreamSubscription? _stageSub;

  Stream<VpnState> get state => _stateCtrl.stream;
  VpnState get current => _current;
  String get lastError => _lastError;
  SessionManager get sessionManager => _sessionManager;
  Stream<int> get secondsLeft => _secondsLeftCtrl.stream;

  Future<void> init() async {
    try {
      print('🔧 Initializing VPN controller...');
      await _engine.initialize(
        groupIdentifier: null,
        providerBundleIdentifier: null,
        localizedDescription: 'Vyntra VPN',
      );
      await NotificationService().init();
      await _sessionManager.initialize();
      print('✅ VPN controller initialization complete');

      // Listen to session expiration
      _sessionManager.statusStream.listen((status) {
        if (status == SessionStatus.expired && _current == VpnState.connected) {
          disconnect();
        }
      });
    } catch (e) {
      _lastError = 'Failed to initialize VPN: $e';
      _set(VpnState.failed);
    }
  }

  void _startCountdown({int seconds = 3600}) {
    _countdown?.cancel();
    int left = seconds;
    _secondsLeftCtrl.add(left);
    _tickNotify(left, 0.0, 0.0);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      left -= 1;
      if (left <= 0) {
        _secondsLeftCtrl.add(0);
        _tickNotify(0, 0.0, 0.0);
        t.cancel();
        disconnect();
        return;
      }
      _secondsLeftCtrl.add(left);
      _tickNotify(left, 0.0, 0.0);
    });
  }

  void _stopCountdown() {
    _countdown?.cancel();
    _countdown = null;
    _secondsLeftCtrl.add(0);
  }

  void _tickNotify(int secondsLeft, double upMbps, double downMbps) {
    final String mm = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final String ss = (secondsLeft % 60).toString().padLeft(2, '0');
    NotificationService().updateStatus(
      title: 'Connected',
      body: 'Up: ${upMbps.toStringAsFixed(1)} Mbps | Down: ${downMbps.toStringAsFixed(1)} Mbps | $mm:$ss',
    );
  }

  void _set(VpnState s) {
    _current = s;
    _stateCtrl.add(s);
  }

  Future<bool> connectFromBase64(String ovpnBase64, {String? country}) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';
      print('🔌 Attempting VPN connection (base64)...');
      if (ovpnBase64.isEmpty) {
        _lastError = 'Empty Base64 config';
        _set(VpnState.failed);
        return false;
      }

      // Decode Base64 → String (use as-is, no mutation)
      String configText;
      try {
        final bytes = base64.decode(ovpnBase64.trim());
        configText = utf8.decode(bytes);
      } catch (e) {
        print('❌ Base64 decode failed: $e');
        _lastError = 'Invalid Base64 OpenVPN config';
        _set(VpnState.failed);
        return false;
      }

      if (!configText.contains('client') || !configText.contains('remote')) {
        _lastError = 'Invalid OpenVPN config';
        _set(VpnState.failed);
        return false;
      }

      // Always apply auth credentials vpn/vpn
      const String username = 'vpn';
      const String password = 'vpn';

      // Listen to stage updates
      await _stageSub?.cancel();
      _stageSub = _stageChannel.receiveBroadcastStream().cast<String>().listen((stage) {
        final s = stage.toLowerCase();
        if (s == 'connected') {
          if (_current != VpnState.connected) {
            print('🎉 VPN connected');
            _set(VpnState.connected);
            _sessionStarted = true;
            _startCountdown(seconds: 3600);
            NotificationService().showConnected(title: 'Connected', body: 'Up: 0.0 Mbps | Down: 0.0 Mbps | 60:00');
          }
        } else if (s == 'disconnected' || s == 'denied' || s == 'no_connection') {
          if (_current != VpnState.disconnected) {
            print('❌ VPN disconnected/failed: $s');
            _sessionStarted = false;
            _stopCountdown();
            NotificationService().showDisconnected();
            _set(VpnState.failed);
          }
        } else if (s == 'connecting' || s == 'prepare' || s == 'authenticating' || s == 'wait_connection' || s == 'reconnect') {
          _set(VpnState.connecting);
        }
      });

      // 45s timeout guard
      Timer(const Duration(seconds: 45), () async {
        if (_current == VpnState.connecting) {
          print('⏰ Connection timeout after 45 seconds');
          try { await _controlChannel.invokeMethod('stop'); } catch (_) {}
          _sessionStarted = false;
          _stopCountdown();
          NotificationService().showDisconnected();
          _set(VpnState.failed);
        }
      });

      // Start via MethodChannel (inline)
      await _controlChannel.invokeMethod('start', {
        'config': configText,
        'country': country ?? '',
        'username': username,
        'password': password,
      });

      print('⏳ Connection initiated from base64');
      return true;
    } catch (e) {
      _lastError = 'Connection failed: $e';
      _set(VpnState.failed);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_current == VpnState.disconnected) {
        _sessionStarted = false;
        return;
      }
      try {
        await _controlChannel.invokeMethod('stop');
      } catch (_) {}
      await _sessionManager.endSession();
      _sessionStarted = false;
      _stopCountdown();
      _set(VpnState.disconnected);
    } catch (e) {
      _lastError = 'Disconnect failed: $e';
    }
  }

  Future<void> dispose() async {
    await _stageSub?.cancel();
    _sessionManager.dispose();
    _stopCountdown();
    await _stateCtrl.close();
    await _secondsLeftCtrl.close();
  }
}