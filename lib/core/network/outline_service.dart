import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OutlineServer {
  final String name;
  final String hostname;
  final int port;
  final String method;
  final String password;
  final String description;
  final String location;
  final String latency;

  OutlineServer({
    required this.name,
    required this.hostname,
    required this.port,
    required this.method,
    required this.password,
    required this.description,
    required this.location,
    required this.latency,
  });

  factory OutlineServer.fromJson(Map<String, dynamic> json) {
    return OutlineServer(
      name: json['name'] ?? 'Unknown',
      hostname: json['hostname'] ?? '',
      port: json['port'] ?? 443,
      method: json['method'] ?? 'chacha20-ietf-poly1305',
      password: json['password'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? 'Unknown',
      latency: json['latency'] ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'hostname': hostname,
      'port': port,
      'method': method,
      'password': password,
      'description': description,
      'location': location,
      'latency': latency,
    };
  }

  // Generate Shadowsocks URL for Outline client
  String get shadowsocksUrl {
    final credentials = base64Encode(utf8.encode('$method:$password'));
    return 'ss://$credentials@$hostname:$port#${Uri.encodeComponent(name)}';
  }

  // Generate config for Outline SDK
  Map<String, dynamic> get outlineConfig {
    return {
      'hostname': hostname,
      'port': port,
      'method': method,
      'password': password,
      'name': name,
      'description': description,
      'location': location,
      'latency': latency,
    };
  }
}

class OutlineService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Vercel API URL for Outline VPN
  static const String _outlineApiUrl = 'https://vyntra-vpn.vercel.app/api/outline-vpn';
  
  // Cache keys
  static const String _cacheKey = 'outline_servers_cache';
  static const String _cacheTimestampKey = 'outline_cache_timestamp';
  
  // Cache duration: 1 hour
  static const Duration _cacheDuration = Duration(hours: 1);

  Future<List<OutlineServer>> fetchOutlineServers() async {
    try {
      // Try to get cached data first
      final cachedData = await _getCachedData();
      if (cachedData != null) {
        return cachedData;
      }

      // Fetch fresh data from Vercel
      final freshData = await _fetchFromVercel();
      if (freshData.isNotEmpty) {
        // Cache the fresh data
        await _cacheData(freshData);
        return freshData;
      }

      // If fresh fetch fails, return empty list
      return <OutlineServer>[];
    } catch (e) {
      // Return cached data if available, even if expired
      final cachedData = await _getCachedData(ignoreExpiry: true);
      return cachedData ?? <OutlineServer>[];
    }
  }

  Future<List<OutlineServer>?> _getCachedData({bool ignoreExpiry = false}) async {
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
      return jsonList.map((json) => OutlineServer.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheData(List<OutlineServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert servers to JSON for caching
      final jsonList = servers.map((server) => server.toJson()).toList();
      final jsonString = json.encode(jsonList);
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Ignore cache errors
    }
  }

  Future<List<OutlineServer>> _fetchFromVercel() async {
    try {
      final Response response = await _dio.get(
        _outlineApiUrl,
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
        return <OutlineServer>[];
      }

      final Map<String, dynamic> data = response.data;
      final List<dynamic> serversJson = data['servers'] ?? [];

      return serversJson.map((json) => OutlineServer.fromJson(json)).toList();
    } catch (e) {
      return <OutlineServer>[];
    }
  }

  // Method to clear cache (useful for testing or manual refresh)
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
  Future<List<OutlineServer>> forceRefresh() async {
    await clearCache();
    return await fetchOutlineServers();
  }

  // Get server by name
  Future<OutlineServer?> getServerByName(String name) async {
    final servers = await fetchOutlineServers();
    try {
      return servers.firstWhere((server) => server.name == name);
    } catch (e) {
      return null;
    }
  }

  // Get servers by location
  Future<List<OutlineServer>> getServersByLocation(String location) async {
    final servers = await fetchOutlineServers();
    return servers.where((server) => 
      server.location.toLowerCase().contains(location.toLowerCase())
    ).toList();
  }

  // Get fastest server (lowest latency)
  Future<OutlineServer?> getFastestServer() async {
    final servers = await fetchOutlineServers();
    if (servers.isEmpty) return null;

    OutlineServer? fastest;
    int lowestLatency = 9999;

    for (final server in servers) {
      final latency = int.tryParse(server.latency.replaceAll('ms', '')) ?? 9999;
      if (latency < lowestLatency) {
        lowestLatency = latency;
        fastest = server;
      }
    }

    return fastest;
  }

  // Generate Outline config URL for sharing
  String generateConfigUrl(OutlineServer server) {
    return server.shadowsocksUrl;
  }

  // Validate server configuration
  bool validateServer(OutlineServer server) {
    return server.hostname.isNotEmpty &&
           server.port > 0 &&
           server.port <= 65535 &&
           server.method.isNotEmpty &&
           server.password.isNotEmpty;
  }
}
