/// Shared constants for VPN server models and scoring algorithms
class ServerConstants {
  // Connection and validation constants
  static const int maxPing = 9999;
  static const int minConfigLength = 100;
  
  // Scoring algorithm constants
  static const double speedToMbpsDivisor = 1000000.0;
  static const double pingScoreMultiplier = 1000.0;
  static const double speedScoreMultiplier = 1000.0;
  static const double pingWeight = 0.7;
  static const double speedWeight = 0.3;
  
  // Protocol preference constants
  static const double udpProtocolBonus = 1.5;
  static const double tcpProtocolBonus = 1.0;
  
  // Common port numbers for protocol detection
  static const List<int> tcpPorts = [80, 443];
  static const List<int> udpPorts = [500, 1194];
  
  // Protocol detection keywords
  static const List<String> tcpKeywords = ['tcp', '443', '80'];
  static const List<String> udpKeywords = ['udp', '1194', '500'];
}
