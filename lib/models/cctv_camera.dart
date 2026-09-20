class CctvCamera {
  final String id;
  final String name;
  final String ipAddress;
  final int rtspPort;
  final int onvifPort;
  final String username;
  final String password;
  final String rtspPath;
  final String brand; // 'TAPO', 'HIKVISION', 'DAHUA', 'REOLINK', 'GENERIC'
  final bool isPtzSupported;

  CctvCamera({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.rtspPort = 554,
    this.onvifPort = 80,
    this.username = 'admin',
    this.password = '',
    this.rtspPath = '/stream1',
    this.brand = 'GENERIC',
    this.isPtzSupported = true,
  });

  // Construct full RTSP stream URL
  String get rtspUrl {
    final auth = (username.isNotEmpty)
        ? '$username:${Uri.encodeComponent(password)}@'
        : '';
    final path = rtspPath.startsWith('/') ? rtspPath : '/$rtspPath';
    return 'rtsp://$auth$ipAddress:$rtspPort$path';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ipAddress': ipAddress,
        'rtspPort': rtspPort,
        'onvifPort': onvifPort,
        'username': username,
        'password': password,
        'rtspPath': rtspPath,
        'brand': brand,
        'isPtzSupported': isPtzSupported,
      };

  factory CctvCamera.fromJson(Map<String, dynamic> json) => CctvCamera(
        id: json['id'] ?? '',
        name: json['name'] ?? 'IP Camera',
        ipAddress: json['ipAddress'] ?? '',
        rtspPort: json['rtspPort'] ?? 554,
        onvifPort: json['onvifPort'] ?? 80,
        username: json['username'] ?? '',
        password: json['password'] ?? '',
        rtspPath: json['rtspPath'] ?? '/stream1',
        brand: json['brand'] ?? 'GENERIC',
        isPtzSupported: json['isPtzSupported'] ?? true,
      );
}
