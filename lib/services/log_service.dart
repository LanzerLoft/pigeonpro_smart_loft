import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LogEntry {
  final String timestamp;
  final String title;
  final String details;
  final String type; // 'clean', 'pump', 'relay', 'rfid', 'schedule'

  LogEntry({
    required this.timestamp,
    required this.title,
    required this.details,
    this.type = 'info',
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'title': title,
        'details': details,
        'type': type,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: json['timestamp'] ?? '',
        title: json['title'] ?? '',
        details: json['details'] ?? '',
        type: json['type'] ?? 'info',
      );
}

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const String _storageKey = 'pigeonpro_session_logs';
  final List<LogEntry> _logs = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  Future<void> loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _logs.clear();
        _logs.addAll(decoded.map((item) => LogEntry.fromJson(item as Map<String, dynamic>)));
      }
    } catch (e) {
      // Failed to load logs
    }
  }

  Future<void> addLog(String title, String details, {String type = 'info'}) async {
    final now = DateTime.now();
    final hRaw = now.hour % 12;
    final h = hRaw == 0 ? 12 : hRaw;
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '${h.toString().padLeft(2, '0')}:$m:$s $period';

    final entry = LogEntry(
      timestamp: timeStr,
      title: title,
      details: details,
      type: type,
    );

    _logs.insert(0, entry);
    if (_logs.length > 100) {
      _logs.removeLast();
    }
    await _saveLogs();
  }

  Future<void> clearLogs() async {
    _logs.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> _saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_logs.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (e) {
      // Failed to save logs
    }
  }
}
