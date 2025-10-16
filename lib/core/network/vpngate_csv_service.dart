import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vpn_server.dart';
import 'package:csv/csv.dart';

class VpnGateCsvService {
  static const String _vpngateApiUrl = 'https://www.vpngate.net/api/iphone/';
  
  /// Fetch and parse VPNGate servers directly from CSV with Base64 decoding
  static Future<List<VpnServer>> fetchVpnGateServers() async {
    try {
      final response = await http.get(
        Uri.parse(_vpngateApiUrl),
        headers: {
          'User-Agent': 'Vyntra-VPN-Android/1.0',
          'Cache-Control': 'no-cache',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch VPNGate servers: ${response.statusCode}');
      }

      final csv = response.body.split('\n');
      final List<VpnServer> servers = [];

      for (final line in csv) {
        // Skip comments and empty lines
        if (line.startsWith('*') || line.trim().isEmpty) continue;
        
        final parts = _parseCsvLine(line);
        if (parts.length < 15) continue;
        
        final base64Config = parts.last.trim();
        if (base64Config.isEmpty) continue;

        try {
          // Clean and validate Base64 string first
          String cleanBase64 = base64Config.trim();
          
          // Remove any non-Base64 characters
          cleanBase64 = cleanBase64.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
          
          // Check if length is valid for Base64
          if (cleanBase64.length % 4 != 0) {
            print('⚠️ Skipping server due to invalid Base64 length: ${cleanBase64.length}');
            continue;
          }
          
          // Check if it's a valid Base64 string
          if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(cleanBase64)) {
            print('⚠️ Skipping server due to invalid Base64 format');
            continue;
          }
          
          // Decode Base64 to get OpenVPN config text
          final ovpnText = utf8.decode(base64.decode(cleanBase64));
          
          // Comprehensive validation that it's a proper OpenVPN config
          if (!ovpnText.contains('client') || 
              !ovpnText.contains('remote') ||
              !ovpnText.contains('<ca>') ||
              !ovpnText.contains('</ca>')) {
            print('⚠️ Skipping server due to invalid OpenVPN config content');
            continue;
          }

          servers.add(VpnServer.fromVpnGate(
            hostName: parts[0].trim(),
            ip: parts[1].trim(),
            country: parts[5].trim(),
            score: int.tryParse(parts[2].trim()) ?? 0,
            pingMs: int.tryParse(parts[3].trim()) ?? 9999,
            speedBps: int.tryParse(parts[4].trim()) ?? 0,
            ovpnBase64: cleanBase64, // Use the cleaned Base64
          ));
        } catch (e) {
          // Skip servers with invalid Base64 configs
          print('Skipping server ${parts[0]} due to invalid config: $e');
          continue;
        }
      }

      print('✅ Successfully loaded ${servers.length} VPNGate servers');
      if (servers.isNotEmpty) {
        final firstServer = servers.first;
        final configPreview = firstServer.ovpnConfig?.substring(0, 120) ?? 'No config';
        print('📋 First server: ${firstServer.hostname} (${firstServer.country})');
        print('🔧 First OVPN config preview: $configPreview...');
        print('🌐 Server has valid config: ${firstServer.ovpnConfig != null && firstServer.ovpnConfig!.isNotEmpty}');
      }
      return servers;
    } catch (e) {
      print('❌ Error fetching VPNGate servers: $e');
      return [];
    }
  }

  /// Fetch and parse VPNGate servers and produce structured JSON (preserving Base64)
  static Future<Map<String, dynamic>> fetchAsStructuredJson() async {
    final response = await http.get(
      Uri.parse(_vpngateApiUrl),
      headers: {
        'User-Agent': 'Vyntra-VPN-Android/1.0',
        'Cache-Control': 'no-cache',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch VPNGate CSV: ${response.statusCode}');
    }
    final raw = response.body;
    final lines = raw.split('\n');
    // Remove comments and empty lines
    final filtered = lines.where((l) => l.isNotEmpty && !l.startsWith('*')).toList();
    if (filtered.isEmpty) {
      return {
        'timestamp': DateTime.now().toIso8601String(),
        'totalServers': 0,
        'services': {
          'vpngate': {
            'name': 'VPNGate',
            'type': 'openvpn',
            'servers': 0,
            'description': 'VPNGate OpenVPN community servers',
            'endpoint': _vpngateApiUrl,
            'features': <String>['openvpn','base64-config'],
            'sampleServers': <dynamic>[],
            'allServers': <dynamic>[],
          }
        }
      };
    }

    final csvConverter = const CsvToListConverter(shouldParseNumbers: false);
    final csvRows = csvConverter.convert(filtered.join('\n'));
    // First row is header
    final header = (csvRows.isNotEmpty) ? (csvRows.first as List<dynamic>).map((e) => e.toString()).toList() : <String>[];
    // Build a lowercase trimmed index map
    final idx = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      idx[header[i].trim().toLowerCase()] = i;
    }

    int _col(String name) => idx[name.toLowerCase()] ?? -1;

    // Accept common header variations
    int hostCol = _col('hostname');
    if (hostCol < 0) hostCol = _col('host name');
    if (hostCol < 0 && header.isNotEmpty) hostCol = 0; // fallback: first column is often HostName

    final requiredCols = <String>['ip','countrylong','score','ping','speed','openvpn_configdata_base64'];
    final missing = requiredCols.where((c) => _col(c) < 0).toList();
    if (hostCol < 0) missing.insert(0, 'hostname');
    if (missing.isNotEmpty) {
      throw Exception('CSV missing columns: ${missing.join(', ')}');
    }

    final allServers = <Map<String, dynamic>>[];

    for (int r = 1; r < csvRows.length; r++) {
      final row = csvRows[r] as List<dynamic>;
      if (row.length < header.length) continue;
      final int ipI = _col('ip');
      final int countryI = _col('countrylong');
      final int scoreI = _col('score');
      final int pingI = _col('ping');
      final int speedI = _col('speed');
      final int b64I = _col('openvpn_configdata_base64');
      if ([hostCol, ipI, countryI, scoreI, pingI, speedI, b64I].any((i) => i < 0)) continue;

      final host = row[hostCol]?.toString() ?? '';
      final ip = row[ipI]?.toString() ?? '';
      final country = row[countryI]?.toString() ?? '';
      final score = int.tryParse(row[scoreI]?.toString() ?? '') ?? 0;
      final ping = int.tryParse(row[pingI]?.toString() ?? '') ?? 9999;
      final speed = int.tryParse(row[speedI]?.toString() ?? '') ?? 0;
      final b64 = row[b64I]?.toString() ?? '';
      final hasConfig = b64.isNotEmpty;
      allServers.add({
        'hostName': host,
        'ip': ip,
        'country': country,
        'score': score,
        'ping': ping,
        'speed': speed,
        'hasConfig': hasConfig,
        'ovpnBase64': b64,
      });
    }

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'totalServers': allServers.length,
      'developer': 'Vyntra',
      'services': {
        'vpngate': {
          'name': 'VPNGate',
          'type': 'openvpn',
          'servers': allServers.length,
          'description': 'VPNGate OpenVPN community servers',
          'endpoint': _vpngateApiUrl,
          'features': <String>['openvpn','base64-config'],
          'sampleServers': allServers.take(5).map((s) => {
            'hostName': s['hostName'],
            'ip': s['ip'],
            'country': s['country'],
            'score': s['score'],
            'ping': s['ping'],
            'speed': s['speed'],
            'hasConfig': s['hasConfig'],
          }).toList(),
          'allServers': allServers,
        }
      },
      'recommendations': {
        'fastest': 'vpngate',
        'mostSecure': 'vpngate',
        'mostServers': 'vpngate',
        'bestForMobile': 'vpngate',
      }
    };
  }

  /// Parse CSV line handling quoted fields
  static List<String> _parseCsvLine(String line) {
    final List<String> parts = [];
    bool inQuote = false;
    String currentPart = '';
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuote = !inQuote;
      } else if (char == ',' && !inQuote) {
        parts.add(currentPart);
        currentPart = '';
      } else {
        currentPart += char;
      }
    }
    
    parts.add(currentPart); // Add the last part
    return parts;
  }

  /// Get a specific server by hostname or IP
  static Future<VpnServer?> getServerByHostOrIp(String hostOrIp) async {
    final servers = await fetchVpnGateServers();
    
    final needle = hostOrIp.toLowerCase().trim();
    for (final server in servers) {
      if (server.hostname.toLowerCase() == needle || 
          server.ip == hostOrIp.trim()) {
        return server;
      }
    }
    
    return null;
  }

  /// Get servers filtered by country
  static Future<List<VpnServer>> getServersByCountry(String country) async {
    final servers = await fetchVpnGateServers();
    return servers.where((server) => 
      server.country.toLowerCase().contains(country.toLowerCase())
    ).toList();
  }

  /// Get fastest servers (lowest ping)
  static Future<List<VpnServer>> getFastestServers({int limit = 10}) async {
    final servers = await fetchVpnGateServers();
    servers.sort((a, b) => (a.pingMs ?? 9999).compareTo(b.pingMs ?? 9999));
    return servers.take(limit).toList();
  }

  /// Get highest speed servers
  static Future<List<VpnServer>> getHighestSpeedServers({int limit = 10}) async {
    final servers = await fetchVpnGateServers();
    servers.sort((a, b) => (b.speedBps ?? 0).compareTo(a.speedBps ?? 0));
    return servers.take(limit).toList();
  }
}
