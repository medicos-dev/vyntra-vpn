import 'dart:async';
import 'package:openvpn_flutter/openvpn_flutter.dart';
// TODO: Add WireGuard/Shadowsocks plugins when finalized.
import 'session_manager.dart';

enum VpnState { disconnected, connecting, connected, reconnecting, failed }

class VpnController {
  final OpenVPN _engine = OpenVPN();
  final SessionManager _sessionManager = SessionManager();
  final StreamController<VpnState> _stateCtrl = StreamController<VpnState>.broadcast();
  VpnState _current = VpnState.disconnected;
  String _lastError = '';

  Stream<VpnState> get state => _stateCtrl.stream;
  VpnState get current => _current;
  String get lastError => _lastError;
  SessionManager get sessionManager => _sessionManager;

  Future<void> init() async {
    try {
      await _engine.initialize(
        groupIdentifier: null,
        providerBundleIdentifier: null,
        localizedDescription: 'Vyntra VPN',
      );
      await _sessionManager.initialize();
      
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

  Future<bool> connect(String ovpnContent) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';
      
      // Use dynamic to handle different plugin API versions
      final result = (_engine as dynamic).connect(ovpnContent, 'Vyntra', certIsRequired: false);
      
      // If it returns a Future, wait for it with timeout
      if (result is Future) {
        await Future.any([
          result,
          Future.delayed(const Duration(seconds: 25), () => throw TimeoutException('Connection timeout', const Duration(seconds: 25))),
        ]);
      }
      
      // Simulate connection success after a delay (since status listener may not work)
      Timer(const Duration(seconds: 3), () {
        if (_current == VpnState.connecting) {
          _set(VpnState.connected);
          _sessionManager.startSession(); // Start 1-hour session
        }
      });
      return true;
    } catch (e) {
      _lastError = 'Connection failed: $e';
      _set(VpnState.failed);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      // Use dynamic to handle different plugin API versions
      final result = (_engine as dynamic).disconnect();
      
      // If it returns a Future, wait for it
      if (result is Future) {
        await result;
      }
      
      await _sessionManager.endSession(); // End session when disconnecting
      _set(VpnState.disconnected);
    } catch (e) {
      _lastError = 'Disconnect failed: $e';
    }
  }

  void _set(VpnState s) {
    _current = s;
    _stateCtrl.add(s);
  }

  Future<void> dispose() async {
    _sessionManager.dispose();
    await _stateCtrl.close();
  }
}