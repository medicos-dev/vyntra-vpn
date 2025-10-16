import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vpn_server.dart';

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

      // Find header and map indices
      int headerIdx = -1;
      List<String> headerCols = [];
      for (int i = 0; i < csv.length; i++) {
        final l = csv[i];
        if (l.startsWith('*') || l.trim().isEmpty) continue;
        final parts = _parseCsvLine(l);
        if (parts.any((c) => c.contains('OpenVPN_ConfigData_Base64'))) {
          headerIdx = i;
          headerCols = parts.map((e) => e.trim()).toList();
          break;
        }
      }
      if (headerIdx == -1) {
        return servers;
      }

      int hostIdx = headerCols.indexOf('HostName');
      int ipIdx = headerCols.indexOf('IP');
      int countryIdx = headerCols.indexOf('CountryLong');
      int scoreIdx = headerCols.indexOf('Score');
      int pingIdx = headerCols.indexOf('Ping');
      int speedIdx = headerCols.indexOf('Speed');
      int b64Idx = headerCols.indexOf('OpenVPN_ConfigData_Base64');
      if ([hostIdx, ipIdx, countryIdx, b64Idx].any((i) => i == -1)) {
        return servers;
      }

      for (int i = headerIdx + 1; i < csv.length; i++) {
        final line = csv[i];
        // Skip comments and empty lines
        if (line.startsWith('*') || line.trim().isEmpty) continue;

        final parts = _parseCsvLine(line);
        if (parts.length <= b64Idx) continue;

        String base64Config = parts[b64Idx].trim();
        if (base64Config.isEmpty) continue;

        // Clean and pad Base64
        String cleanBase64 = base64Config.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
        // Auto pad to multiple of 4
        final rem = cleanBase64.length % 4;
        if (rem != 0) {
          cleanBase64 = cleanBase64.padRight(cleanBase64.length + (4 - rem), '=');
        }

        try {
          // Decode Base64 to get OpenVPN config text
          final ovpnText = utf8.decode(base64.decode(cleanBase64));

          // Comprehensive validation that it's a proper OpenVPN config
          if (!ovpnText.contains('client') ||
              !ovpnText.contains('remote') ||
              !ovpnText.contains('<ca>') ||
              !ovpnText.contains('</ca>')) {
            // Skip if essential elements missing
            continue;
          }

          servers.add(VpnServer.fromVpnGate(
            hostName: parts.length > hostIdx ? parts[hostIdx].trim() : 'unknown',
            ip: parts.length > ipIdx ? parts[ipIdx].trim() : '0.0.0.0',
            country: parts.length > countryIdx ? parts[countryIdx].trim() : 'Unknown',
            score: parts.length > scoreIdx ? int.tryParse((parts[scoreIdx]).trim()) ?? 0 : 0,
            pingMs: parts.length > pingIdx ? int.tryParse((parts[pingIdx]).trim()) ?? 9999 : 9999,
            speedBps: parts.length > speedIdx ? int.tryParse((parts[speedIdx]).trim()) ?? 0 : 0,
            ovpnBase64: cleanBase64,
          ));
        } catch (e) {
          // Skip servers with invalid Base64 configs
          // print('Skipping server due to invalid Base64: $e');
          continue;
        }
      }

      return servers;
    } catch (e) {
      return <VpnServer>[];
    }
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
