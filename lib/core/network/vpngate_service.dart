import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpngate_server.dart';

class VpnGateService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Vercel API URL - will be updated after deployment
  static const String _vercelApiUrl = 'https://vyntra-vpn.vercel.app/api/vpngate';
  
  // Cache keys
  static const String _cacheKey = 'vpngate_csv_cache';
  static const String _cacheTimestampKey = 'vpngate_cache_timestamp';
  
  // Cache duration: 2 hours
  static const Duration _cacheDuration = Duration(hours: 2);

  String _safeDecodeResponse(dynamic data) {
    if (data is String) {
      return data;
    } else if (data is List<int>) {
      return utf8.decode(data);
    } else if (data is Uint8List) {
      return utf8.decode(data);
    } else {
      return data.toString();
    }
  }

  Future<List<VpnGateServer>> fetchServersFromVercel() async {
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
      return <VpnGateServer>[];
    } catch (e) {
      // Return cached data if available, even if expired
      final cachedData = await _getCachedData(ignoreExpiry: true);
      return cachedData ?? <VpnGateServer>[];
    }
  }

  Future<List<VpnGateServer>?> _getCachedData({bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCsv = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);

      if (cachedCsv == null || timestamp == null) {
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

      // Parse cached CSV
      return _parseServers(cachedCsv);
    } catch (e) {
      return null;
    }
  }

  Future<void> _cacheData(List<VpnGateServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert servers back to CSV format for caching
      final csvData = _serversToCsv(servers);
      
      await prefs.setString(_cacheKey, csvData);
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Ignore cache errors
    }
  }

  Future<List<VpnGateServer>> _fetchFromVercel() async {
    try {
      final Response response = await _dio.get(
        _vercelApiUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/csv,text/plain,*/*',
            'Cache-Control': 'no-cache',
            'User-Agent': 'Vyntra-VPN-Android/1.0',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200) {
        return <VpnGateServer>[];
      }

      final String csvData = _safeDecodeResponse(response.data);

      if (csvData.isEmpty || csvData.length < 100) {
        return <VpnGateServer>[];
      }

      return _parseServers(csvData);
    } catch (e) {
      return <VpnGateServer>[];
    }
  }

  List<VpnGateServer> _parseServers(String csvData) {
    // Handle UTF-8 BOM and invisible characters
    String cleanData = csvData;
    
    // Remove UTF-8 BOM if present
    if (cleanData.startsWith('\uFEFF')) {
      cleanData = cleanData.substring(1);
    }
    
    // Remove any invisible characters
    cleanData = cleanData.replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '');
    
    final List<String> lines = cleanData
        .split(RegExp(r'\r?\n'))
        .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('*'))
        .toList();
    
    if (lines.length < 2) {
      return <VpnGateServer>[];
    }
    
    // Look for the header line that contains HostName (case-insensitive)
    final int headerIndex = lines.indexWhere((l) => l.toLowerCase().contains('hostname,'));
    if (headerIndex < 0) {
      return <VpnGateServer>[];
    }

    final List<String> header = _parseCsvLine(lines[headerIndex]);
    
    // Create column index mapping with trimmed keys
    final Map<String, int> idx = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      idx[header[i].trim()] = i;
    }
    
    // Strict check for required columns
    if (!idx.containsKey('OpenVPN_ConfigData_Base64') || 
        !idx.containsKey('HostName') || 
        !idx.containsKey('IP') || 
        !idx.containsKey('CountryLong')) {
      return <VpnGateServer>[];
    }

    final List<VpnGateServer> out = <VpnGateServer>[];
    
    // Parse each server line
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final String line = lines[i];
      if (line.isEmpty) continue;
      
      // Use RFC-style CSV parser
      final List<String> cols = _parseCsvLine(line);
      
      if (cols.length <= idx['OpenVPN_ConfigData_Base64']!) continue;
      
      final String b64 = cols[idx['OpenVPN_ConfigData_Base64']!].trim();
      
      // Validate Base64 config
      if (b64.isEmpty || b64.length < 10 || !_isValidBase64(b64)) {
        continue;
      }
      
      try {
        // Handle missing columns gracefully with proper bounds checking
        final String hostName = cols.length > idx['HostName']! ? cols[idx['HostName']!].trim() : 'Unknown';
        final String ip = cols.length > idx['IP']! ? cols[idx['IP']!].trim() : '0.0.0.0';
        final String country = cols.length > idx['CountryLong']! ? cols[idx['CountryLong']!].trim() : 'Unknown';
        final int score = cols.length > idx['Score']! ? int.tryParse(cols[idx['Score']!].trim()) ?? 0 : 0;
        final int ping = cols.length > idx['Ping']! ? int.tryParse(cols[idx['Ping']!].trim()) ?? 9999 : 9999;
        final int speed = cols.length > idx['Speed']! ? int.tryParse(cols[idx['Speed']!].trim()) ?? 0 : 0;
        
        out.add(
          VpnGateServer(
            hostName: hostName,
            ip: ip,
            country: country,
            score: score,
            pingMs: ping,
            speedBps: speed,
            ovpnBase64: b64,
          ),
        );
      } catch (e) {
        continue;
      }
    }
    
    return out;
  }

  bool _isValidBase64(String str) {
    try {
      base64.decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote inside quoted field
          current.write('"');
          i++; // Skip next quote
        } else {
          // Toggle quote state
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator
        result.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    
    // Add final field
    result.add(current.toString());
    
    // Trim whitespace from unquoted fields
    for (int i = 0; i < result.length; i++) {
      if (!result[i].startsWith('"') || !result[i].endsWith('"')) {
        result[i] = result[i].trim();
      }
    }
    
    return result;
  }

  String _serversToCsv(List<VpnGateServer> servers) {
    if (servers.isEmpty) return '';
    
    final StringBuffer csv = StringBuffer();
    
    // Header
    csv.writeln('HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64');
    
    // Data rows
    for (final server in servers) {
      csv.writeln('${server.hostName},${server.ip},${server.score},${server.pingMs},${server.speedBps},${server.country},,0,0,0,0,2weeks,,,${server.ovpnBase64}');
    }
    
    return csv.toString();
  }

  // Legacy methods for backward compatibility
  Future<List<VpnGateServer>> fetchServersQuick() async {
    final servers = await fetchServersFromVercel();
    return servers.take(10).toList();
  }

  Future<List<VpnGateServer>> fetchServers() async {
    return await fetchServersFromVercel();
  }

  String buildHardenedOvpn(String base64Config) {
    final String raw = utf8.decode(base64.decode(base64Config));
    final StringBuffer buf = StringBuffer();
    buf.write(raw);

    bool present(String directive) =>
        RegExp('^${RegExp.escape(directive)}\\b', multiLine: true)
            .hasMatch(raw);

    void ensure(String directive) {
      if (!present(directive)) buf.writeln(directive);
    }

    ensure('client');
    ensure('nobind');
    ensure('persist-key');
    ensure('persist-tun');
    ensure('remote-cert-tls server');
    ensure('cipher AES-256-GCM');
    ensure('auth SHA256');
    ensure('pull-filter ignore "ifconfig-ipv6"');
    ensure('dhcp-option DNS 1.1.1.1');
    ensure('setenv IV_GUI_VER Vyntra-Android-1.0');

    return buf.toString();
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
  Future<List<VpnGateServer>> forceRefresh() async {
    await clearCache();
    return await fetchServersFromVercel();
  }
}