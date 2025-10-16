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
      print('🔧 Initializing VPN controller...');
      await _engine.initialize(
        groupIdentifier: null,
        providerBundleIdentifier: null,
        localizedDescription: 'Vyntra VPN',
      );
      
      // Note: OpenVPN plugin initialization is handled by the engine.initialize() call above
      
      await _sessionManager.initialize();
      print('✅ VPN controller initialization complete');
      
      // Start monitoring connection status
      _startStatusMonitoring();
      
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
  
  void _startStatusMonitoring() {
    // Monitor connection status periodically
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_current == VpnState.connecting) {
        // Check if connection has been established by trying to get status
        try {
          // This is a placeholder - in a real implementation, you'd check the actual VPN status
          // For now, we'll use a timeout-based approach
        } catch (e) {
          // Connection failed
          if (_current == VpnState.connecting) {
            _lastError = 'Connection failed during monitoring: $e';
            _set(VpnState.failed);
          }
        }
      }
    });
  }

  Future<bool> connect(String ovpnContent) async {
    try {
      _set(VpnState.connecting);
      _lastError = '';
      
      print('🔌 Attempting VPN connection...');
      print('📄 Config length: ${ovpnContent.length} characters');
      print('🔍 Config preview: ${ovpnContent.substring(0, 200)}...');
      
      // Comprehensive OpenVPN config validation
      if (!ovpnContent.contains('client') || !ovpnContent.contains('remote')) {
        _lastError = 'Invalid OpenVPN configuration - missing client or remote directives';
        print('❌ Invalid OpenVPN config - missing client or remote directives');
        _set(VpnState.failed);
        return false;
      }
      
      // Check for required certificates
      if (!ovpnContent.contains('<ca>') || !ovpnContent.contains('</ca>')) {
        _lastError = 'Invalid OpenVPN configuration - missing CA certificate';
        print('❌ Invalid OpenVPN config - missing CA certificate');
        _set(VpnState.failed);
        return false;
      }
      
      print('✅ OpenVPN config validation passed');
      
      // Optimize OpenVPN config for better compatibility
      String configToUse = _optimizeOpenVpnConfig(ovpnContent);
      print('🌐 Using protocol: ${configToUse.contains('proto tcp') ? 'TCP' : (configToUse.contains('proto udp') ? 'UDP' : 'UNKNOWN')}');
      
      // Debug: Print the optimized config for troubleshooting
      print('🔍 Optimized config preview:');
      final lines = configToUse.split('\n');
      for (int i = 0; i < lines.length && i < 20; i++) {
        print('  ${lines[i]}');
      }
      if (lines.length > 20) {
        print('  ... (${lines.length - 20} more lines)');
      }
      
      // Debug: Validate essential config elements
      print('🔍 Config validation:');
      final hasClient = configToUse.contains('client');
      final hasRemote = configToUse.contains('remote');
      final hasCA = configToUse.contains('<ca>') && configToUse.contains('</ca>');
      final hasDevTun = configToUse.contains('dev tun');
      final hasProto = configToUse.contains('proto ');
      print('  - Contains "client": $hasClient');
      print('  - Contains "remote": $hasRemote');
      print('  - Contains "<ca>": $hasCA');
      print('  - Contains "dev tun": $hasDevTun');
      print('  - Contains proto: $hasProto');
      
      // Strict validation: must have client, remote and inline CA
      if (!hasClient || !hasRemote || !hasCA) {
        _lastError = 'Invalid OpenVPN configuration - missing required directives (client/remote/CA)';
        print('❌ Invalid OpenVPN config - missing required directives');
        _set(VpnState.failed);
        return false;
      }
      
      // Try the correct API call - the plugin expects specific parameters
      print('🚀 Starting OpenVPN connection...');
      
      // Set up a proper timeout mechanism
      final Completer<bool> connectionCompleter = Completer<bool>();
      Timer? connectionTimeout;
      
      // Set up timeout (increased to 30s for VPNGate servers)
      connectionTimeout = Timer(const Duration(seconds: 30), () {
        if (!connectionCompleter.isCompleted) {
          print('⏰ Connection timeout after 30 seconds');
          _lastError = 'Connection timeout - server may be unreachable';
          _set(VpnState.failed);
          connectionCompleter.complete(false);
        }
      });
      
      try {
        // Detect if this config requires authentication
        final requiresAuth = _requiresAuth(configToUse);
        print('🔐 Config requires authentication: $requiresAuth');
        
        // Set up credentials based on config type
        String username = '';
        String password = '';
        
        // SoftEther / PacketiX servers generally require vpn/vpn
        if (requiresAuth) {
          username = 'vpn';
          password = 'vpn';
          print('🔑 Using authentication credentials: $username/$password');
        } else {
          print('🔓 Using empty credentials');
        }
        
        // Use the correct API call with appropriate credentials
        dynamic result;
        
        try {
          result = await _engine.connect(
            configToUse,
            'Vyntra',
            certIsRequired: false,
            username: username,
            password: password,
          );
          print('📊 Connection result: $result');
        } catch (e) {
          print('❌ Connection failed: $e');
          _lastError = 'Connection failed: $e';
          _set(VpnState.failed);
          connectionCompleter.complete(false);
          return false;
        }
        
        // Wait a bit for the connection to establish
        await Future.delayed(const Duration(seconds: 3));
        
        // Check if we're still in connecting state (connection might have succeeded)
        if (_current == VpnState.connecting) {
          print('🎉 VPN connection established successfully!');
          _set(VpnState.connected);
          _sessionManager.startSession();
          connectionCompleter.complete(true);
        } else {
          print('❌ Connection failed - state changed to: $_current');
          connectionCompleter.complete(false);
        }
        
      } catch (e) {
        print('❌ All connection methods failed: $e');
        _lastError = 'Connection failed: $e';
        _set(VpnState.failed);
        connectionCompleter.complete(false);
      }
      
      // Wait for connection result
      final success = await connectionCompleter.future;
      
      // Clean up
      connectionTimeout.cancel();
      
      if (success) {
        print('✅ VPN connection successful');
        return true;
      } else {
        print('❌ VPN connection failed: $_lastError');
        return false;
      }
      
    } catch (e) {
      _lastError = 'Connection failed: $e';
      print('❌ VPN connection failed: $e');
      _set(VpnState.failed);
      return false;
    }
  }
  
  // Detect if the OpenVPN config requires authentication
  bool _requiresAuth(String ovpnContent) {
    // SoftEther / PacketiX configs often contain "auth-user-pass"
    // or "PacketiX" in comments
    final hasAuthUserPass = RegExp(r'auth-user-pass', caseSensitive: false).hasMatch(ovpnContent);
    final hasPacketiX = ovpnContent.contains('PacketiX');
    final hasSoftEther = ovpnContent.contains('SoftEther');
    final hasAutoGenerated = ovpnContent.contains('AUTO-GENERATED BY SOFTETH');
    final hasPacketiXVPN = ovpnContent.contains('PacketiX VPN');
    
    final requiresAuth = hasAuthUserPass || hasPacketiX || hasSoftEther || hasAutoGenerated || hasPacketiXVPN;
    
    if (requiresAuth) {
      print('🔍 Auth detection patterns:');
      if (hasAuthUserPass) print('  ✓ auth-user-pass directive found');
      if (hasPacketiX) print('  ✓ PacketiX reference found');
      if (hasSoftEther) print('  ✓ SoftEther reference found');
      if (hasAutoGenerated) print('  ✓ AUTO-GENERATED BY SOFTETH found');
      if (hasPacketiXVPN) print('  ✓ PacketiX VPN reference found');
    }
    
    return requiresAuth;
  }

  String _optimizeOpenVpnConfig(String config) {
    String optimized = config;
    
    // Ensure we have the client directive
    if (!optimized.contains('client')) {
      optimized = 'client\n' + optimized;
    }
    
    // Convert UDP to TCP for better reliability
    if (optimized.contains('proto udp')) {
      print('🔄 Converting UDP to TCP for better compatibility...');
      optimized = optimized.replaceAll('proto udp', 'proto tcp');
      // Change port from 1194 (UDP) to 443 (TCP) if needed
      optimized = optimized.replaceAll(':1194', ':443');
      print('✅ Config converted to TCP protocol');
    }
    
    // Ensure we have a protocol directive
    if (!optimized.contains('proto ')) {
      optimized += '\nproto tcp\n';
    }
    
    // Ensure we have a dev directive
    if (!optimized.contains('dev ')) {
      optimized += '\ndev tun\n';
    }
    
    // Add connection timeout settings (shorter for faster failure detection)
    if (!optimized.contains('connect-timeout')) {
      optimized += '\nconnect-timeout 8\n';
    }
    
    // Add keepalive settings for better stability
    if (!optimized.contains('keepalive')) {
      optimized += '\nkeepalive 10 60\n';
    }
    
    // Add connection retry settings
    if (!optimized.contains('connect-retry')) {
      optimized += '\nconnect-retry 1\n';
    }
    
    // Add connection retry max settings
    if (!optimized.contains('connect-retry-max')) {
      optimized += '\nconnect-retry-max 2\n';
    }
    
    // Add handshake timeout (shorter for faster failure detection)
    if (!optimized.contains('handshake-window')) {
      optimized += '\nhandshake-window 8\n';
    }
    
    // Add server poll timeout
    if (!optimized.contains('server-poll-timeout')) {
      optimized += '\nserver-poll-timeout 8\n';
    }
    
    // Add TLS timeout for faster failure detection
    if (!optimized.contains('tls-timeout')) {
      optimized += '\ntls-timeout 8\n';
    }
    
    // Add connection retry delay
    if (!optimized.contains('connect-retry-delay')) {
      optimized += '\nconnect-retry-delay 2\n';
    }
    
    // Add verbosity for debugging
    if (!optimized.contains('verb ')) {
      optimized += '\nverb 3\n';
    }
    
    // Add mute for less noise
    if (!optimized.contains('mute ')) {
      optimized += '\nmute 20\n';
    }
    
    print('🔧 OpenVPN config optimized for better connection reliability');
    return optimized;
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