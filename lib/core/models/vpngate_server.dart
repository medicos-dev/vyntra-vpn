class VpnGateServer {
  final String hostName;
  final String ip;
  final String country;
  final int score;
  final int pingMs;
  final int speedBps;
  final String ovpnBase64;

  const VpnGateServer({
    required this.hostName,
    required this.ip,
    required this.country,
    required this.score,
    required this.pingMs,
    required this.speedBps,
    required this.ovpnBase64,
  });
}


