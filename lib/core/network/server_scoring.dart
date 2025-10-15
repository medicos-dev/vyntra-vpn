import '../models/vpngate_server.dart';

class ServerScoring {
  static List<VpnGateServer> sortBest(List<VpnGateServer> servers) {
    final List<VpnGateServer> copy = List<VpnGateServer>.from(servers);
    copy.sort((a, b) {
      // Lower ping preferred, higher speed preferred, higher score preferred
      final int pingCmp = (a.pingMs).compareTo(b.pingMs);
      if (pingCmp != 0) return pingCmp;
      final int speedCmp = (b.speedBps).compareTo(a.speedBps);
      if (speedCmp != 0) return speedCmp;
      return (b.score).compareTo(a.score);
    });
    return copy;
  }
}


