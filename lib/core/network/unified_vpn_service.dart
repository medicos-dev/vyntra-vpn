import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_server.dart';
import '../config/feature_flags.dart';

class UnifiedVpnService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  // Optional: set a Vercel Protection Bypass token here if your API is being challenged
  // Go to Vercel → Project Settings → Protection Bypass → create token and paste below
  static const String _vercelBypassToken = 'thJgAkOY1niCHIBLu8BmWuqFD02VP0Bb';

  // Vercel API URLs
  static const String _unifiedApiUrl = 'https://vyntra-vpn.vercel.app/api/vpn-unified';
  
  // Cache keys
  static const String _cacheKey = 'unified_vpn_servers_cache';
  static const String _cacheTimestampKey = 'unified_vpn_cache_timestamp';
  
  // Cache duration: 1 hour
  static const Duration _cacheDuration = Duration(hours: 1);

  // Clear cache to force fresh fetch
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      print('🔄 Unified VPN cache cleared');
    } catch (e) {
      print('⚠️ Failed to clear cache: $e');
    }
  }

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

  Future<List<VpnServer>> _fetchFromUnifiedApi({bool retried = false}) async {
    try {
      final Response response = await _dio.get(
        _unifiedApiUrl,
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'User-Agent': 'Vyntra-VPN-Android/1.0',
            if (_vercelBypassToken.isNotEmpty) 'x-vercel-protection-bypass': _vercelBypassToken,
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        return <VpnServer>[];
      }

      final Map<String, dynamic> data = (response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{});
      final Map<String, dynamic> services = (data['services'] is Map<String, dynamic>
          ? data['services'] as Map<String, dynamic>
          : <String, dynamic>{});
      final List<VpnServer> allServers = <VpnServer>[];

      Map<String, dynamic>? _pickService(Map<String, dynamic> src, List<String> keys) {
        for (final k in keys) {
          final val = src[k];
          if (val is Map<String, dynamic>) return val;
        }
        return null;
      }

      // Parse VPNGate servers (support aliases)
      final Map<String, dynamic>? vpngateData = _pickService(services, const ['vpngate', 'vpnGate', 'VPNGate']);
      if (vpngateData != null) {
        final List<dynamic> vpngateServers = (vpngateData['allServers'] is List
            ? vpngateData['allServers'] as List
            : <dynamic>[]);
        
        print('🔍 VPNGate servers count: ${vpngateServers.length}');
        if (vpngateServers.isNotEmpty) {
          final firstServer = vpngateServers.first;
          if (firstServer is Map<String, dynamic>) {
            print('🔍 First server keys: ${firstServer.keys.toList()}');
            print('🔍 First server ovpnBase64 length: ${firstServer['ovpnBase64']?.toString().length ?? 'null'}');
          }
        }
        
        for (final serverJson in vpngateServers) {
          try {
            final Map<String, dynamic> m = serverJson is Map<String, dynamic> ? serverJson : <String, dynamic>{};
            final base64Data = (m['ovpnBase64'] ?? '').toString();
            
            // Debug first few servers
            if (allServers.length < 3) {
              print('🔍 Server ${allServers.length + 1}: ${m['hostName']} - Base64 length: ${base64Data.length}');
            }
            
            final server = VpnServer.fromVpnGate(
              hostName: (m['hostName'] ?? '').toString(),
              ip: (m['ip'] ?? '').toString(),
              country: (m['country'] ?? '').toString(),
              score: (m['score'] is num ? (m['score'] as num).toInt() : 0),
              pingMs: (m['ping'] is num ? (m['ping'] as num).toInt() : 9999),
              speedBps: (m['speed'] is num ? (m['speed'] as num).toInt() : 0),
              ovpnBase64: base64Data, // Use actual Base64 data from API
            );
            allServers.add(server);
          } catch (e) {
            print('⚠️ Failed to create server: $e');
          }
        }
      }

      // Cloudflare WARP (disabled by flag)
      final Map<String, dynamic>? cloudflareData = kEnableCloudflareWarp
          ? _pickService(services, const ['cloudflareWarp', 'cloudflare_warp', 'CloudflareWARP', 'warp'])
          : null;
      if (cloudflareData != null) {
        final List<dynamic> cloudflareServers = (cloudflareData['servers'] is List
            ? cloudflareData['servers'] as List
            : <dynamic>[]);
        
        for (final serverJson in cloudflareServers) {
          try {
            final Map<String, dynamic> m = serverJson is Map<String, dynamic> ? serverJson : <String, dynamic>{};
            final server = VpnServer.fromCloudflareWarp(
              name: (m['name'] ?? 'Unknown').toString(),
              endpoint: (m['endpoint'] ?? '').toString(),
              publicKey: (m['publicKey'] ?? '').toString(),
              allowedIPs: (m['allowedIPs'] is List)
                  ? List<String>.from((m['allowedIPs'] as List).map((e) => e.toString()))
                  : <String>[],
              dns: (m['dns'] is List)
                  ? List<String>.from((m['dns'] as List).map((e) => e.toString()))
                  : <String>[],
              mtu: (m['mtu'] is num ? (m['mtu'] as num).toInt() : 1280),
              persistentKeepalive: (m['persistentKeepalive'] is num
                  ? (m['persistentKeepalive'] as num).toInt()
                  : 25),
            );
            allServers.add(server);
          } catch (e) {
            // Skip invalid servers
          }
        }
      }

      // Outline VPN (disabled by flag)
      final Map<String, dynamic>? outlineData = kEnableOutlineVpn
          ? _pickService(services, const ['outlineVpn', 'outline_vpn', 'OutlineVPN', 'outline'])
          : null;
      if (outlineData != null) {
        final dynamic serversData = outlineData['servers'];
        final List<dynamic> outlineServers = serversData is List
            ? serversData
            : serversData is Map
                ? (serversData).values
                    .expand((v) => v is List ? v : const <dynamic>[])
                    .toList()
                : <dynamic>[];
        
        for (final serverJson in outlineServers) {
          try {
            final Map<String, dynamic> m = serverJson is Map<String, dynamic> ? serverJson : <String, dynamic>{};
            final server = VpnServer.fromOutline(
              name: (m['name'] ?? 'Unknown').toString(),
              hostname: (m['hostname'] ?? '').toString(),
              port: (m['port'] is num ? (m['port'] as num).toInt() : 8388),
              method: (m['method'] ?? 'chacha20-ietf-poly1305').toString(),
              password: (m['password'] ?? '').toString(),
              description: (m['description'] ?? '').toString(),
              location: (m['location'] ?? '').toString(),
              latency: (m['latency'] ?? '').toString(),
            );
            allServers.add(server);
          } catch (e) {
            // Skip invalid servers
          }
        }
      }

      if (allServers.isEmpty && !retried) {
        // Retry once after a short delay
        await Future.delayed(const Duration(seconds: 2));
        return _fetchFromUnifiedApi(retried: true);
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
