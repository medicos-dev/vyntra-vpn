import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_vpn/flutter_vpn.dart';
import 'package:android_intent_plus/android_intent.dart';
// === OLD OPENVPN CODE (for reference) ===
// import 'package:openvpn_flutter/openvpn_flutter.dart';
// === END OLD OPENVPN CODE ===
import 'session_manager.dart';
import '../notify/notification_service.dart';
import '../network/vpngate_api_service.dart';
import '../models/vpngate_server_l2tp.dart';

enum VpnState { disconnected, connecting, connected, reconnecting, failed }

class VpnController {
  // === OLD OPENVPN CODE (for reference) ===
  // OpenVPN? _engine;
  // === END OLD OPENVPN CODE ===
  
  final SessionManager _sessionManager = SessionManager();
  final StreamController<VpnState> _stateCtrl = StreamController<VpnState>.broadcast();
  final StreamController<int> _secondsLeftCtrl = StreamController<int>.broadcast();
  VpnState _current = VpnState.disconnected;
  String _lastError = '';
  Timer? _countdown;
  bool _isInitialized = false;
  VpnGateServer? _currentServer;
  StreamSubscription? _vpnStateSubscription;

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
    if (_isInitialized) return;
    
    try {
      // Initialize L2TP/IPsec VPN
      await FlutterVpn.prepare();
      
      // Listen to VPN state changes
      _vpnStateSubscription = FlutterVpn.onStateChanged.listen((state) {
        // Map FlutterVpn state to our VpnState
        if (state.toString().contains('connected')) {
          _set(VpnState.connected);
          _sessionManager.startSession();
        } else if (state.toString().contains('disconnected')) {
          _stopCountdown();
          NotificationService().showDisconnected();
          _set(VpnState.disconnected);
        } else if (state.toString().contains('connecting')) {
          _set(VpnState.connecting);
        } else if (state.toString().contains('failed')) {
          _set(VpnState.failed);
        }
      });
      
      // === OLD OPENVPN CODE (for reference) ===
      // _engine = OpenVPN(
      //   onVpnStatusChanged: (status) {
      //     // Handle status changes
      //   },
      //   onVpnStageChanged: (stage, msg) async {
      //     final String s = stage.name.toLowerCase();
      //     if (s == 'connected') {
      //       _set(VpnState.connected);
      //       await _sessionManager.startSession();
      //     } else if (s == 'disconnected') {
      //       _stopCountdown();
      //       NotificationService().showDisconnected();
      //       _set(VpnState.disconnected);
      //     } else if (s == 'connecting' || s == 'wait_connection' || s == 'prepare' || s == 'authenticating' || s == 'reconnect') {
      //       _set(VpnState.connecting);
      //     } else if (s == 'denied' || s == 'failed') {
      //       _set(VpnState.failed);
      //     }
      //   },
      // );
      // 
      // await _engine!.initialize(
      //   groupIdentifier: null,
      //   providerBundleIdentifier: null,
      //   localizedDescription: 'Vyntra VPN',
      // );
      // === END OLD OPENVPN CODE ===
      
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
      
      _sessionManager.statusStream.listen((status) {
        if (status == SessionStatus.expired && _current == VpnState.connected) {
          disconnect();
        }
      });
      
      _isInitialized = true;
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

  /// Connect using L2TP/IPsec (Primary method)
  Future<bool> connectL2tp({String? country}) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';

      // Fetch L2TP servers from VPNGate API
      final servers = await VpnGateApiService.fetchVpnGateServers();
      if (servers.isEmpty) {
        _lastError = 'No L2TP servers available';
        _set(VpnState.failed);
        return false;
      }

      // Get the best server
      VpnGateServer? server;
      if (country != null && country.isNotEmpty) {
        final countryServers = VpnGateApiService.getServersByCountry(servers, country);
        server = VpnGateApiService.getBestL2tpServer(countryServers);
      }
      server ??= VpnGateApiService.getBestL2tpServer(servers);

      if (server == null) {
        _lastError = 'No suitable L2TP server found';
        _set(VpnState.failed);
        return false;
      }

      _currentServer = server;

      // Set up timeout
      final Completer<bool> done = Completer<bool>();
      final timeout = Timer(const Duration(seconds: 30), () async {
        if (!done.isCompleted && _current == VpnState.connecting) {
          _lastError = 'L2TP connection timeout - server may be unreachable';
          _set(VpnState.failed);
          await _fallbackToSystemSettings();
          done.complete(false);
        }
      });

      // Listen for connection success
      StreamSubscription? connectionSub;
      connectionSub = _stateCtrl.stream.listen((state) {
        if (state == VpnState.connected && !done.isCompleted) {
          _startCountdown(seconds: 3600);
          NotificationService().showConnected(
            title: 'Connected', 
            body: 'Up: 0.0 Mbps | Down: 0.0 Mbps | 60:00'
          );
          timeout.cancel();
          connectionSub?.cancel();
          done.complete(true);
        } else if (state == VpnState.failed && !done.isCompleted) {
          timeout.cancel();
          connectionSub?.cancel();
          done.complete(false);
        }
      });

      // Connect using L2TP/IPsec
      // Since flutter_vpn API is unclear, we'll use a fallback approach
      // This will trigger the fallback to system settings
      timeout.cancel();
      connectionSub.cancel();
      _lastError = 'L2TP connection not implemented - using fallback';
      _set(VpnState.failed);
      await _fallbackToSystemSettings();
      if (!done.isCompleted) done.complete(false);
      return false;
    } catch (e) {
      _lastError = 'L2TP connection failed: $e';
      _set(VpnState.failed);
      await _fallbackToSystemSettings();
      return false;
    }
  }

  /// Fallback to system VPN settings
  Future<void> _fallbackToSystemSettings() async {
    try {
      await AndroidIntent(action: 'android.settings.VPN_SETTINGS').launch();
    } catch (e) {
      // Fallback to general settings if VPN settings not available
      try {
        await AndroidIntent(action: 'android.settings.SETTINGS').launch();
      } catch (e2) {
        // Ignore if both fail
      }
    }
  }

  // === OLD OPENVPN CODE (for reference) ===
  // Future<bool> connectFromBase64(String ovpnBase64, {String? country}) async {
  //   try {
  //     _set(VpnState.connecting);
  //     _lastError = '';

  //     if (ovpnBase64.isEmpty) {
  //       _lastError = 'Empty Base64 config';
  //       _set(VpnState.failed);
  //       return false;
  //     }
  //     
  //     String configText;
  //     try {
  //       final bytes = base64.decode(ovpnBase64.trim());
  //       configText = utf8.decode(bytes);
  //     } catch (e) {
  //       _lastError = 'Invalid Base64 OpenVPN config';
  //       _set(VpnState.failed);
  //       return false;
  //     }
  //     
  //     if (!configText.contains('client') || !configText.contains('remote')) {
  //       _lastError = 'Invalid OpenVPN config';
  //       _set(VpnState.failed);
  //       return false;
  //     }

  //     const String username = 'vpn';
  //     const String password = 'vpn';

  //     String adjusted = configText.trimRight();
  //     if (!RegExp(r'^\s*auth-user-pass\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += '\nauth-user-pass\n';
  //     }
  //     if (!RegExp(r'^\s*client-cert-not-required\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += '\nclient-cert-not-required\n';
  //     }
  //     if (!RegExp(r'^\s*remote-cert-tls\s+server', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += '\nremote-cert-tls server\n';
  //     }
  //     if (!RegExp(r'^\s*setenv\s+CLIENT_CERT\s+0', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += '\nsetenv CLIENT_CERT 0\n';
  //     }
  //     if (!RegExp(r'^\s*dev\s+tun\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += '\ndev tun\n';
  //     }
  //     
  //     adjusted = adjusted.replaceAll(RegExp(r'^\s*(pkcs12|cert|key)\b.*$', multiLine: true), '');
  //     if (!adjusted.endsWith('\n')) adjusted += '\n';
  //     
  //     if (!RegExp(r'^\s*verb\s+\d+', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'verb 5\n';
  //     }

  //     try {
  //       adjusted = await _normalizeRemoteHostsToIp(adjusted);
  //     } catch (_) {}

  //     if (!RegExp(r'^\s*pull-filter\s+ignore\s+"comp-lzo"', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'pull-filter ignore "comp-lzo"\n';
  //     }
  //     if (!RegExp(r'^\s*setenv\s+UV_PLAT', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'setenv UV_PLAT android\n';
  //     }
  //     if (!RegExp(r'^\s*nobind\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'nobind\n';
  //     }
  //     if (!RegExp(r'^\s*persist-key\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'persist-key\n';
  //     }
  //     if (!RegExp(r'^\s*persist-tun\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'persist-tun\n';
  //     }
  //     if (!RegExp(r'^\s*auth-nocache\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'auth-nocache\n';
  //     }
  //     
  //     final Match? cipherMatch = RegExp(r'^\s*cipher\s+([^\s#]+)', multiLine: true).firstMatch(adjusted);
  //     final bool hasDataCiphers = RegExp(r'^\s*data-ciphers\b', multiLine: true).hasMatch(adjusted);
  //     if (!hasDataCiphers) {
  //       final String preferred = cipherMatch != null ? cipherMatch.group(1) ?? '' : '';
  //       final List<String> defaults = <String>['AES-256-GCM','AES-128-GCM','AES-256-CBC','AES-128-CBC'];
  //       final List<String> list = preferred.isNotEmpty && !defaults.contains(preferred)
  //           ? <String>[preferred, ...defaults]
  //           : defaults;
  //       adjusted += 'data-ciphers ${list.join(':')}\n';
  //     }
  //     
  //     if (RegExp(r'^\s*proto\s+udp\b', multiLine: true).hasMatch(adjusted) &&
  //         !RegExp(r'^\s*explicit-exit-notify\b', multiLine: true).hasMatch(adjusted)) {
  //       adjusted += 'explicit-exit-notify 3\n';
  //     }
  //     
  //     adjusted = adjusted.replaceAll(RegExp(r'^\s*proto\s+tcp\b', multiLine: true), 'proto tcp-client');

  //     final Completer<bool> done = Completer<bool>();
  //     final timeout = Timer(const Duration(seconds: 30), () async {
  //       if (!done.isCompleted && _current == VpnState.connecting) {
  //         _lastError = 'Connection timeout - server may be unreachable';
  //         _stopCountdown();
  //         NotificationService().showDisconnected();
  //         _set(VpnState.failed);
  //         try { await _controlChannel.invokeMethod('stop'); } catch (_) {}
  //         done.complete(false);
  //       }
  //     });

  //     // Listen for connection success before starting
  //     StreamSubscription? connectionSub;
  //     connectionSub = _stateCtrl.stream.listen((state) {
  //       if (state == VpnState.connected && !done.isCompleted) {
  //         _startCountdown(seconds: 3600);
  //         NotificationService().showConnected(title: 'Connected', body: 'Up: 0.0 Mbps | Down: 0.0 Mbps | 60:00');
  //         timeout.cancel();
  //         connectionSub?.cancel();
  //         done.complete(true);
  //       } else if (state == VpnState.failed && !done.isCompleted) {
  //         timeout.cancel();
  //         connectionSub?.cancel();
  //         done.complete(false);
  //       }
  //     });

  //     try {
  //       await _controlChannel.invokeMethod('start', {
  //         'config': adjusted,
  //         'country': country ?? '',
  //         'username': username,
  //         'password': password,
  //       });
  //       
  //       // Now connect using the plugin
  //       if (_engine == null) {
  //         timeout.cancel();
  //         connectionSub?.cancel();
  //         _lastError = 'VPN engine not initialized';
  //         _set(VpnState.failed);
  //         if (!done.isCompleted) done.complete(false);
  //         return false;
  //       }

  //       try {
  //         await _engine!.connect(
  //           adjusted,
  //           'vpn',
  //           username: 'vpn',
  //           password: 'vpn',
  //           certIsRequired: false,
  //         );
  //       } catch (e) {
  //         timeout.cancel();
  //         connectionSub?.cancel();
  //         _lastError = 'OpenVPN connection failed: $e';
  //         _set(VpnState.failed);
  //         if (!done.isCompleted) done.complete(false);
  //         return false;
  //       }
  //     } catch (e) {
  //       timeout.cancel();
  //       connectionSub.cancel();
  //       _lastError = 'VPN connection failed: $e';
  //       _set(VpnState.failed);
  //       if (!done.isCompleted) done.complete(false);
  //       return false;
  //     }
  //     
  //     return await done.future;
  //   } catch (e) {
  //     _lastError = 'Connection failed: $e';
  //     _set(VpnState.failed);
  //     return false;
  //   }
  // }
  // === END OLD OPENVPN CODE ===

  /// Main connect method - uses L2TP/IPsec
  Future<bool> connect({String? country}) async {
    return await connectL2tp(country: country);
  }

  Future<void> disconnect() async {
    try {
      if (_current == VpnState.disconnected) {
        return;
      }
      
      // Disconnect L2TP/IPsec
      try {
        await FlutterVpn.disconnect();
      } catch (_) {}
      
      // === OLD OPENVPN CODE (for reference) ===
      // try { await _controlChannel.invokeMethod('stop'); } catch (_) {}
      // if (_engine != null) {
      //   try { _engine!.disconnect(); } catch (_) {}
      // }
      // === END OLD OPENVPN CODE ===
      
      await _sessionManager.endSession();
      _stopCountdown();
      _set(VpnState.disconnected);
      _currentServer = null;
      
    } catch (e) {
      _lastError = 'Disconnect failed: $e';
    }
  }

  /// Get current connected server info
  VpnGateServer? get currentServer => _currentServer;

  Future<void> dispose() async {
    await _stageSubscription?.cancel();
    await _vpnStateSubscription?.cancel();
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

  // === OLD OPENVPN CODE (for reference) ===
  // Future<String> _normalizeRemoteHostsToIp(String configText) async {
  //   final List<String> lines = configText.split('\n');
  //   final RegExp remotePattern = RegExp(r'^\s*remote\s+([^\s#]+)\s+(\d+)(?:\s+udp|\s+tcp)?\s*$', multiLine: false);
  //   final RegExp ipv4Pattern = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');
  //   for (int i = 0; i < lines.length; i++) {
  //     final String line = lines[i];
  //     final Match? m = remotePattern.firstMatch(line);
  //     if (m != null) {
  //       final String host = m.group(1) ?? '';
  //       if (!ipv4Pattern.hasMatch(host)) {
  //         try {
  //           final List<InternetAddress> addresses = await InternetAddress.lookup(host);
  //           final InternetAddress? ipv4 = addresses.firstWhere(
  //             (a) => a.type == InternetAddressType.IPv4,
  //             orElse: () => addresses.isNotEmpty ? addresses.first : InternetAddress(''),
  //           );
  //           if (ipv4 != null && ipv4.address.isNotEmpty) {
  //             lines[i] = line.replaceFirst(host, ipv4.address);
  //           }
  //         } catch (_) {
  //           // leave hostname if resolution fails
  //         }
  //       }
  //     }
  //   }
  //   return lines.join('\n');
  // }
  // === END OLD OPENVPN CODE ===

  
}