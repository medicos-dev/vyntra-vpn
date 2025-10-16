// Import the existing VpnGateServer for compatibility
import 'dart:convert';
import 'vpngate_server.dart';

enum VpnProtocol {
  openvpn,
  wireguard,
  shadowsocks,
}

class VpnServer {
  final String id;
  final String name;
  final String hostname;
  final String ip;
  final String country;
  final VpnProtocol protocol;
  final int port;
  final int? pingMs;
  final int? speedBps;
  final int? score;
  final String? description;
  final String? location;
  final String? latency;
  final String? method;
  final String? password;
  final String? publicKey;
  final List<String>? allowedIPs;
  final List<String>? dns;
  final int? mtu;
  final int? persistentKeepalive;
  final String? ovpnBase64;
  final bool hasConfig;

  const VpnServer({
    required this.id,
    required this.name,
    required this.hostname,
    required this.ip,
    required this.country,
    required this.protocol,
    required this.port,
    this.pingMs,
    this.speedBps,
    this.score,
    this.description,
    this.location,
    this.latency,
    this.method,
    this.password,
    this.publicKey,
    this.allowedIPs,
    this.dns,
    this.mtu,
    this.persistentKeepalive,
    this.ovpnBase64,
    this.hasConfig = false,
  });

  // Factory constructor for VPNGate servers
  factory VpnServer.fromVpnGate({
    required String hostName,
    required String ip,
    required String country,
    required int score,
    required int pingMs,
    required int speedBps,
    required String ovpnBase64,
  }) {
    return VpnServer(
      id: 'vpngate_${hostName}_$ip',
      name: hostName,
      hostname: hostName,
      ip: ip,
      country: country,
      protocol: VpnProtocol.openvpn,
      port: 1194, // Default OpenVPN port
      pingMs: pingMs,
      speedBps: speedBps,
      score: score,
      description: 'Free OpenVPN server from VPNGate community',
      ovpnBase64: ovpnBase64,
      hasConfig: ovpnBase64.isNotEmpty,
    );
  }

  // Factory constructor for Cloudflare WARP servers
  factory VpnServer.fromCloudflareWarp({
    required String name,
    required String endpoint,
    required String publicKey,
    required List<String> allowedIPs,
    required List<String> dns,
    required int mtu,
    required int persistentKeepalive,
  }) {
    final parts = endpoint.split(':');
    return VpnServer(
      id: 'cloudflare_${name.toLowerCase().replaceAll(' ', '_')}',
      name: name,
      hostname: parts[0],
      ip: parts[0], // Will be resolved by DNS
      country: name.contains('US') ? 'United States' : 'Europe',
      protocol: VpnProtocol.wireguard,
      port: int.parse(parts[1]),
      publicKey: publicKey,
      allowedIPs: allowedIPs,
      dns: dns,
      mtu: mtu,
      persistentKeepalive: persistentKeepalive,
      description: 'Fast and secure VPN powered by Cloudflare',
      hasConfig: true,
    );
  }

  // Factory constructor for Outline VPN servers
  factory VpnServer.fromOutline({
    required String name,
    required String hostname,
    required int port,
    required String method,
    required String password,
    required String description,
    required String location,
    required String latency,
  }) {
    return VpnServer(
      id: 'outline_${name.toLowerCase().replaceAll(' ', '_')}',
      name: name,
      hostname: hostname,
      ip: hostname, // Will be resolved by DNS
      country: location,
      protocol: VpnProtocol.shadowsocks,
      port: port,
      method: method,
      password: password,
      description: description,
      location: location,
      latency: latency,
      hasConfig: true,
    );
  }

  // Convert to VPNGate server for compatibility
  VpnGateServer toVpnGateServer() {
    return VpnGateServer(
      hostName: hostname,
      ip: ip,
      country: country,
      score: score ?? 0,
      pingMs: pingMs ?? 9999,
      speedBps: speedBps ?? 0,
      ovpnBase64: ovpnBase64 ?? '',
    );
  }

  // Get protocol display name
  String get protocolName {
    switch (protocol) {
      case VpnProtocol.openvpn:
        return 'OpenVPN';
      case VpnProtocol.wireguard:
        return 'WireGuard';
      case VpnProtocol.shadowsocks:
        return 'Shadowsocks';
    }
  }

  // Get protocol icon
  String get protocolIcon {
    switch (protocol) {
      case VpnProtocol.openvpn:
        return '🔒';
      case VpnProtocol.wireguard:
        return '⚡';
      case VpnProtocol.shadowsocks:
        return '🛡️';
    }
  }

  // Get speed in Mbps
  double get speedMbps {
    if (speedBps == null) return 0.0;
    return speedBps! / 1e6;
  }

  // Check if server is fast
  bool get isFast {
    if (pingMs == null) return false;
    return pingMs! < 100;
  }

  // Check if server is very fast
  bool get isVeryFast {
    if (pingMs == null) return false;
    return pingMs! < 50;
  }

  // Get decoded OpenVPN config text
  String? get ovpnConfig {
    if (ovpnBase64 == null || ovpnBase64!.isEmpty) return null;
    try {
      return utf8.decode(base64.decode(ovpnBase64!));
    } catch (e) {
      print('Error decoding Base64 OpenVPN config: $e');
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VpnServer &&
        other.id == id &&
        other.name == name &&
        other.hostname == hostname &&
        other.ip == ip &&
        other.country == country &&
        other.protocol == protocol &&
        other.port == port;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, hostname, ip, country, protocol, port);
  }
}
