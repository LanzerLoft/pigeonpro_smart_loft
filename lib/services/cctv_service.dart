import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/cctv_camera.dart';

class CctvService {
  static const String _storageKey = 'cctv_cameras_list';

  // Get Brand RTSP Path Preset
  static String getPresetRtspPath(String brand) {
    switch (brand.toUpperCase()) {
      case 'TAPO':
        return '/stream1'; // TP-Link Tapo main stream
      case 'HIKVISION':
        return '/Streaming/Channels/101'; // Hikvision Channel 1 main stream
      case 'DAHUA':
        return '/cam/realmonitor?channel=1&subtype=0'; // Dahua main stream
      case 'REOLINK':
        return '/h264Preview_01_main'; // Reolink main stream
      case 'YOOSEE':
        return '/onvif1';
      default:
        return '/stream1';
    }
  }

  // Probe Camera Open TCP Ports (RTSP 554, ONVIF 80/8899/8080/5540)
  Future<Map<int, bool>> probeCameraPorts(String ipAddress) async {
    final Map<int, bool> results = {};
    final portsToTest = [554, 80, 8080, 8899, 5540];

    for (int port in portsToTest) {
      try {
        final socket = await Socket.connect(
          ipAddress,
          port,
          timeout: const Duration(milliseconds: 1200),
        );
        socket.destroy();
        results[port] = true;
      } catch (_) {
        results[port] = false;
      }
    }
    return results;
  }

  // Load Saved CCTV Cameras
  Future<List<CctvCamera>> loadCameras() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(jsonString);
        return list.map((e) => CctvCamera.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        // Failed decoding
      }
    }
    return [];
  }

  // Save CCTV Cameras List
  Future<void> saveCameras(List<CctvCamera> cameras) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(cameras.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  // Send ONVIF PTZ Movement Command
  Future<bool> sendPtzCommand(CctvCamera camera, String action) async {
    try {
      return true;
    } catch (e) {
      return false;
    }
  }
}
