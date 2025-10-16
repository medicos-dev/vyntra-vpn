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
  String? hostName;
  String? ip;
  String? country;
  int? score;
  int? ping;
  int? speed;
  bool? hasConfig;

  SampleServers({this.hostName, this.ip, this.country, this.score, this.ping, this.speed, this.hasConfig});

  SampleServers.fromJson(Map<String, dynamic> json) {
    hostName = json['hostName'] as String?;
    ip = json['ip'] as String?;
    country = json['country'] as String?;
    score = json['score'] as int?;
    ping = json['ping'] as int?;
    speed = json['speed'] as int?;
    hasConfig = json['hasConfig'] as bool?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['hostName'] = hostName;
    data['ip'] = ip;
    data['country'] = country;
    data['score'] = score;
    data['ping'] = ping;
    data['speed'] = speed;
    data['hasConfig'] = hasConfig;
    return data;
  }
}

class AllServers {
  String? hostName;
  String? ip;
  String? country;
  int? score;
  int? ping;
  int? speed;
  bool? hasConfig;
  String? ovpnBase64;

  AllServers({this.hostName, this.ip, this.country, this.score, this.ping, this.speed, this.hasConfig, this.ovpnBase64});

  AllServers.fromJson(Map<String, dynamic> json) {
    hostName = json['hostName'] as String?;
    ip = json['ip'] as String?;
    country = json['country'] as String?;
    score = json['score'] as int?;
    ping = json['ping'] as int?;
    speed = json['speed'] as int?;
    hasConfig = json['hasConfig'] as bool?;
    ovpnBase64 = json['ovpnBase64'] as String?;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['hostName'] = hostName;
    data['ip'] = ip;
    data['country'] = country;
    data['score'] = score;
    data['ping'] = ping;
    data['speed'] = speed;
    data['hasConfig'] = hasConfig;
    data['ovpnBase64'] = ovpnBase64;
    return data;
  }
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
    servers = json['servers'] as int?;
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
