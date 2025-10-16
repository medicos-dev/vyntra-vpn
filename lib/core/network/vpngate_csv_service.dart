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

      for (final line in csv) {
        // Skip comments and empty lines
        if (line.startsWith('*') || line.trim().isEmpty) continue;
        
        final parts = _parseCsvLine(line);
        if (parts.length < 15) continue;
        
        final base64Config = parts.last.trim();
        if (base64Config.isEmpty) continue;

        try {
          // Decode Base64 to get OpenVPN config text
          final ovpnText = utf8.decode(base64.decode(base64Config));
          
          // Validate that it's a proper OpenVPN config
          if (!ovpnText.contains('client') || !ovpnText.contains('remote')) {
            continue;
          }

          servers.add(VpnServer.fromVpnGate(
            hostName: parts[0].trim(),
            ip: parts[1].trim(),
            country: parts[5].trim(),
            score: int.tryParse(parts[2].trim()) ?? 0,
            pingMs: int.tryParse(parts[3].trim()) ?? 9999,
            speedBps: int.tryParse(parts[4].trim()) ?? 0,
            ovpnBase64: base64Config,
          ));
        } catch (e) {
          // Skip servers with invalid Base64 configs
          print('Skipping server ${parts[0]} due to invalid config: $e');
          continue;
        }
      }

      return servers;
    } catch (e) {
      print('Error fetching VPNGate servers: $e');
      return [];
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
