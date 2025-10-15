import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/vpngate_service.dart';
import '../../core/network/unified_vpn_service.dart';
import '../../core/models/vpn_server.dart';
import '../../core/vpn/reconnect_watchdog.dart';
import '../../core/vpn/vpn_controller.dart';
import '../servers/server_list_screen.dart';
import '../settings/settings_screen.dart';

final vpngateProvider = Provider((ref) => VpnGateService());
final unifiedVpnProvider = Provider((ref) => UnifiedVpnService());
final vpnControllerProvider = Provider((ref) => VpnController());

class HomeScreen extends ConsumerStatefulWidget {
  final void Function(ThemeMode) onThemeChange;
  final ThemeMode currentMode;
  const HomeScreen({
    super.key, 
    required this.onThemeChange, 
    required this.currentMode,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  List<VpnServer> servers = [];
  String? _currentProfile;
  ReconnectWatchdog? _watchdog;
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  bool _loadingServers = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _glowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _glowController.repeat(reverse: true);
    
    Future.microtask(() async {
      final ctrl = ref.read(vpnControllerProvider);
      await ctrl.init();
      _watchdog = ReconnectWatchdog(
        controller: ctrl,
        currentProfileProvider: () async => _currentProfile,
      );
      await _watchdog!.start();
      await _loadServers();
    });
  }

  Future<void> _loadServers() async {
    if (_loadingServers) return;
    
    setState(() {
      _loadingServers = true;
    });
    
    try {
      final unifiedService = ref.read(unifiedVpnProvider);
      // Fetch all servers from unified service (cached)
      final allServers = await unifiedService.fetchAllServers();

      if (mounted) {
        setState(() {
          // Prefer lower ping first when available, but keep all protocols
          final list = List<VpnServer>.from(allServers);
          list.sort((a, b) => (a.pingMs ?? 9999).compareTo(b.pingMs ?? 9999));
          servers = list; // Do not truncate so counts are accurate
          _loadingServers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingServers = false;
        });
      }
    }
  }

  Future<void> _retryLoadServers() async {
    setState(() {
      servers = [];
      _loadingServers = true;
    });
    
    try {
      final unifiedService = ref.read(unifiedVpnProvider);
      // Force refresh (bypass cache)
      final allServers = await unifiedService.forceRefresh();

      if (mounted) {
        setState(() {
          final list = List<VpnServer>.from(allServers);
          list.sort((a, b) => (a.pingMs ?? 9999).compareTo(b.pingMs ?? 9999));
          servers = list;
          _loadingServers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingServers = false;
        });
      }
    }
  }

  Future<void> _connectBest() async {
    if (servers.isEmpty) {
      await _loadServers();
      if (servers.isEmpty) return;
    }
    
    final ctrl = ref.read(vpnControllerProvider);
    // Prefer the fastest OpenVPN server using highest speed first, then lowest ping
    final List<VpnServer> openvpnServers = servers
        .where((s) => s.protocol == VpnProtocol.openvpn)
        .toList();
    openvpnServers.sort((a, b) {
      final int aspeed = a.speedBps ?? 0;
      final int bspeed = b.speedBps ?? 0;
      if (bspeed != aspeed) return bspeed.compareTo(aspeed); // higher speed first
      return (a.pingMs ?? 9999).compareTo(b.pingMs ?? 9999); // then lower ping
    });
    if (openvpnServers.isEmpty) return;

    final vpngate = ref.read(vpngateProvider);
    for (final candidate in openvpnServers) {
      try {
        String? ovpn = candidate.ovpnBase64;
        if (ovpn == null || ovpn.isEmpty) {
          final withConfig = await vpngate.getServerWithConfig(candidate.hostname);
          if (withConfig != null && withConfig.ovpnBase64.isNotEmpty) {
            ovpn = withConfig.ovpnBase64;
          }
        }
        if (ovpn == null || ovpn.isEmpty) {
          continue; // try next candidate
        }
        final profile = vpngate.buildHardenedOvpn(ovpn);
        _currentProfile = profile;
        await ctrl.connect(profile);
        return; // stop after first successful kick-off
      } catch (_) {
        // try next candidate
      }
    }
  }

  Future<void> _disconnect() async {
    final ctrl = ref.read(vpnControllerProvider);
    await ctrl.disconnect();
  }

  String _getServerCountText() {
    if (servers.isEmpty) return 'No servers available';
    
    final openvpnCount = servers.where((s) => s.protocol == VpnProtocol.openvpn).length;
    final wireguardCount = servers.where((s) => s.protocol == VpnProtocol.wireguard).length;
    final shadowsocksCount = servers.where((s) => s.protocol == VpnProtocol.shadowsocks).length;
    
    final List<String> parts = [];
    if (openvpnCount > 0) parts.add('$openvpnCount OpenVPN');
    if (wireguardCount > 0) parts.add('$wireguardCount WireGuard');
    if (shadowsocksCount > 0) parts.add('$shadowsocksCount Shadowsocks');
    
    return '${servers.length} servers: ${parts.join(', ')}';
  }

  @override
  void dispose() {
    _watchdog?.dispose();
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Widget _buildStatusCard(VpnState state, String? error) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusSubtext;
    
    switch (state) {
      case VpnState.connected:
        statusColor = const Color(0xFF00C851);
        statusIcon = Icons.security;
        statusText = 'Connected & Secure';
        statusSubtext = 'Your connection is protected';
        break;
      case VpnState.connecting:
        statusColor = const Color(0xFFFF8800);
        statusIcon = Icons.vpn_key;
        statusText = 'Connecting...';
        statusSubtext = 'Establishing secure tunnel';
        break;
      case VpnState.reconnecting:
        statusColor = const Color(0xFF2196F3);
        statusIcon = Icons.refresh;
        statusText = 'Reconnecting...';
        statusSubtext = 'Restoring connection';
        break;
      case VpnState.failed:
        statusColor = const Color(0xFFFF4444);
        statusIcon = Icons.error_outline;
        statusText = 'Connection Failed';
        statusSubtext = 'Unable to establish connection';
        break;
      default:
        statusColor = const Color(0xFF757575);
        statusIcon = Icons.vpn_lock_outlined;
        statusText = 'Disconnected';
        statusSubtext = 'Tap to connect securely';
    }

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.15),
            statusColor.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Glow effect
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor.withValues(alpha: _glowAnimation.value * 0.1),
                    ),
                  );
                },
              ),
              // Main icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: state == VpnState.connecting || state == VpnState.reconnecting 
                        ? _pulseAnimation.value : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 2),
                      ),
                      child: Icon(
                        statusIcon,
                        size: 48,
                        color: statusColor,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            statusText,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusSubtext,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          if (state == VpnState.connected) ...[
            const SizedBox(height: 12),
            StreamBuilder<Duration>(
              stream: ref.read(vpnControllerProvider).sessionManager.timeRemainingStream,
              initialData: ref.read(vpnControllerProvider).sessionManager.timeRemaining,
              builder: (context, snapshot) {
                final timeRemaining = snapshot.data ?? Duration.zero;
                final sessionManager = ref.read(vpnControllerProvider).sessionManager;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C851).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00C851).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_rounded,
                        size: 16,
                        color: Color(0xFF00C851),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Session: ${sessionManager.formatDuration(timeRemaining)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF00C851),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectButton(VpnState state) {
    final isConnected = state == VpnState.connected;
    final isLoading = state == VpnState.connecting || state == VpnState.reconnecting;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: ElevatedButton(
        onPressed: isLoading ? null : (isConnected ? _disconnect : (servers.isEmpty ? null : _connectBest)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? const Color(0xFFFF4444) : const Color(0xFF2196F3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 12,
          shadowColor: (isConnected ? const Color(0xFFFF4444) : const Color(0xFF2196F3)).withValues(alpha: 0.4),
        ),
        child: isLoading
            ? const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isConnected ? Icons.stop_rounded : Icons.play_arrow_rounded, 
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isConnected ? 'Disconnect' : 'Connect Fastest',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildServerInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: Color(0xFF2196F3),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server Network',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loadingServers 
                      ? 'Loading servers...' 
                      : servers.isEmpty 
                          ? 'No servers available - tap refresh to retry'
                          : _getServerCountText(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadingServers ? null : _retryLoadServers,
            icon: _loadingServers 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Hard refresh servers',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.1),
            const Color(0xFF8B5CF6).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.timer_rounded,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session Duration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Each session lasts 1 hour for optimal performance',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(vpnControllerProvider);
    
    return StreamBuilder<VpnState>(
      stream: ctrl.state,
      initialData: ctrl.current,
      builder: (context, snapshot) {
        final vpnState = snapshot.data ?? VpnState.disconnected;
        
        return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: const DecorationImage(
                  image: AssetImage('assets/vyntra logo.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Vyntra',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: IconButton(
                icon: Icon(
                  Icons.list_rounded, 
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.white 
                      : Theme.of(context).primaryColor,
                ),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ServerListScreen(
                      servers: servers,
                      onSelect: (s) async {
                        final ctrl = ref.read(vpnControllerProvider);
                        
                        // Handle different protocols
                        if (s.protocol == VpnProtocol.openvpn) {
                          final service = ref.read(vpngateProvider);
                          String? ovpnB64 = s.ovpnBase64;
                          if (ovpnB64 == null || ovpnB64.isEmpty) {
                            final withConfig = await service.getServerWithConfig(s.hostname);
                            if (withConfig == null || withConfig.ovpnBase64.isEmpty) {
                              return;
                            }
                            ovpnB64 = withConfig.ovpnBase64;
                          }
                          final String profile = service.buildHardenedOvpn(ovpnB64);
                          _currentProfile = profile;
                          Navigator.of(context).pop();
                          await ctrl.connect(profile);
                          return;
                        }

                        if (s.protocol == VpnProtocol.shadowsocks) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Shadowsocks connection will be added in a future update.')),
                          );
                          return;
                        }

                        if (s.protocol == VpnProtocol.wireguard) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('WireGuard connection will be added in a future update.')),
                          );
                          return;
                        }
                      },
                    ),
                  ));
                },
                tooltip: 'Server List',
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: IconButton(
                icon: Icon(
                  Icons.settings_rounded, 
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.white 
                      : Theme.of(context).primaryColor,
                ),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SettingsScreen(),
                  ));
                },
                tooltip: 'Settings',
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              backgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white.withValues(alpha: 0.15)
                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: IconButton(
                icon: Icon(
                  widget.currentMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.white 
                      : Theme.of(context).primaryColor,
                ),
                onPressed: () {
                  // Switch to opposite theme - single click
                  final newMode = widget.currentMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                  widget.onThemeChange(newMode);
                },
                tooltip: widget.currentMode == ThemeMode.dark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildStatusCard(vpnState, ctrl.lastError),
                    const SizedBox(height: 24),
                    _buildServerInfo(),
                    const SizedBox(height: 16),
                    _buildSessionInfo(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildConnectButton(vpnState),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}