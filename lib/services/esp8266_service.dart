import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/relay_status.dart';

class Esp8266Service {
  static const String defaultProvisioningUrl = 'http://192.168.4.1';
  static const String defaultLocalUrl = 'http://pigeonpro-portal.local';

  // Smart status fetch
  Future<EspStatus?> fetchStatus(String baseUrl) async {
    EspStatus? status = await _getRawStatus(baseUrl);
    if (status != null) return status;

    if (baseUrl != defaultLocalUrl) {
      status = await _getRawStatus(defaultLocalUrl);
      if (status != null) return status;
    }

    if (baseUrl != defaultProvisioningUrl) {
      status = await _getRawStatus(defaultProvisioningUrl);
      if (status != null) return status;
    }

    return null;
  }

  Future<EspStatus?> _getRawStatus(String url) async {
    try {
      final response = await http
          .get(Uri.parse('$url/api/status'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return EspStatus.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      // Endpoint unreachable
    }
    return null;
  }

  // Toggle single relay
  Future<bool> toggleRelay(String baseUrl, int relayId, bool state) async {
    try {
      final stateVal = state ? 1 : 0;
      final response = await http
          .get(Uri.parse('$baseUrl/api/toggle?id=$relayId&state=$stateVal'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Master turn all relays ON or OFF
  Future<bool> setAllRelays(String baseUrl, bool turnOn) async {
    try {
      final stateParam = turnOn ? 'on' : 'off';
      final response = await http
          .get(Uri.parse('$baseUrl/api/all?state=$stateParam'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Set countdown timer for a relay
  Future<bool> setTimer(
      String baseUrl, int relayId, int seconds, bool targetState) async {
    try {
      final targetVal = targetState ? 1 : 0;
      final response = await http
          .get(Uri.parse(
              '$baseUrl/api/timer?id=$relayId&duration=$seconds&target=$targetVal'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Configure inching pulse mode
  Future<bool> setInching(
      String baseUrl, int relayId, bool enable, int durationSec) async {
    try {
      final enableVal = enable ? 1 : 0;
      final response = await http
          .get(Uri.parse(
              '$baseUrl/api/inching?id=$relayId&enable=$enableVal&duration=$durationSec'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Clear RFID Scan history/tag
  Future<bool> clearRfidScan(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/rfid/clear'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // In-App Wi-Fi Scanner (calls GET /api/wifi/scan)
  Future<List<WifiNetwork>> scanWifi(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/wifi/scan'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['networks'] as List<dynamic>?)
                ?.map((e) => WifiNetwork.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        return list;
      }
    } catch (e) {
      // Failed to scan
    }
    return [];
  }

  // Submit Wi-Fi credentials to ESP8266 (POST /api/wifi/save)
  Future<bool> saveWifi(String baseUrl, String ssid, String pass) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/wifi/save'),
        body: {'ssid': ssid, 'pass': pass},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Reset ESP8266 Wi-Fi settings (POST /api/wifi/reset)
  Future<bool> resetWifi(String baseUrl) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/api/wifi/reset'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Control L298N Submersible Pump (GET /api/pump?state=1&speed=80&dir=fwd)
  Future<bool> setPumpState(String baseUrl, bool state, int speed, {String direction = 'fwd'}) async {
    try {
      final stateVal = state ? 1 : 0;
      final response = await http
          .get(Uri.parse('$baseUrl/api/pump?state=$stateVal&speed=$speed&dir=$direction'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Set Pump Countdown Timer (GET /api/pump/timer?duration=300&target=0)
  Future<bool> setPumpTimer(String baseUrl, int seconds, bool targetState, {int speed = 80, String direction = 'fwd'}) async {
    try {
      final targetVal = targetState ? 1 : 0;
      final response = await http
          .get(Uri.parse('$baseUrl/api/pump/timer?duration=$seconds&target=$targetVal&speed=$speed&dir=$direction'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Control L298N Submersible Pump 2 (OUT3 Positive, OUT4 Negative) (GET /api/pump2?state=1&speed=80&dir=fwd)
  Future<bool> setPump2State(String baseUrl, bool state, int speed, {String direction = 'fwd'}) async {
    try {
      final stateVal = state ? 1 : 0;
      final response = await http
          .get(Uri.parse('$baseUrl/api/pump2?state=$stateVal&speed=$speed&dir=$direction'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Set Pump 2 Countdown Timer (GET /api/pump2/timer?duration=300&target=0)
  Future<bool> setPump2Timer(String baseUrl, int seconds, bool targetState, {int speed = 80, String direction = 'fwd'}) async {
    try {
      final targetVal = targetState ? 1 : 0;
      final response = await http
          .get(Uri.parse('$baseUrl/api/pump2/timer?duration=$seconds&target=$targetVal&speed=$speed&dir=$direction'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Trigger 2-Stage Automated Drinker Flush & Refill Cycle (GET /api/drinker/autocycle?drainSec=30&fillSec=40&drainSpeed=80&fillSpeed=80&pauseSec=2)
  Future<bool> triggerDrinkerAutoCycle(
    String baseUrl,
    int drainSec,
    int fillSec, {
    int drainSpeed = 80,
    int fillSpeed = 80,
    int pauseSec = 2,
    int speed = 80,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(
              '$baseUrl/api/drinker/autocycle?drainSec=$drainSec&fillSec=$fillSec&drainSpeed=$drainSpeed&fillSpeed=$fillSpeed&pauseSec=$pauseSec&speed=$speed'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Stop 2-Stage Automated Drinker Flush & Refill Cycle (GET /api/drinker/autocycle?stop=1)
  Future<bool> stopDrinkerAutoCycle(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/drinker/autocycle?stop=1'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Fetch Hardware Persistent Schedules (GET /api/schedules)
  Future<HardwareScheduleData?> fetchHardwareSchedules(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/schedules'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return HardwareScheduleData.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      // Endpoint unreachable
    }
    return null;
  }

  // Save / Update Hardware Schedule (GET /api/schedules/set?id=0&target=1&hour=7...)
  Future<HardwareScheduleData?> setHardwareSchedule(String baseUrl, HardwareSchedule schedule) async {
    try {
      final stateVal = schedule.target == 7 ? schedule.rawState : (schedule.targetState ? 1 : 0);
      final enabledVal = schedule.enabled ? 1 : 0;
      final url = '$baseUrl/api/schedules/set?id=${schedule.id}&target=${schedule.target}&hour=${schedule.hour}&minute=${schedule.minute}&state=$stateVal&duration=${schedule.durationSec}&speed=${schedule.speedPercent}&days=${schedule.daysMask}&enabled=$enabledVal';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return HardwareScheduleData.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      // Endpoint unreachable
    }
    return null;
  }

  // Delete / Disable Hardware Schedule (GET /api/schedules/delete?id=0)
  Future<HardwareScheduleData?> deleteHardwareSchedule(String baseUrl, int scheduleId) async {
    try {
      final setClearUrl = '$baseUrl/api/schedules/set?id=$scheduleId&target=0&hour=0&minute=0&state=0&duration=0&speed=0&days=0&enabled=0';
      await http.get(Uri.parse(setClearUrl)).timeout(const Duration(seconds: 3));

      final response = await http
          .get(Uri.parse('$baseUrl/api/schedules/delete?id=$scheduleId'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return HardwareScheduleData.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      // Endpoint unreachable
    }
    return fetchHardwareSchedules(baseUrl);
  }

  // Sync Phone Time to ESP8266 Board Clock (GET /api/time/sync?epoch=...&tz=28800)
  Future<bool> syncPhoneTime(String baseUrl) async {
    try {
      final nowEpoch = (DateTime.now().millisecondsSinceEpoch / 1000).round();
      final timeZoneOffset = DateTime.now().timeZoneOffset.inSeconds;
      final response = await http
          .get(Uri.parse('$baseUrl/api/time/sync?epoch=$nowEpoch&tz=$timeZoneOffset'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
