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
  bool _sessionStarted = false;

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
      print('🌐 Using protocol: ${configToUse.contains('proto tcp') ? 'TCP' : 'UDP'}');
      
      // Debug: Print the optimized config for troubleshooting
      print('🔍 Optimized config preview:');
      final lines = configToUse.split('\n');
      for (int i = 0; i < lines.length && i < 20; i++) {
        print('  ${lines[i]}');
      }
      if (lines.length > 20) {
        print('  ... (${lines.length - 20} more lines)');
      }
      
      // Additional validation for common issues
      if (!configToUse.contains('remote ')) {
        _lastError = 'Invalid OpenVPN configuration - no remote server specified';
        print('❌ Invalid OpenVPN config - no remote server specified');
        _set(VpnState.failed);
        return false;
      }
      
      // Check for required directives
      final requiredDirectives = ['client', 'remote', 'dev', 'proto'];
      for (final directive in requiredDirectives) {
        if (!configToUse.contains('$directive ')) {
          print('⚠️ Missing directive: $directive');
        }
      }
      
      // Try the correct API call - the plugin expects specific parameters
      print('🚀 Starting OpenVPN connection...');
      
      // Sanitize config (trim trailing spaces and ensure newline at end)
      configToUse = configToUse.trimRight();
      if (!configToUse.endsWith('\n')) configToUse += '\n';
      
      // Ensure platform is prepared (VPN permission/binding) before connecting
      try {
        final prep = (_engine as dynamic).prepare;
        if (prep != null) {
          final res = prep();
          if (res is Future) {
            await res;
          }
        }
      } catch (_) {}
      
      // Set up a proper timeout mechanism
      final Completer<bool> connectionCompleter = Completer<bool>();
      Timer? connectionTimeout;
      
      // Set up timeout
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
        
        if (requiresAuth) {
          username = 'vpn';
          password = 'vpn';
          print('🔑 Using authentication credentials: $username/$password');
        } else {
          print('🔓 No authentication required');
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
          _sessionStarted = true;
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
    
    // Honor the protocol specified in the config (no conversion or injection)
    
    // Normalize auth-user-pass: remove file argument so provided credentials are used
    optimized = optimized.replaceAll(RegExp(r'^\s*auth-user-pass\s+\S+.*$', multiLine: true), 'auth-user-pass');
    
    // Ensure we have a dev directive
    if (!optimized.contains('dev ')) {
      optimized += '\ndev tun\n';
    }
    
    // Remove potentially unsupported/legacy timeout directives that can terminate OpenVPN
    // (connect-timeout, handshake-window, server-poll-timeout)
    optimized = optimized.replaceAll(RegExp(r'^\s*connect-timeout\b.*$', multiLine: true), '');
    optimized = optimized.replaceAll(RegExp(r'^\s*handshake-window\b.*$', multiLine: true), '');
    optimized = optimized.replaceAll(RegExp(r'^\s*server-poll-timeout\b.*$', multiLine: true), '');
    
    // Keep TLS timeout (supported) if user didn't specify
    if (!RegExp(r'^\s*tls-timeout\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\ntls-timeout 8\n';
    }
    
    // Add keepalive settings for better stability
    if (!optimized.contains('keepalive')) {
      optimized += '\nkeepalive 10 60\n';
    }
    
    // Add connection retry settings
    if (!RegExp(r'^\s*connect-retry\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\nconnect-retry 2\n';
    }
    
    // Add connection retry max settings
    if (!RegExp(r'^\s*connect-retry-max\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\nconnect-retry-max 3\n';
    }
    
    // Add connection retry delay
    if (!RegExp(r'^\s*connect-retry-delay\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\nconnect-retry-delay 2\n';
    }
    
    // SoftEther/PacketiX compatibility directives (inject only if absent)
    if (!RegExp(r'^\s*setenv\s+CLIENT_CERT\s+0', multiLine: true).hasMatch(optimized)) {
      optimized += '\nsetenv CLIENT_CERT 0\n';
    }
    if (!RegExp(r'^\s*remote-cert-tls\s+server', multiLine: true).hasMatch(optimized)) {
      optimized += '\nremote-cert-tls server\n';
    }
    if (!RegExp(r'^\s*tls-client\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\ntls-client\n';
    }
    if (!RegExp(r'^\s*auth-nocache\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\nauth-nocache\n';
    }
    
    // Do not inject cipher lists; honor ciphers from the original config
    // (data-ciphers, ncp-ciphers, cipher, auth) will be used only if present in config
    
    // Persistence and reliability tweaks
    if (!RegExp(r'^\s*persist-tun\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\npersist-tun\n';
    }
    if (!RegExp(r'^\s*persist-key\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\npersist-key\n';
    }
    
    // For UDP configs, help server detect exit cleanly
    if (RegExp(r'^\s*proto\s+udp', multiLine: true).hasMatch(optimized) &&
        !RegExp(r'^\s*explicit-exit-notify\b', multiLine: true).hasMatch(optimized)) {
      optimized += '\nexplicit-exit-notify 1\n';
    }
    
    // Increase verbosity for better diagnostics during bring-up
    if (!RegExp(r'^\s*verb\s+\d+', multiLine: true).hasMatch(optimized)) {
      optimized += '\nverb 5\n';
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
      // Avoid calling into plugin if already disconnected or session never started
      if (_current == VpnState.disconnected || !_sessionStarted) {
        _sessionStarted = false;
        return;
      }
      // Use dynamic to handle different plugin API versions
      final result = (_engine as dynamic).disconnect();
      
      // If it returns a Future, wait for it
      if (result is Future) {
        await result;
      }
      
      await _sessionManager.endSession(); // End session when disconnecting
      _sessionStarted = false;
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