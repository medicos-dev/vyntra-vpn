import 'dart:async';
import 'dart:convert';
// import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
// TODO: Add WireGuard/Shadowsocks plugins when finalized.
import 'session_manager.dart';
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
import '../notify/notification_service.dart';

enum VpnState { disconnected, connecting, connected, reconnecting, failed }

class VpnController {
  final OpenVPN _engine = OpenVPN(
    onVpnStatusChanged: (status) {},
    onVpnStageChanged: (stage, msg) async {},
  );
  final SessionManager _sessionManager = SessionManager();
  final StreamController<VpnState> _stateCtrl = StreamController<VpnState>.broadcast();
  final StreamController<int> _secondsLeftCtrl = StreamController<int>.broadcast();
  VpnState _current = VpnState.disconnected;
  String _lastError = '';
  // Tracks session lifecycle via SessionManager only
  Timer? _countdown;

  // Stage callback is registered via OpenVPN constructor

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
      // Recreate engine with stage handler to update state
      OpenVPN(
        onVpnStatusChanged: (status) {},
        onVpnStageChanged: (stage, msg) async {
          // stage change received
          try {
            if (stage == VPNStage.connected) {
              _set(VpnState.connected);
              await _sessionManager.startSession();
            } else if (stage == VPNStage.disconnected) {
              _stopCountdown();
              NotificationService().showDisconnected();
              _set(VpnState.disconnected);
            } else if (stage == VPNStage.connecting) {
              _set(VpnState.connecting);
            } else {
              // Treat other stages as transitional; do not touch error here
            }
          } catch (_) {}
        },
      );
      // Handler attached via constructor above
      await NotificationService().init();
      await _sessionManager.initialize();
      print('✅ VPN controller initialization complete');
      
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

      const String username = 'vpn';
      const String password = 'vpn';

      // Minimal adjustments only if missing
      String adjusted = configText.trimRight();
      if (!RegExp(r'^\s*auth-user-pass\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\nauth-user-pass\n';
      }
      if (!RegExp(r'^\s*client-cert-not-required\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\nclient-cert-not-required\n';
      }
      if (!RegExp(r'^\s*remote-cert-tls\s+server', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\nremote-cert-tls server\n';
      }
      if (!RegExp(r'^\s*setenv\s+CLIENT_CERT\s+0', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\nsetenv CLIENT_CERT 0\n';
      }
      if (!RegExp(r'^\s*dev\s+tun\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\ndev tun\n';
      }
      // Strip client-certificate lines to avoid prompts
      adjusted = adjusted.replaceAll(RegExp(r'^\s*(pkcs12|cert|key)\b.*$', multiLine: true), '');
      if (!adjusted.endsWith('\n')) adjusted += '\n';

      // 45s timeout guard
      final Completer<bool> done = Completer<bool>();
      final timeout = Timer(const Duration(seconds: 45), () async {
        if (!done.isCompleted && _current == VpnState.connecting) {
          print('⏰ Connection timeout after 45 seconds');
          _lastError = 'Connection timeout - server may be unreachable';
          _stopCountdown();
          NotificationService().showDisconnected();
          _set(VpnState.failed);
          try { _engine.disconnect(); } catch (_) {}
          
          done.complete(false);
        }
      });

      try {
        // Connect using OpenVPN Flutter API
        _engine.connect(
          adjusted,
          'Vyntra',
          username: username,
          password: password,
          certIsRequired: false,
        );
        print('📊 Connection start invoked via plugin channel');
        
      } catch (e) {
        timeout.cancel();
        print('❌ Connect failed: $e');
        
        _lastError = 'Connect failed: $e';
        _set(VpnState.failed);
        if (!done.isCompleted) done.complete(false);
        return false;
      }

      _startCountdown(seconds: 3600);
      NotificationService().showConnected(title: 'Connected', body: 'Up: 0.0 Mbps | Down: 0.0 Mbps | 60:00');
      if (!done.isCompleted) done.complete(true);
      timeout.cancel();
      print('⏳ Connection initiated from base64');
      
      return await done.future;
    } catch (e) {
      _lastError = 'Connection failed: $e';
      
      _set(VpnState.failed);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_current == VpnState.disconnected) {
        return;
      }
      try {
        _engine.disconnect();
      } catch (_) {}
      await _sessionManager.endSession();
      _stopCountdown();
      _set(VpnState.disconnected);
      
    } catch (e) {
      _lastError = 'Disconnect failed: $e';
      
    }
  }

  Future<void> dispose() async {
    // No stream subscriptions to cancel; callbacks are GC'd with instance
    _sessionManager.dispose();
    _stopCountdown();
    await _stateCtrl.close();
    await _secondsLeftCtrl.close();
  }

  
}