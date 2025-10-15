import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_server.dart';
import 'vpngate_service.dart';
import 'outline_service.dart';

class UnifiedVpnService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  final VpnGateService _vpngateService = VpnGateService();
  final OutlineService _outlineService = OutlineService();

  // Vercel API URLs
  static const String _unifiedApiUrl = 'https://vyntra-vpn.vercel.app/api/vpn-unified';
  static const String _cloudflareApiUrl = 'https://vyntra-vpn.vercel.app/api/cloudflare-warp';
  static const String _outlineApiUrl = 'https://vyntra-vpn.vercel.app/api/outline-vpn';
  
  // Cache keys
  static const String _cacheKey = 'unified_vpn_servers_cache';
  static const String _cacheTimestampKey = 'unified_vpn_cache_timestamp';
  
  // Cache duration: 1 hour
  static const Duration _cacheDuration = Duration(hours: 1);

  Future<List<VpnServer>> fetchAllServers() async {
    try {
      // Try to get cached data first
      final cachedData = await _getCachedData();
      if (cachedData != null) {
        return cachedData;
      }

      // Fetch fresh data from all sources
      final allServers = <VpnServer>[];
      
      // Fetch VPNGate servers
      try {
        final vpngateServers = await _fetchVpnGateServers();
        allServers.addAll(vpngateServers);
      } catch (e) {
        // Continue with other services if VPNGate fails
      }

      // Fetch Cloudflare WARP servers
      try {
        final cloudflareServers = await _fetchCloudflareServers();
        allServers.addAll(cloudflareServers);
      } catch (e) {
        // Continue with other services if Cloudflare fails
      }

      // Fetch Outline VPN servers
      try {
        final outlineServers = await _fetchOutlineServers();
        allServers.addAll(outlineServers);
      } catch (e) {
        // Continue with other services if Outline fails
      }

      if (allServers.isNotEmpty) {
        // Cache the fresh data
        await _cacheData(allServers);
        return allServers;
      }

      // If all fresh fetches fail, return cached data if available
      final cachedDataFallback = await _getCachedData(ignoreExpiry: true);
      return cachedDataFallback ?? <VpnServer>[];
    } catch (e) {
      // Return cached data if available, even if expired
      final cachedData = await _getCachedData(ignoreExpiry: true);
      return cachedData ?? <VpnServer>[];
    }
  }

  Future<List<VpnServer>> _fetchVpnGateServers() async {
    try {
      // Use the existing VPNGate service
      final vpngateServers = await _vpngateService.fetchServersFromVercel();
      
      return vpngateServers.map((server) => VpnServer.fromVpnGate(
        hostName: server.hostName,
        ip: server.ip,
        country: server.country,
        score: server.score,
        pingMs: server.pingMs,
        speedBps: server.speedBps,
        ovpnBase64: server.ovpnBase64,
      )).toList();
    } catch (e) {
      return <VpnServer>[];
    }
  }

  Future<List<VpnServer>> _fetchCloudflareServers() async {
    try {
      final Response response = await _dio.get(
        _cloudflareApiUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'User-Agent': 'Vyntra-VPN-Android/1.0',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        return <VpnServer>[];
      }

      final Map<String, dynamic> data = response.data;
      final List<dynamic> serversJson = data['servers'] ?? [];

      return serversJson.map((json) => VpnServer.fromCloudflareWarp(
        name: json['name'] ?? 'Unknown',
        endpoint: json['endpoint'] ?? '',
        publicKey: json['publicKey'] ?? '',
        allowedIPs: List<String>.from(json['allowedIPs'] ?? []),
        dns: List<String>.from(json['dns'] ?? []),
        mtu: json['mtu'] ?? 1280,
        persistentKeepalive: json['persistentKeepalive'] ?? 25,
      )).toList();
    } catch (e) {
      return <VpnServer>[];
    }
  }

  Future<List<VpnServer>> _fetchOutlineServers() async {
    try {
      final outlineServers = await _outlineService.fetchOutlineServers();
      
      return outlineServers.map((server) => VpnServer.fromOutline(
        name: server.name,
        hostname: server.hostname,
        port: server.port,
        method: server.method,
        password: server.password,
        description: server.description,
        location: server.location,
        latency: server.latency,
      )).toList();
    } catch (e) {
      return <VpnServer>[];
    }
  }

  Future<List<VpnServer>?> _getCachedData({bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);

      if (cachedJson == null || timestamp == null) {
        return null;
      }

      // Check if cache is still valid
      if (!ignoreExpiry) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final now = DateTime.now();
        if (now.difference(cacheTime) > _cacheDuration) {
          return null; // Cache expired
        }
      }

      // Parse cached JSON
      final List<dynamic> jsonList = json.decode(cachedJson);
      return jsonList.map((json) => _vpnServerFromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheData(List<VpnServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert servers to JSON for caching
      final jsonList = servers.map((server) => _vpnServerToJson(server)).toList();
      final jsonString = json.encode(jsonList);
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Ignore cache errors
    }
  }

  Map<String, dynamic> _vpnServerToJson(VpnServer server) {
    return {
      'id': server.id,
      'name': server.name,
      'hostname': server.hostname,
      'ip': server.ip,
      'country': server.country,
      'protocol': server.protocol.name,
      'port': server.port,
      'pingMs': server.pingMs,
      'speedBps': server.speedBps,
      'score': server.score,
      'description': server.description,
      'location': server.location,
      'latency': server.latency,
      'method': server.method,
      'password': server.password,
      'publicKey': server.publicKey,
      'allowedIPs': server.allowedIPs,
      'dns': server.dns,
      'mtu': server.mtu,
      'persistentKeepalive': server.persistentKeepalive,
      'ovpnBase64': server.ovpnBase64,
      'hasConfig': server.hasConfig,
    };
  }

  VpnServer _vpnServerFromJson(Map<String, dynamic> json) {
    return VpnServer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      hostname: json['hostname'] ?? '',
      ip: json['ip'] ?? '',
      country: json['country'] ?? '',
      protocol: VpnProtocol.values.firstWhere(
        (p) => p.name == json['protocol'],
        orElse: () => VpnProtocol.openvpn,
      ),
      port: json['port'] ?? 1194,
      pingMs: json['pingMs'],
      speedBps: json['speedBps'],
      score: json['score'],
      description: json['description'],
      location: json['location'],
      latency: json['latency'],
      method: json['method'],
      password: json['password'],
      publicKey: json['publicKey'],
      allowedIPs: json['allowedIPs'] != null ? List<String>.from(json['allowedIPs']) : null,
      dns: json['dns'] != null ? List<String>.from(json['dns']) : null,
      mtu: json['mtu'],
      persistentKeepalive: json['persistentKeepalive'],
      ovpnBase64: json['ovpnBase64'],
      hasConfig: json['hasConfig'] ?? false,
    );
  }

  // Method to clear cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
    } catch (e) {
      // Ignore errors
    }
  }

  // Method to force refresh (bypass cache)
  Future<List<VpnServer>> forceRefresh() async {
    await clearCache();
    return await fetchAllServers();
  }

  // Get servers by protocol
  Future<List<VpnServer>> getServersByProtocol(VpnProtocol protocol) async {
    final allServers = await fetchAllServers();
    return allServers.where((server) => server.protocol == protocol).toList();
  }

  // Get fastest server
  Future<VpnServer?> getFastestServer() async {
    final allServers = await fetchAllServers();
    if (allServers.isEmpty) return null;

    VpnServer? fastest;
    int lowestPing = 9999;

    for (final server in allServers) {
      if (server.pingMs != null && server.pingMs! < lowestPing) {
        lowestPing = server.pingMs!;
        fastest = server;
      }
    }

    return fastest;
  }

  // Get server by ID
  Future<VpnServer?> getServerById(String id) async {
    final allServers = await fetchAllServers();
    try {
      return allServers.firstWhere((server) => server.id == id);
    } catch (e) {
      return null;
    }
  }

  // Get servers by country
  Future<List<VpnServer>> getServersByCountry(String country) async {
    final allServers = await fetchAllServers();
    return allServers.where((server) => 
      server.country.toLowerCase().contains(country.toLowerCase())
    ).toList();
  }

  // Get VPN services info
  Future<Map<String, dynamic>?> getVpnServicesInfo() async {
    try {
      final Response response = await _dio.get(
        _unifiedApiUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'User-Agent': 'Vyntra-VPN-Android/1.0',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
