import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'session_manager.dart';
import '../notify/notification_service.dart';

enum VpnState { disconnected, connecting, connected, reconnecting, failed }

class VpnController {
  late final OpenVPN _engine;
  final SessionManager _sessionManager = SessionManager();
  final StreamController<VpnState> _stateCtrl = StreamController<VpnState>.broadcast();
  final StreamController<int> _secondsLeftCtrl = StreamController<int>.broadcast();
  VpnState _current = VpnState.disconnected;
  String _lastError = '';
  // Tracks session lifecycle via SessionManager only
  Timer? _countdown;

  // Reference-aligned native channels
  static const String _eventChannelVpnStage = 'vpnStage';
  static const String _methodChannelVpnControl = 'vpnControl';
  final EventChannel _stageChannel = const EventChannel(_eventChannelVpnStage);
  final MethodChannel _controlChannel = const MethodChannel(_methodChannelVpnControl);
  StreamSubscription? _stageSubscription;

  Stream<VpnState> get state => _stateCtrl.stream;
  VpnState get current => _current;
  String get lastError => _lastError;
  SessionManager get sessionManager => _sessionManager;
  Stream<int> get secondsLeft => _secondsLeftCtrl.stream;

  Future<void> init() async {
    try {
      print('🔧 Initializing VPN controller (channel-based)...');
      // Create engine with stage handler that updates our state
      _engine = OpenVPN(
        onVpnStatusChanged: (status) {},
        onVpnStageChanged: (stage, msg) async {
          final String s = stage.name.toLowerCase();
          if (s == 'connected') {
            _set(VpnState.connected);
            await _sessionManager.startSession();
          } else if (s == 'disconnected') {
            _stopCountdown();
            NotificationService().showDisconnected();
            _set(VpnState.disconnected);
          } else if (s == 'connecting' || s == 'wait_connection' || s == 'prepare' || s == 'authenticating' || s == 'reconnect') {
            _set(VpnState.connecting);
          }
        },
      );
      // Initialize plugin engine
      await _engine.initialize(
        groupIdentifier: null,
        providerBundleIdentifier: null,
        localizedDescription: 'Vyntra VPN',
      );
      // Stage mapping via native channel below; plugin mapping above ensures fallback
      _stageSubscription?.cancel();
      _stageSubscription = _stageChannel.receiveBroadcastStream().cast<String>().listen((stage) async {
        final String s = (stage).toLowerCase();
        if (s == 'connected') {
          _set(VpnState.connected);
          await _sessionManager.startSession();
        } else if (s == 'disconnected') {
          _stopCountdown();
          NotificationService().showDisconnected();
          _set(VpnState.disconnected);
        } else if (s == 'connecting' || s == 'wait_connection') {
          _set(VpnState.connecting);
        }
      });
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

      // Replace DDNS hostnames with resolved IPv4 to bypass censorship/DNS blocks
      try {
        adjusted = await _normalizeRemoteHostsToIp(adjusted);
      } catch (_) {}

      // Force UDP if server supports both and avoid compression issues
      if (!RegExp(r'^\s*proto\s+', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\nproto udp\n';
      }
      // Avoid server-pushed compression causing stalls on some networks
      if (!RegExp(r'^\s*pull-filter\s+ignore\s+"comp-lzo"', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'pull-filter ignore "comp-lzo"\n';
      }
      if (!RegExp(r'^\s*setenv\s+UV_PLAT', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'setenv UV_PLAT android\n';
      }
      // Ensure stability flags commonly required on Android
      if (!RegExp(r'^\s*nobind\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'nobind\n';
      }
      if (!RegExp(r'^\s*persist-key\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'persist-key\n';
      }
      if (!RegExp(r'^\s*persist-tun\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'persist-tun\n';
      }
      if (!RegExp(r'^\s*auth-nocache\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'auth-nocache\n';
      }
      // OpenVPN3 prefers data-ciphers; map legacy cipher to data-ciphers if needed
      final Match? cipherMatch = RegExp(r'^\s*cipher\s+([^\s#]+)', multiLine: true).firstMatch(adjusted);
      final bool hasDataCiphers = RegExp(r'^\s*data-ciphers\b', multiLine: true).hasMatch(adjusted);
      if (!hasDataCiphers) {
        final String preferred = cipherMatch != null ? cipherMatch.group(1) ?? '' : '';
        final List<String> defaults = <String>['AES-256-GCM','AES-128-GCM','AES-256-CBC','AES-128-CBC'];
        final List<String> list = preferred.isNotEmpty && !defaults.contains(preferred)
            ? <String>[preferred, ...defaults]
            : defaults;
        adjusted += 'data-ciphers ${list.join(':')}\n';
      }
      // For UDP, explicit-exit-notify improves teardown; harmless on server ignoring
      if (RegExp(r'^\s*proto\s+udp\b', multiLine: true).hasMatch(adjusted) &&
          !RegExp(r'^\s*explicit-exit-notify\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += 'explicit-exit-notify 3\n';
      }
      // Normalize tcp proto to tcp-client if needed
      adjusted = adjusted.replaceAll(RegExp(r'^\s*proto\s+tcp\b', multiLine: true), 'proto tcp-client');

      // 45s timeout guard
      final Completer<bool> done = Completer<bool>();
      final timeout = Timer(const Duration(seconds: 45), () async {
        if (!done.isCompleted && _current == VpnState.connecting) {
          print('⏰ Connection timeout after 45 seconds');
          _lastError = 'Connection timeout - server may be unreachable';
          _stopCountdown();
          NotificationService().showDisconnected();
          _set(VpnState.failed);
          try { await _controlChannel.invokeMethod('stop'); } catch (_) {}
          
          done.complete(false);
        }
      });

      // Try native control channel first, but do not fail if missing
      try {
        await _controlChannel.invokeMethod('start', {
          'config': adjusted,
          'country': country ?? '',
          'username': username,
          'password': password,
        });
        print('📊 Connection start invoked via control channel');
      } catch (_) {
        // MissingPlugin or unimplemented: fall back to plugin connect
        print('ℹ️ vpnControl.start not available, falling back to plugin connect');
      }

      // Ensure connection via OpenVPN Flutter plugin as a reliable fallback
      try {
        await _engine.connect(
          adjusted,
          'Vyntra',
          username: username,
          password: password,
          certIsRequired: false,
        );
        print('📊 Plugin connect invoked');
      } catch (e) {
        timeout.cancel();
        print('❌ Plugin connect failed: $e');
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
      try { await _controlChannel.invokeMethod('stop'); } catch (_) {}
      try { _engine.disconnect(); } catch (_) {}
      await _sessionManager.endSession();
      _stopCountdown();
      _set(VpnState.disconnected);
      
    } catch (e) {
      _lastError = 'Disconnect failed: $e';
      
    }
  }

  Future<void> dispose() async {
    await _stageSubscription?.cancel();
    _sessionManager.dispose();
    _stopCountdown();
    await _stateCtrl.close();
    await _secondsLeftCtrl.close();
  }

  Future<void> openKillSwitch() async {
    try {
      await _controlChannel.invokeMethod('kill_switch');
    } catch (_) {}
  }

  Future<void> refreshStage() async {
    try {
      await _controlChannel.invokeMethod('refresh');
    } catch (_) {}
  }

  Future<String> _normalizeRemoteHostsToIp(String configText) async {
    final List<String> lines = configText.split('\n');
    final RegExp remotePattern = RegExp(r'^\s*remote\s+([^\s#]+)\s+(\d+)(?:\s+udp|\s+tcp)?\s*$', multiLine: false);
    final RegExp ipv4Pattern = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final Match? m = remotePattern.firstMatch(line);
      if (m != null) {
        final String host = m.group(1) ?? '';
        if (!ipv4Pattern.hasMatch(host)) {
          try {
            final List<InternetAddress> addresses = await InternetAddress.lookup(host);
            final InternetAddress? ipv4 = addresses.firstWhere(
              (a) => a.type == InternetAddressType.IPv4,
              orElse: () => addresses.isNotEmpty ? addresses.first : InternetAddress(''),
            );
            if (ipv4 != null && ipv4.address.isNotEmpty) {
              lines[i] = line.replaceFirst(host, ipv4.address);
            }
          } catch (_) {
            // leave hostname if resolution fails
          }
        }
      }
    }
    return lines.join('\n');
  }

  
}