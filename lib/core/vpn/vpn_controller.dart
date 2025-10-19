import 'dart:async';
import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/vpngate_api_service.dart';
import '../notify/notification_service.dart';
import 'session_manager.dart';

enum VpnState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class VpnController extends StateNotifier<VpnState> {
  VpnController() : super(VpnState.disconnected);

  // OpenVPN Flutter instance
  OpenVPN? _engine;
  bool _isInitialized = false;

  // Platform channels
  static const EventChannel _stageChannel = EventChannel('vpnStage');

  // State management
  StreamSubscription? _stageSub;
  String _lastError = '';
  VpnGateServer? _currentServer;
  Timer? _connectionTimeout;
  final SessionManager _sessionManager = SessionManager();

  // Getters
  VpnState get current => state;
  String get lastError => _lastError;
  VpnGateServer? get currentServer => _currentServer;
  SessionManager get sessionManager => _sessionManager;

  /// Initialize the VPN controller
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Initialize OpenVPN Flutter
      _engine = OpenVPN();
      await _engine!.initialize();
      
      // Listen to native stage channel
      _stageChannel.receiveBroadcastStream().listen(_handleNativeStage);
      
      _isInitialized = true;
      print('✅ VPN Controller initialized');
    } catch (e) {
      print('❌ VPN Controller initialization failed: $e');
      _lastError = 'Initialization failed: $e';
    }
  }

  /// Connect to VPN using VPNGate API
  Future<bool> connect({String? country}) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';

      // Fetch servers from VPNGate API
      final servers = await VpnGateApiService.fetchVpnGateServers();
      if (servers.isEmpty) {
        _lastError = 'No VPN servers available';
        _set(VpnState.failed);
        return false;
      }

      // Select the best server
      VpnGateServer? server;
      if (country != null && country.isNotEmpty) {
        final countryServers = VpnGateApiService.getServersByCountry(servers, country);
        server = VpnGateApiService.getBestServer(countryServers);
      }
      server ??= VpnGateApiService.getBestServer(servers);

      if (server == null) {
        _lastError = 'No suitable server found';
        _set(VpnState.failed);
        return false;
      }

      _currentServer = server;
      print('🎯 Selected server: ${server.hostName} (${server.countryLong})');
      print('📊 Server stats: ${(server.speed / 1e6).toStringAsFixed(1)} Mbps, ${server.ping}ms');

      // Decode OpenVPN config
      final configData = server.openvpnConfigDataBase64;
      if (configData == null || configData.isEmpty) {
        _lastError = 'No OpenVPN config available for this server';
        _set(VpnState.failed);
        return false;
      }

      final ovpnConfig = VpnGateApiService.decodeOpenVpnConfig(configData);
      if (ovpnConfig == null) {
        _lastError = 'Failed to decode OpenVPN configuration';
        _set(VpnState.failed);
        return false;
      }

      // Apply OpenVPN3-compatible adjustments
      final adjustedConfig = _applyOpenVpn3Adjustments(ovpnConfig, server.ip);

      // Start connection timeout
      _connectionTimeout = Timer(const Duration(seconds: 30), () {
        if (state == VpnState.connecting) {
          _lastError = 'Connection timeout';
          _set(VpnState.failed);
        }
      });

      // Connect using OpenVPN Flutter
      await _engine!.connect(adjustedConfig, 'vpn');

      return true;
    } catch (e) {
      _lastError = 'Connection failed: $e';
      _set(VpnState.failed);
      _connectionTimeout?.cancel();
      return false;
    }
  }

  /// Refresh VPN stage
  void refreshStage() {
    // Emit current state to listeners
    _set(state);
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    try {
      _connectionTimeout?.cancel();
      _engine?.disconnect();
      _set(VpnState.disconnected);
      await _sessionManager.endSession();
      NotificationService().showDisconnected();
      print('🔌 VPN disconnected');
    } catch (e) {
      print('❌ Disconnect error: $e');
    }
  }

  /// Apply OpenVPN3-compatible adjustments to config
  String _applyOpenVpn3Adjustments(String config, String serverIp) {
    String adjusted = config;

    // Add OpenVPN3-compatible flags
    final adjustments = [
      'pull-filter ignore "comp-lzo"',
      'setenv UV_PLAT android',
      'nobind',
      'persist-key',
      'persist-tun',
      'auth-nocache',
      'data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC',
      'proto tcp-client',
      'explicit-exit-notify 3',
      'verb 5',
    ];

    for (final adjustment in adjustments) {
      if (!adjusted.contains(adjustment.split(' ')[0])) {
        adjusted += '\n$adjustment';
      }
    }

    // Ensure auth-user-pass is present
    if (!adjusted.contains('auth-user-pass')) {
      adjusted += '\nauth-user-pass';
    }

    // Resolve hostname to IP if needed
    adjusted = _normalizeRemoteHostsToIp(adjusted, serverIp);

    return adjusted;
  }

  /// Normalize remote hosts to IP addresses
  String _normalizeRemoteHostsToIp(String config, String serverIp) {
    // Replace hostname with IP in remote lines
    final remoteRegex = RegExp(r'^remote\s+(\S+)\s+(\d+)', multiLine: true);
    return config.replaceAllMapped(remoteRegex, (match) {
      final port = match.group(2)!;
      return 'remote $serverIp $port';
    });
  }

  /// Handle native stage changes
  void _handleNativeStage(dynamic stage) {
    if (stage is String) {
      print('🔄 Native Stage: $stage');
      
      final stageStr = stage.toLowerCase();
      
      if (stageStr.contains('disconnected')) {
        _set(VpnState.disconnected);
      } else if (stageStr.contains('connecting') || stageStr.contains('wait')) {
        _set(VpnState.connecting);
      } else if (stageStr.contains('connected')) {
        _connectionTimeout?.cancel();
        _set(VpnState.connected);
        _sessionManager.startSession();
        NotificationService().showConnected(
          title: 'VPN Connected',
          body: 'Connected to ${_currentServer?.countryLong ?? 'Unknown'}',
        );
      } else if (stageStr.contains('reconnecting')) {
        _set(VpnState.reconnecting);
      } else if (stageStr.contains('auth') || stageStr.contains('failed')) {
        _lastError = 'Authentication failed';
        _set(VpnState.failed);
      } else if (stageStr.contains('no') || stageStr.contains('connection')) {
        _lastError = 'No connection';
        _set(VpnState.failed);
      } else if (stageStr.contains('device') || stageStr.contains('supported')) {
        _lastError = 'Device not supported';
        _set(VpnState.failed);
      } else {
        print('Unknown VPN stage: $stage');
      }
    }
  }

  /// Set VPN state
  void _set(VpnState newState) {
    if (state != newState) {
      state = newState;
      print('📱 VPN State: $newState');
    }
  }

  /// Dispose resources
  @override
  void dispose() {
    _stageSub?.cancel();
    _connectionTimeout?.cancel();
    _engine?.disconnect();
    super.dispose();
  }
}

// Provider for VPN Controller
final vpnControllerProvider = StateNotifierProvider<VpnController, VpnState>((ref) {
  return VpnController();
});