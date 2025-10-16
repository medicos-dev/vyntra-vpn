import 'dart:convert';
import 'dart:developer';
import 'package:csv/csv.dart';
import 'package:http/http.dart';
import '../models/vpndart.dart';

class APIs {
  static Future<List<AllServers>> getVPNServers() async {
    final List<AllServers> vpnList = [];
    try {
      final res = await get(Uri.parse('http://www.vpngate.net/api/iphone/'));
      final csvString = res.body.split('#')[1].replaceAll('*', '');

      List<List<dynamic>> list = const CsvToListConverter().convert(csvString);
      final header = list[0];

      for (int i = 1; i < list.length - 1; ++i) {
        Map<String, dynamic> tempJson = {};
        for (int j = 0; j < header.length; ++j) {
          tempJson.addAll({header[j].toString(): list[i][j]});
        }
        // Build AllServers using exact keys
        vpnList.add(AllServers.fromJson(tempJson));
      }
    } catch (e) {
      log('\ngetVPNServersE: $e');
    }
    vpnList.shuffle();
    return vpnList;
  }
}
