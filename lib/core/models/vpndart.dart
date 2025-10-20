import '../constants/server_constants.dart';

class VpnDart {
  String? timestamp;
  int? totalServers;
  Services? services;
  Recommendations? recommendations;
  String? developer;

  VpnDart({this.timestamp, this.totalServers, this.services, this.recommendations, this.developer});

  VpnDart.fromJson(Map<String, dynamic> json) {
    timestamp = json['timestamp'] as String?;
    totalServers = json['totalServers'] as int?;
    services = json['services'] != null ? Services.fromJson(json['services'] as Map<String, dynamic>) : null;
    recommendations = json['recommendations'] != null ? Recommendations.fromJson(json['recommendations'] as Map<String, dynamic>) : null;
    developer = json['developer'] as String?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['timestamp'] = timestamp;
    data['totalServers'] = totalServers;
    if (services != null) data['services'] = services!.toJson();
    if (recommendations != null) data['recommendations'] = recommendations!.toJson();
    data['developer'] = developer;
    return data;
  }
}

class Services {
  Vpngate? vpngate;
  CloudflareWarp? cloudflareWarp;
  CloudflareWarp? outlineVpn;

  Services({this.vpngate, this.cloudflareWarp, this.outlineVpn});

  Services.fromJson(Map<String, dynamic> json) {
    vpngate = json['vpngate'] != null ? Vpngate.fromJson(json['vpngate'] as Map<String, dynamic>) : null;
    cloudflareWarp = json['cloudflareWarp'] != null ? CloudflareWarp.fromJson(json['cloudflareWarp'] as Map<String, dynamic>) : null;
    outlineVpn = json['outlineVpn'] != null ? CloudflareWarp.fromJson(json['outlineVpn'] as Map<String, dynamic>) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (vpngate != null) data['vpngate'] = vpngate!.toJson();
    if (cloudflareWarp != null) data['cloudflareWarp'] = cloudflareWarp!.toJson();
    if (outlineVpn != null) data['outlineVpn'] = outlineVpn!.toJson();
    return data;
  }
}

class Vpngate {
  String? name;
  String? type;
  int? servers;
  String? description;
  String? endpoint;
  List<String>? features;
  List<SampleServers>? sampleServers;
  List<AllServers>? allServers;

  Vpngate({this.name, this.type, this.servers, this.description, this.endpoint, this.features, this.sampleServers, this.allServers});

  Vpngate.fromJson(Map<String, dynamic> json) {
    name = json['name'] as String?;
    type = json['type'] as String?;
    servers = json['servers'] as int?;
    description = json['description'] as String?;
    endpoint = json['endpoint'] as String?;
    features = (json['features'] as List<dynamic>?)?.map((e) => e.toString()).toList();
    if (json['sampleServers'] != null) {
      sampleServers = <SampleServers>[];
      for (final v in (json['sampleServers'] as List<dynamic>)) {
        sampleServers!.add(SampleServers.fromJson(v as Map<String, dynamic>));
      }
    }
    if (json['allServers'] != null) {
      allServers = <AllServers>[];
      for (final v in (json['allServers'] as List<dynamic>)) {
        allServers!.add(AllServers.fromJson(v as Map<String, dynamic>));
      }
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['type'] = type;
    data['servers'] = servers;
    data['description'] = description;
    data['endpoint'] = endpoint;
    data['features'] = features;
    if (sampleServers != null) data['sampleServers'] = sampleServers!.map((v) => v.toJson()).toList();
    if (allServers != null) data['allServers'] = allServers!.map((v) => v.toJson()).toList();
    return data;
  }
}

class SampleServers {
  String? HostName;
  String? IP;
  String? CountryLong;
  int? Score;
  int? Ping;
  int? Speed;
  bool? HasConfig;

  SampleServers({this.HostName, this.IP, this.CountryLong, this.Score, this.Ping, this.Speed, this.HasConfig});

  SampleServers.fromJson(Map<String, dynamic> json) {
    HostName = json['HostName'] as String?;
    IP = json['IP'] as String?;
    CountryLong = json['CountryLong'] as String?;
    Score = (json['Score'] is String) ? int.tryParse(json['Score'] as String) : json['Score'] as int?;
    Ping = (json['Ping'] is String) ? int.tryParse(json['Ping'] as String) : json['Ping'] as int?;
    Speed = (json['Speed'] is String) ? int.tryParse(json['Speed'] as String) : json['Speed'] as int?;
    HasConfig = json['HasConfig'] as bool?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['HostName'] = HostName;
    data['IP'] = IP;
    data['CountryLong'] = CountryLong;
    data['Score'] = Score;
    data['Ping'] = Ping;
    data['Speed'] = Speed;
    data['HasConfig'] = HasConfig;
    return data;
  }
}

class AllServers {

  String? HostName;
  String? IP;
  String? CountryLong;
  int? Score;
  int? Ping;
  int? Speed;
  bool? HasConfig;
  String? OpenVPN_ConfigData_Base64;

  AllServers({this.HostName, this.IP, this.CountryLong, this.Score, this.Ping, this.Speed, this.HasConfig, this.OpenVPN_ConfigData_Base64});

  AllServers.fromJson(Map<String, dynamic> json) {
    HostName = json['HostName'] as String?;
    IP = json['IP'] as String?;
    CountryLong = json['CountryLong'] as String?;
    Score = (json['Score'] is String) ? int.tryParse(json['Score'] as String) : json['Score'] as int?;
    Ping = (json['Ping'] is String) ? int.tryParse(json['Ping'] as String) ?? ServerConstants.maxPing : json['Ping'] as int? ?? ServerConstants.maxPing;
    Speed = (json['Speed'] is String) ? int.tryParse(json['Speed'] as String) : json['Speed'] as int?;
    HasConfig = json['HasConfig'] as bool?;
    
    // Handle Base64 config with better validation
    final base64Config = json['OpenVPN_ConfigData_Base64'] as String?;
    if (base64Config != null && base64Config.isNotEmpty) {
      // Clean the Base64 string (remove any whitespace/newlines)
      final cleanBase64 = base64Config.trim().replaceAll(RegExp(r'\s+'), '');
      OpenVPN_ConfigData_Base64 = cleanBase64.isNotEmpty ? cleanBase64 : null;
    } else {
      OpenVPN_ConfigData_Base64 = null;
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['HostName'] = HostName;
    data['IP'] = IP;
    data['CountryLong'] = CountryLong;
    data['Score'] = Score;
    data['Ping'] = Ping;
    data['Speed'] = Speed;
    data['HasConfig'] = HasConfig;
    data['OpenVPN_ConfigData_Base64'] = OpenVPN_ConfigData_Base64;
    return data;
  }

  // Calculate intelligent score based on ping, speed, and protocol preference
  double get intelligentScore {
    if (Score != null && Score! > 0) return Score!.toDouble();
    
    // Calculate score based on ping (lower is better) and speed (higher is better)
    final pingScore = (Ping != null && Ping! > 0) ? (ServerConstants.pingScoreMultiplier / Ping!.clamp(1, 1000)) : 0.0;
    final speedScore = (Speed != null && Speed! > 0) ? (Speed! / ServerConstants.speedToMbpsDivisor) : 0.0; // Convert to Mbps
    
    // Protocol bonus: UDP gets higher priority (avoids TCP meltdown)
    final protocolBonus = hasUdpSupport ? ServerConstants.udpProtocolBonus : ServerConstants.tcpProtocolBonus;
    
    return (pingScore * ServerConstants.pingWeight + speedScore * ServerConstants.speedWeight) * ServerConstants.speedScoreMultiplier * protocolBonus;
  }

  // Check if server supports UDP (based on common VPNGate patterns)
  bool get hasUdpSupport {
    if (HostName == null) return true; // Default to UDP if unknown
    
    final hostname = HostName!.toLowerCase();
    
    // Explicit TCP indicators
    if (ServerConstants.tcpKeywords.any((keyword) => hostname.contains(keyword))) {
      return false;
    }
    
    // Explicit UDP indicators
    if (ServerConstants.udpKeywords.any((keyword) => hostname.contains(keyword))) {
      return true;
    }
    
    // Default to UDP for VPNGate servers (most support both, but UDP is preferred)
    return true;
  }

  // Check if server has valid OpenVPN config
  bool get hasValidConfig => 
      OpenVPN_ConfigData_Base64 != null && 
      OpenVPN_ConfigData_Base64!.isNotEmpty &&
      OpenVPN_ConfigData_Base64!.length > ServerConstants.minConfigLength; // Basic validation
}

class CloudflareWarp {
  String? name;
  String? type;
  int? servers;
  String? description;
  String? endpoint;
  List<String>? features;

  CloudflareWarp({this.name, this.type, this.servers, this.description, this.endpoint, this.features});

  CloudflareWarp.fromJson(Map<String, dynamic> json) {
    name = json['name'] as String?;
    type = json['type'] as String?;
    servers = (json['servers'] is String) ? int.tryParse(json['servers'] as String) : json['servers'] as int?;
    description = json['description'] as String?;
    endpoint = json['endpoint'] as String?;
    features = (json['features'] as List<dynamic>?)?.map((e) => e.toString()).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['type'] = type;
    data['servers'] = servers;
    data['description'] = description;
    data['endpoint'] = endpoint;
    data['features'] = features;
    return data;
  }
}

class Recommendations {
  String? fastest;
  String? mostSecure;
  String? mostServers;
  String? bestForMobile;

  Recommendations({this.fastest, this.mostSecure, this.mostServers, this.bestForMobile});

  Recommendations.fromJson(Map<String, dynamic> json) {
    fastest = json['fastest'] as String?;
    mostSecure = json['mostSecure'] as String?;
    mostServers = json['mostServers'] as String?;
    bestForMobile = json['bestForMobile'] as String?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['fastest'] = fastest;
    data['mostSecure'] = mostSecure;
    data['mostServers'] = mostServers;
    data['bestForMobile'] = bestForMobile;
    return data;
  }
}
