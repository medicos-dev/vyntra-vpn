import 'dart:async';
import 'dart:io';
import 'dart:convert';
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

  /// Connect to VPN using VPNGate API with direct Base64 decoding
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

      // Filter by country if specified
      List<VpnGateServer> filteredServers = servers;
      if (country != null && country.isNotEmpty) {
        filteredServers = VpnGateApiService.getServersByCountry(servers, country);
      }

      if (filteredServers.isEmpty) {
        _lastError = 'No suitable servers found for the selected criteria.';
        _set(VpnState.failed);
        return false;
      }

      // Sort by Score (descending) and Ping (ascending) - CRITICAL FIX
      filteredServers.sort((a, b) {
        final scoreComparison = b.score.compareTo(a.score);
        if (scoreComparison != 0) return scoreComparison;
        return a.ping.compareTo(b.ping);
      });

      print('📊 Top 5 servers by score:');
      for (int i = 0; i < filteredServers.length && i < 5; i++) {
        final server = filteredServers[i];
        print('  ${i + 1}. ${server.hostName} - Score: ${server.score}, Ping: ${server.ping}ms, Country: ${server.countryLong}');
      }

      // Try connecting to the top 3 servers directly
      final topServers = filteredServers.take(3).toList();
      for (int i = 0; i < topServers.length; i++) {
        final server = topServers[i];
        _currentServer = server;
        
        print('🎯 Attempting server ${i + 1}: ${server.hostName} (Score: ${server.score}, Ping: ${server.ping}ms)');

        try {
          final success = await _attemptConnection(server);
          if (success) {
            print('✅ Connected successfully to ${server.hostName}');
            return true;
          }
        } catch (e) {
          print('❌ Failed to connect to ${server.hostName}: $e');
          if (i == topServers.length - 1) {
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
    // Check internet reachability before attempting connection
    final hasInternet = await _checkInternetReachability();
    if (!hasInternet) {
      throw Exception('No internet connection available - please check your network');
    }

    // Validate server has config
    if (server.openvpnConfigDataBase64 == null || server.openvpnConfigDataBase64!.isEmpty) {
      throw Exception('No OpenVPN config available for ${server.hostName}');
    }

    // Decode Base64 config directly
    String decodedConfig;
    try {
      final decodedBytes = base64.decode(server.openvpnConfigDataBase64!);
      decodedConfig = utf8.decode(decodedBytes);
      print('📄 Decoded config for ${server.hostName} (${decodedConfig.length} chars)');
    } catch (e) {
      throw Exception('Failed to decode Base64 config for ${server.hostName}: $e');
    }

    // Validate the decoded config
    if (!_isValidOvpnConfig(decodedConfig)) {
      throw Exception('Invalid OpenVPN config for ${server.hostName} - missing essential directives');
    }

    // Normalize the config
    final normalizedConfig = _normalizeOvpnConfig(decodedConfig);
    print('✅ Config normalized for ${server.hostName}');

    // Prepare config with mandatory UDP and credential modifications
    final preparedConfig = _prepareConfigFromString(normalizedConfig, server);

    // Start connection timeout
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(const Duration(seconds: 30), () {
      if (state == VpnState.connecting) {
        _lastError = 'Connection timeout - server did not respond';
        _engine?.disconnect(); // Clean up timed out connection
        _set(VpnState.failed);
      }
    });

    // Request VPN permission first
    final hasPermission = await _requestVpnPermission();
    if (!hasPermission) {
      throw Exception('VPN permission denied - please grant VPN access');
    }

    // Connect using OpenVPN Flutter with credentials
    await _engine!.connect(
      preparedConfig, // The prepared config with UDP and credentials
      'vpn', // name
      username: 'vpn', // CRITICAL: This must be passed
      password: 'vpn', // CRITICAL: This must be passed
    );

    // Wait for connection confirmation (single wait period)
    await Future.delayed(const Duration(seconds: 5));
    
    if (state == VpnState.connected) {
      _connectionTimeout?.cancel();
      return true;
    } else {
      // Connection failed or timed out
      _connectionTimeout?.cancel();
      _engine?.disconnect(); // Clean up failed connection
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


  /// Prepare OpenVPN config from string content
  String _prepareConfigFromString(String config, VpnGateServer server) {
    print('🔧 Original config protocol: ${RegExp(r'proto\s+\w+', caseSensitive: false).firstMatch(config)?.group(0) ?? 'none'}');

    // 2. FORCE UDP PROTOCOL - CRITICAL fix for stalling issue
    config = config.replaceAll(RegExp(r'proto\s+tcp', caseSensitive: false), 'proto udp');
    config = config.replaceAll(RegExp(r'proto\s+tcp-client', caseSensitive: false), 'proto udp');
    
    // Ensure proto udp is present
    if (!RegExp(r'proto\s+udp', caseSensitive: false).hasMatch(config)) {
      config += '\nproto udp';
    }
    print('✅ Forced UDP protocol');

    // 3. FORCE UDP PORT 1194 and ensure IP is used
    final originalRemote = RegExp(r'remote\s+[^\s]+\s+\d+', multiLine: true, caseSensitive: false).firstMatch(config)?.group(0);
    config = config.replaceAll(
      RegExp(r'remote\s+[^\s]+\s+\d+', multiLine: true, caseSensitive: false), 
      'remote ${server.ip} 1194'
    );
    print('✅ Remote line: $originalRemote → remote ${server.ip} 1194');

    // 4. Append OpenVPN's auth-user-pass directive
    if (!config.contains('auth-user-pass')) {
      config += '\nauth-user-pass';
      print('✅ Added auth-user-pass directive');
    } else {
      print('✅ auth-user-pass already present');
    }

    // 5. Clean up other known problem directives
    config = config.replaceAll(RegExp(r'^\s*auth-user-pass-verify\b', multiLine: true), '#auth-user-pass-verify');
    config = config.replaceAll(RegExp(r'^\s*pkcs12\b', multiLine: true), '#pkcs12');

    // 6. Apply additional OpenVPN3/Android fixes
    final finalConfig = _applyOpenVpn3Adjustments(config, server.ip);
    print('🔧 Final config prepared for ${server.hostName}');
    return finalConfig;
  }

  /// Apply OpenVPN3-compatible adjustments to config
  String _applyOpenVpn3Adjustments(String config, String serverIp) {
    String adjusted = config;

    // Add OpenVPN3/Android fixes and modern ciphers
    final adjustments = <String>[
      'pull-filter ignore "comp-lzo"',
      'pull-filter ignore "ip-win32"', // ignore Windows-only option
      'setenv UV_PLAT android',
      'nobind',
      'persist-key',
      'persist-tun',
      'auth-nocache',
      // Ensure modern ciphers are present (include CBC as fallback if server needs it)
      'data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC',
      'explicit-exit-notify 3',
      'verb 5',
    ];

    for (final line in adjustments) {
      final key = line.split(' ').first;
      if (!RegExp('^\\s*' + RegExp.escape(key) + r'\b', multiLine: true).hasMatch(adjusted)) {
        adjusted += '\n$line';
      }
    }

    return adjusted;
  }

  /// Validate OpenVPN configuration
  bool _isValidOvpnConfig(String config) {
    // Check for essential OpenVPN directives
    final hasRemote = config.contains('remote');
    final hasCa = config.contains('<ca>') && config.contains('</ca>');
    final hasProto = config.contains('proto');
    final hasDev = config.contains('dev tun') || config.contains('dev tap');
    
    return hasRemote && hasCa && hasProto && hasDev;
  }

  /// Normalize OpenVPN configuration
  String _normalizeOvpnConfig(String config) {
    // Normalize line endings (Windows \r\n → Unix \n)
    String normalized = config.replaceAll('\r\n', '\n');
    
    // Trim extra whitespace around XML blocks
    normalized = normalized.replaceAll(RegExp(r'\s*<ca>\s*'), '\n<ca>\n');
    normalized = normalized.replaceAll(RegExp(r'\s*</ca>\s*'), '\n</ca>\n');
    normalized = normalized.replaceAll(RegExp(r'\s*<cert>\s*'), '\n<cert>\n');
    normalized = normalized.replaceAll(RegExp(r'\s*</cert>\s*'), '\n</cert>\n');
    normalized = normalized.replaceAll(RegExp(r'\s*<key>\s*'), '\n<key>\n');
    normalized = normalized.replaceAll(RegExp(r'\s*</key>\s*'), '\n</key>\n');
    
    // Clean up multiple consecutive newlines
    normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    return normalized.trim();
  }

  /// Check internet reachability before attempting VPN connection
  Future<bool> _checkInternetReachability() async {
    try {
      // Quick ping to well-known DNS servers to verify internet access
      final dnsServers = ['8.8.8.8', '1.1.1.1', '208.67.222.222'];
      
      for (final dns in dnsServers) {
        try {
          final result = await InternetAddress.lookup(dns).timeout(
            const Duration(seconds: 3),
          );
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            print('✅ Internet reachability confirmed via $dns');
            return true;
          }
        } catch (e) {
          print('⚠️ DNS lookup failed for $dns: $e');
          continue;
        }
      }
      
      print('❌ No internet reachability detected');
      return false;
    } catch (e) {
      print('❌ Internet reachability check failed: $e');
      return false;
    }
  }

  /// Prepare for VPN connection (permission will be requested by plugin)
  Future<bool> _requestVpnPermission() async {
    try {
      // The openvpn_flutter plugin automatically requests VPN permission
      // when connect() is called. This method is a placeholder for future
      // pre-connection checks (e.g., Android 12+ background restrictions).
      // The plugin will show the system permission dialog if needed.
      return true;
    } catch (e) {
      print('❌ VPN preparation failed: $e');
      return false;
    }
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
      } else if (stageStr.contains('auth') || stageStr.contains('authentication') || stageStr.contains('credential')) {
        _lastError = 'Authentication failed - using vpn/vpn credentials';
        _set(VpnState.failed);
      } else if (stageStr.contains('timeout') || stageStr.contains('timed out')) {
        _lastError = 'Connection timeout - server did not respond';
        _set(VpnState.failed);
      } else if (stageStr.contains('no') && stageStr.contains('connection')) {
        _lastError = 'No network connection available';
        _set(VpnState.failed);
      } else if (stageStr.contains('device') || stageStr.contains('supported')) {
        _lastError = 'Device not supported for VPN connections';
        _set(VpnState.failed);
      } else if (stageStr.contains('permission') || stageStr.contains('denied') || stageStr.contains('unauthorized')) {
        _lastError = 'VPN permission denied - please grant VPN access in Android settings';
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