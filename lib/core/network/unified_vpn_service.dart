import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_server.dart';

class UnifiedVpnService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Vercel API URLs
  static const String _unifiedApiUrl = 'https://vyntra-vpn.vercel.app/api/vpn-unified';
  
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

      // Fetch fresh data from unified API
      final allServers = await _fetchFromUnifiedApi();
      
      if (allServers.isNotEmpty) {
        // Cache the fresh data
        await _cacheData(allServers);
        return allServers;
      }

      // If unified API fails, return cached data if available
      final cachedDataFallback = await _getCachedData(ignoreExpiry: true);
      return cachedDataFallback ?? <VpnServer>[];
    } catch (e) {
      // Return cached data if available, even if expired
      final cachedData = await _getCachedData(ignoreExpiry: true);
      return cachedData ?? <VpnServer>[];
    }
  }

  Future<List<VpnServer>> _fetchFromUnifiedApi() async {
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

      if (response.statusCode != 200) {
        return <VpnServer>[];
      }

      final Map<String, dynamic> data = response.data;
      final Map<String, dynamic> services = data['services'] ?? {};
      final List<VpnServer> allServers = <VpnServer>[];

      // Parse VPNGate servers
      if (services['vpngate'] != null) {
        final vpngateData = services['vpngate'];
        final List<dynamic> vpngateServers = vpngateData['allServers'] ?? [];
        
        for (final serverJson in vpngateServers) {
          try {
            final server = VpnServer.fromVpnGate(
              hostName: serverJson['hostName'] ?? '',
              ip: serverJson['ip'] ?? '',
              country: serverJson['country'] ?? '',
              score: serverJson['score'] ?? 0,
              pingMs: serverJson['ping'] ?? 9999,
              speedBps: serverJson['speed'] ?? 0,
              ovpnBase64: '', // Will be fetched separately when needed
            );
            allServers.add(server);
          } catch (e) {
            // Skip invalid servers
          }
        }
      }

      // Parse Cloudflare WARP servers
      if (services['cloudflareWarp'] != null) {
        final cloudflareData = services['cloudflareWarp'];
        final List<dynamic> cloudflareServers = cloudflareData['servers'] ?? [];
        
        for (final serverJson in cloudflareServers) {
          try {
            final server = VpnServer.fromCloudflareWarp(
              name: serverJson['name'] ?? 'Unknown',
              endpoint: serverJson['endpoint'] ?? '',
              publicKey: serverJson['publicKey'] ?? '',
              allowedIPs: List<String>.from(serverJson['allowedIPs'] ?? []),
              dns: List<String>.from(serverJson['dns'] ?? []),
              mtu: serverJson['mtu'] ?? 1280,
              persistentKeepalive: serverJson['persistentKeepalive'] ?? 25,
            );
            allServers.add(server);
          } catch (e) {
            // Skip invalid servers
          }
        }
      }

      // Parse Outline VPN servers
      if (services['outlineVpn'] != null) {
        final outlineData = services['outlineVpn'];
        final List<dynamic> outlineServers = outlineData['servers'] ?? [];
        
        for (final serverJson in outlineServers) {
          try {
            final server = VpnServer.fromOutline(
              name: serverJson['name'] ?? 'Unknown',
              hostname: serverJson['hostname'] ?? '',
              port: serverJson['port'] ?? 8388,
              method: serverJson['method'] ?? 'chacha20-ietf-poly1305',
              password: serverJson['password'] ?? '',
              description: serverJson['description'] ?? '',
              location: serverJson['location'] ?? '',
              latency: serverJson['latency'] ?? '',
            );
            allServers.add(server);
          } catch (e) {
            // Skip invalid servers
          }
        }
      }

      return allServers;
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
      // If cache exists but is empty, treat as no-cache so we refetch fresh data
      if (!ignoreExpiry && (jsonList.isEmpty)) {
        return null;
      }
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
      
      // Only cache if we actually have servers
      if (servers.isNotEmpty) {
        await prefs.setString(_cacheKey, jsonString);
        await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      } else {
        // Clear cache if no servers to avoid persisting empty state
        await prefs.remove(_cacheKey);
        await prefs.remove(_cacheTimestampKey);
      }
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
    // Bypass cache and hit unified API directly
    final fresh = await _fetchFromUnifiedApi();
    if (fresh.isNotEmpty) {
      await _cacheData(fresh);
    }
    return fresh;
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
