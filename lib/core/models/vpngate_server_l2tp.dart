class VpnGateServer {
  final String hostName;
  final String ip;
  final String countryLong;
  final String? l2tpSupported;
  final int? ping;
  final int? speed;
  final int? score;

  VpnGateServer({
    required this.hostName,
    required this.ip,
    required this.countryLong,
    this.l2tpSupported,
    this.ping,
    this.speed,
    this.score,
  });

  factory VpnGateServer.fromJson(Map<String, dynamic> json) {
    return VpnGateServer(
      hostName: json['HostName'] ?? '',
      ip: json['IP'] ?? '',
      countryLong: json['CountryLong'] ?? '',
      l2tpSupported: json['L2TP'] ?? json['L2tpSupported'],
      ping: json['Ping'] is String ? int.tryParse(json['Ping']) : json['Ping'],
      speed: json['Speed'] is String ? int.tryParse(json['Speed']) : json['Speed'],
      score: json['Score'] is String ? int.tryParse(json['Score']) : json['Score'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'HostName': hostName,
      'IP': ip,
      'CountryLong': countryLong,
      'L2TP': l2tpSupported,
      'Ping': ping,
      'Speed': speed,
      'Score': score,
    };
  }

  @override
  String toString() {
    return 'VpnGateServer(hostName: $hostName, ip: $ip, country: $countryLong, l2tp: $l2tpSupported)';
  }

  bool get hasL2tpSupport => l2tpSupported != null && l2tpSupported!.isNotEmpty;
}
