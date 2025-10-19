import 'package:http/http.dart' as http;
import '../models/vpngate_server_l2tp.dart';

class VpnGateApiService {
  static const String _apiUrl = 'https://www.vpngate.net/api/iphone/';
  
  /// Fetch VPN servers from VPNGate API
  static Future<List<VpnGateServer>> fetchVpnGateServers() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch VPN servers: ${response.statusCode}');
      }

      return _parseVpnGateResponse(response.body);
    } catch (e) {
      throw Exception('Error fetching VPN servers: $e');
    }
  }

  /// Parse the raw VPNGate API response
  static List<VpnGateServer> _parseVpnGateResponse(String responseBody) {
    final List<VpnGateServer> servers = [];
    final List<String> lines = responseBody.split('\n');
    
    // Find the header line (starts with #HostName,IP,Score,Ping,Speed...)
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#HostName,IP,Score,Ping,Speed')) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex == -1) {
      throw Exception('Could not find header in VPNGate response');
    }

    // Parse header to get column indices
    final headerLine = lines[headerIndex].substring(1); // Remove the # prefix
    final List<String> headers = headerLine.split(',');
    
    final Map<String, int> columnIndex = {};
    for (int i = 0; i < headers.length; i++) {
      columnIndex[headers[i].trim()] = i;
    }

    // Parse data rows
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      try {
        final List<String> values = _parseCsvLine(line);
        if (values.length < headers.length) continue;

        final server = VpnGateServer(
          hostName: _getValue(values, columnIndex, 'HostName') ?? '',
          ip: _getValue(values, columnIndex, 'IP') ?? '',
          countryLong: _getValue(values, columnIndex, 'CountryLong') ?? '',
          l2tpSupported: _getValue(values, columnIndex, 'L2TP'),
          ping: _getIntValue(values, columnIndex, 'Ping'),
          speed: _getIntValue(values, columnIndex, 'Speed'),
          score: _getIntValue(values, columnIndex, 'Score'),
        );

        // Only add servers that support L2TP
        if (server.hasL2tpSupport) {
          servers.add(server);
        }
      } catch (e) {
        // Skip malformed rows
        continue;
      }
    }

    return servers;
  }

  /// Parse a CSV line handling quoted fields
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

  /// Get string value from CSV row
  static String? _getValue(List<String> values, Map<String, int> columnIndex, String columnName) {
    final int? index = columnIndex[columnName];
    if (index == null || index >= values.length) return null;
    final String value = values[index].trim();
    return value.isEmpty ? null : value;
  }

  /// Get integer value from CSV row
  static int? _getIntValue(List<String> values, Map<String, int> columnIndex, String columnName) {
    final String? value = _getValue(values, columnIndex, columnName);
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// Get the best L2TP server based on ping and speed
  static VpnGateServer? getBestL2tpServer(List<VpnGateServer> servers) {
    if (servers.isEmpty) return null;

    // Filter servers with valid metrics
    final validServers = servers.where((s) => 
      s.ping != null && s.ping! > 0 && 
      s.speed != null && s.speed! > 0
    ).toList();

    if (validServers.isEmpty) {
      // Return first server if no valid metrics
      return servers.first;
    }

    // Sort by ping (lower is better), then by speed (higher is better)
    validServers.sort((a, b) {
      final int pingCompare = a.ping!.compareTo(b.ping!);
      if (pingCompare != 0) return pingCompare;
      return b.speed!.compareTo(a.speed!);
    });

    return validServers.first;
  }

  /// Get servers by country
  static List<VpnGateServer> getServersByCountry(List<VpnGateServer> servers, String country) {
    return servers.where((s) => 
      s.countryLong.toLowerCase().contains(country.toLowerCase())
    ).toList();
  }
}
