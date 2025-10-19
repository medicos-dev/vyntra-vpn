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

  /// Connect to VPN using VPNGate API with UDP/TCP fallback
  Future<bool> connect({String? country}) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';

      // Fetch servers from VPNGate API
      final servers = await VpnGateApiService.fetchVpnGateServers();
      if (servers.isEmpty) {
        _lastError = 'No VPN servers available. Please check your internet connection.';
        _set(VpnState.failed);
        return false;
      }

      // Get servers sorted by preference (UDP first, then TCP)
      List<VpnGateServer> preferredServers;
      if (country != null && country.isNotEmpty) {
        final countryServers = VpnGateApiService.getServersByCountry(servers, country);
        preferredServers = VpnGateApiService.getServersByPreference(countryServers);
      } else {
        preferredServers = VpnGateApiService.getServersByPreference(servers);
      }

      if (preferredServers.isEmpty) {
        _lastError = 'No suitable servers found for the selected criteria.';
        _set(VpnState.failed);
        return false;
      }

      // Try connecting to servers in order of preference
      for (int i = 0; i < preferredServers.length && i < 3; i++) {
        final server = preferredServers[i];
        _currentServer = server;
        
        print('🎯 Attempting server ${i + 1}: ${server.hostName} (${server.countryLong})');
        print('📊 Server stats: ${(server.speed / 1e6).toStringAsFixed(1)} Mbps, ${server.ping}ms');
        print('🔗 Protocol: ${server.hasUdpSupport ? 'UDP' : 'TCP'}');

        try {
          final success = await _attemptConnection(server);
          if (success) {
            print('✅ Connected successfully to ${server.hostName}');
            return true;
          }
        } catch (e) {
          print('❌ Failed to connect to ${server.hostName}: $e');
          if (i == preferredServers.length - 1) {
            _lastError = 'All connection attempts failed. Last error: $e';
          }
        }
      }

      _lastError = 'Unable to connect to any available server. Please try again.';
      _set(VpnState.failed);
      return false;
    } catch (e) {
      _lastError = 'Connection failed: $e';
      _set(VpnState.failed);
      _connectionTimeout?.cancel();
      return false;
    }
  }

  /// Attempt connection to a specific server
  Future<bool> _attemptConnection(VpnGateServer server) async {
    // Decode OpenVPN config
    final configData = server.openvpnConfigDataBase64;
    if (configData == null || configData.isEmpty) {
      throw Exception('No OpenVPN config available for this server');
    }

    final ovpnConfig = VpnGateApiService.decodeOpenVpnConfig(configData);
    if (ovpnConfig == null) {
      throw Exception('Failed to decode OpenVPN configuration');
    }

    // Apply OpenVPN3-compatible adjustments
    final adjustedConfig = _applyOpenVpn3Adjustments(ovpnConfig, server.ip);

    // Start connection timeout
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(const Duration(seconds: 30), () {
      if (state == VpnState.connecting) {
        _lastError = 'Connection timeout - server did not respond';
        _set(VpnState.failed);
      }
    });

    // Connect using OpenVPN Flutter
    await _engine!.connect(adjustedConfig, 'vpn');

    // Wait for connection confirmation
    await Future.delayed(const Duration(seconds: 2));
    
    if (state == VpnState.connected) {
      _connectionTimeout?.cancel();
      return true;
    } else if (state == VpnState.failed) {
      _connectionTimeout?.cancel();
      return false;
    }

    // If still connecting, wait a bit more
    await Future.delayed(const Duration(seconds: 3));
    return state == VpnState.connected;
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

    // Detect if this is a UDP or TCP config
    final isUdp = adjusted.contains('proto udp') || !adjusted.contains('proto tcp');
    
    // Add OpenVPN3-compatible flags
    final adjustments = [
      'pull-filter ignore "comp-lzo"',
      'setenv UV_PLAT android',
      'nobind',
      'persist-key',
      'persist-tun',
      'auth-nocache',
      'data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC',
      if (isUdp) 'proto udp' else 'proto tcp-client',
      'explicit-exit-notify 3',
      'verb 5',
    ];

    for (final adjustment in adjustments) {
      if (!adjusted.contains(adjustment.split(' ')[0])) {
        adjusted += '\n$adjustment';
      }
    }

    // Handle auth-user-pass properly
    if (adjusted.contains('#auth-user-pass')) {
      // Uncomment the auth-user-pass line
      adjusted = adjusted.replaceAll('#auth-user-pass', 'auth-user-pass');
    } else if (!adjusted.contains('auth-user-pass')) {
      // Add auth-user-pass if not present
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
        _lastError = 'Authentication failed - check server credentials';
        _set(VpnState.failed);
      } else if (stageStr.contains('timeout') || stageStr.contains('timed out')) {
        _lastError = 'Connection timeout - server did not respond';
        _set(VpnState.failed);
      } else if (stageStr.contains('no') || stageStr.contains('connection')) {
        _lastError = 'No network connection available';
        _set(VpnState.failed);
      } else if (stageStr.contains('device') || stageStr.contains('supported')) {
        _lastError = 'Device not supported for VPN connections';
        _set(VpnState.failed);
      } else if (stageStr.contains('permission') || stageStr.contains('denied')) {
        _lastError = 'VPN permission denied - please grant VPN access';
        _set(VpnState.failed);
      } else if (stageStr.contains('server') || stageStr.contains('unreachable')) {
        _lastError = 'Server unreachable - trying next server';
        _set(VpnState.failed);
      } else {
        print('Unknown VPN stage: $stage');
        _lastError = 'Connection error: $stage';
        _set(VpnState.failed);
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