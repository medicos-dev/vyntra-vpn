import 'dart:convert';
import 'package:http/http.dart' as http;

class VpnGateServer {
  final String hostName;
  final String ip;
  final int score;
  final int ping;
  final int speed;
  final String countryLong;
  final String countryShort;
  final int numVpnSessions;
  final int uptime;
  final int totalUsers;
  final int totalTraffic;
  final String logType;
  final String operator;
  final String message;
  final String? openvpnConfigDataBase64;

  VpnGateServer({
    required this.hostName,
    required this.ip,
    required this.score,
    required this.ping,
    required this.speed,
    required this.countryLong,
    required this.countryShort,
    required this.numVpnSessions,
    required this.uptime,
    required this.totalUsers,
    required this.totalTraffic,
    required this.logType,
    required this.operator,
    required this.message,
    this.openvpnConfigDataBase64,
  });

  factory VpnGateServer.fromCsvLine(List<String> fields) {
    return VpnGateServer(
      hostName: fields[0],
      ip: fields[1],
      score: int.tryParse(fields[2]) ?? 0,
      ping: int.tryParse(fields[3]) ?? 9999,
      speed: int.tryParse(fields[4]) ?? 0,
      countryLong: fields[5],
      countryShort: fields[6],
      numVpnSessions: int.tryParse(fields[7]) ?? 0,
      uptime: int.tryParse(fields[8]) ?? 0,
      totalUsers: int.tryParse(fields[9]) ?? 0,
      totalTraffic: int.tryParse(fields[10]) ?? 0,
      logType: fields[11],
      operator: fields[12],
      message: fields[13],
      openvpnConfigDataBase64: fields.length > 14 && fields[14].isNotEmpty ? fields[14] : null,
    );
  }

  // Calculate intelligent score based on ping and speed
  double get intelligentScore {
    if (score > 0) return score.toDouble();
    
    // Calculate score based on ping (lower is better) and speed (higher is better)
    final pingScore = (ping > 0) ? (1000.0 / ping.clamp(1, 1000)) : 0.0;
    final speedScore = (speed > 0) ? (speed / 1000000.0) : 0.0; // Convert to Mbps
    
    return (pingScore * 0.7 + speedScore * 0.3) * 1000;
  }

  // Check if server has valid OpenVPN config
  bool get hasValidConfig => 
      openvpnConfigDataBase64 != null && 
      openvpnConfigDataBase64!.isNotEmpty &&
      openvpnConfigDataBase64!.length > 100; // Basic validation
}

class VpnGateApiService {
  static const String _apiUrl = 'https://www.vpngate.net/api/iphone/';

  /// Fetch VPN servers from VPNGate API
  static Future<List<VpnGateServer>> fetchVpnGateServers() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch VPN servers: ${response.statusCode}');
      }

      return _parseVpnGateResponse(response.body);
    } catch (e) {
      print('Error fetching VPN servers: $e');
      return [];
    }
  }

  /// Parse the raw VPNGate API response
  static List<VpnGateServer> _parseVpnGateResponse(String responseBody) {
    final lines = responseBody.split('\n');
    final servers = <VpnGateServer>[];

    // Skip header lines and find the data section
    bool inDataSection = false;
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      // Skip empty lines and comments
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
        continue;
      }
      
      // Look for the data section marker
      if (trimmedLine.startsWith('*vpn_servers')) {
        inDataSection = true;
        continue;
      }
      
      // Stop at the end marker
      if (trimmedLine.startsWith('*')) {
        break;
      }
      
      // Parse server data
      if (inDataSection) {
        try {
          final fields = _parseCsvLine(trimmedLine);
          if (fields.length >= 14) {
            final server = VpnGateServer.fromCsvLine(fields);
            if (server.hasValidConfig) {
              servers.add(server);
            }
          }
        } catch (e) {
          print('Error parsing server line: $trimmedLine - $e');
          continue;
        }
      }
    }

    return servers;
  }

  /// Parse a CSV line handling quoted fields
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        fields.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    
    // Add the last field
    fields.add(buffer.toString().trim());
    
    return fields;
  }

  /// Get servers filtered by country
  static List<VpnGateServer> getServersByCountry(List<VpnGateServer> servers, String country) {
    return servers.where((server) => 
        server.countryLong.toLowerCase().contains(country.toLowerCase()) ||
        server.countryShort.toLowerCase().contains(country.toLowerCase())
    ).toList();
  }

  /// Get the best server based on intelligent scoring
  static VpnGateServer? getBestServer(List<VpnGateServer> servers) {
    if (servers.isEmpty) return null;
    
    // Sort by intelligent score (descending) then by ping (ascending)
    servers.sort((a, b) {
      final scoreComparison = b.intelligentScore.compareTo(a.intelligentScore);
      if (scoreComparison != 0) return scoreComparison;
      return a.ping.compareTo(b.ping);
    });
    
    return servers.first;
  }

  /// Decode Base64 OpenVPN config to readable format
  static String? decodeOpenVpnConfig(String base64Config) {
    try {
      final decoded = utf8.decode(base64Decode(base64Config));
      return decoded;
    } catch (e) {
      print('Error decoding OpenVPN config: $e');
      return null;
    }
  }
}