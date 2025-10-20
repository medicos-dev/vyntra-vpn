import 'dart:developer';
import 'package:http/http.dart';
import '../models/vpndart.dart';

class APIs {
  static Future<List<AllServers>> getVPNServers() async {
    final List<AllServers> vpnList = [];
    try {
      final res = await get(Uri.parse('http://www.vpngate.net/api/iphone/'));
      final csvString = res.body.split('#')[1].replaceAll('*', '');

      // Use custom CSV parser to handle double comma issue
      List<List<dynamic>> list = _parseCsvWithDoubleCommaFix(csvString);
      final header = list[0];

      print('🔍 CSV Header: ${header.join(', ')}');
      print('📊 Total fields in header: ${header.length}');

      for (int i = 1; i < list.length - 1; ++i) {
        final row = list[i];
        print('🔍 Row $i fields: ${row.length}');
        
        Map<String, dynamic> tempJson = {};
        for (int j = 0; j < header.length && j < row.length; ++j) {
          final fieldValue = row[j]?.toString() ?? '';
          tempJson.addAll({header[j].toString(): fieldValue});
          
          // Debug: Show Base64 field specifically
          if (header[j].toString() == 'OpenVPN_ConfigData_Base64') {
            print('🔍 Base64 field [$j]: ${fieldValue.length > 0 ? '${fieldValue.substring(0, 50)}...' : 'EMPTY'}');
          }
        }
        
        // Build AllServers using exact keys
        final server = AllServers.fromJson(tempJson);
        if (server.OpenVPN_ConfigData_Base64 != null && server.OpenVPN_ConfigData_Base64!.isNotEmpty) {
          vpnList.add(server);
          print('✅ Added server: ${server.HostName} (Base64 length: ${server.OpenVPN_ConfigData_Base64!.length})');
        } else {
          print('⚠️ Skipped server ${server.HostName}: No Base64 config');
        }
      }
    } catch (e) {
      log('\ngetVPNServersE: $e');
    }
    vpnList.shuffle();
    print('📊 Total servers with valid configs: ${vpnList.length}');
    return vpnList;
  }

  /// Custom CSV parser that handles double comma issue
  static List<List<dynamic>> _parseCsvWithDoubleCommaFix(String csvString) {
    final lines = csvString.split('\n');
    final result = <List<dynamic>>[];
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      final fields = _parseCsvLine(line);
      result.add(fields);
    }
    
    return result;
  }

  /// Parse a CSV line handling quoted fields and double commas
  static List<dynamic> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        final field = buffer.toString().trim();
        fields.add(field);
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    
    // Add the last field
    final lastField = buffer.toString().trim();
    fields.add(lastField);
    
    // Clean up trailing empty fields (double commas issue)
    while (fields.isNotEmpty && fields.last.isEmpty) {
      fields.removeLast();
    }
    
    // Ensure we have at least 15 fields (including the Base64 config)
    while (fields.length < 15) {
      fields.add('');
    }
    
    return fields;
  }
}
