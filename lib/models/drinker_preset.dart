import 'dart:convert';

class DrinkerPreset {
  final String id;
  final String name;
  final int drainSec;
  final int fillSec;
  final int pauseSec;
  final int drainSpeed;
  final int fillSpeed;
  final double pumpLpm;
  final int? targetMl;

  DrinkerPreset({
    required this.id,
    required this.name,
    required this.drainSec,
    required this.fillSec,
    required this.pauseSec,
    required this.drainSpeed,
    required this.fillSpeed,
    required this.pumpLpm,
    this.targetMl,
  });

  int get volumeMl => targetMl ?? (calculatedLiters * 1000).round();

  double get calculatedLiters =>
      targetMl != null ? (targetMl! / 1000.0) : (fillSec / 60.0) * pumpLpm;

  String get volumeChipLabel {
    final ml = volumeMl;
    if (ml >= 1000) {
      final liters = ml / 1000.0;
      final formatted = liters.toStringAsFixed(ml % 100 == 0 ? (ml % 1000 == 0 ? 0 : 1) : 2);
      return '${formatted}L';
    } else {
      return '${ml}mL';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'drainSec': drainSec,
        'fillSec': fillSec,
        'pauseSec': pauseSec,
        'drainSpeed': drainSpeed,
        'fillSpeed': fillSpeed,
        'pumpLpm': pumpLpm,
        'targetMl': volumeMl,
      };

  factory DrinkerPreset.fromJson(Map<String, dynamic> json) => DrinkerPreset(
        id: json['id'] ?? 'preset_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] ?? 'Preset',
        drainSec: (json['drainSec'] as num?)?.toInt() ?? 30,
        fillSec: (json['fillSec'] as num?)?.toInt() ?? 40,
        pauseSec: (json['pauseSec'] as num?)?.toInt() ?? 2,
        drainSpeed: (json['drainSpeed'] as num?)?.toInt() ?? 80,
        fillSpeed: (json['fillSpeed'] as num?)?.toInt() ?? 80,
        pumpLpm: (json['pumpLpm'] as num?)?.toDouble() ?? 3.0,
        targetMl: (json['targetMl'] as num?)?.toInt(),
      );

  static List<DrinkerPreset> defaultPresets() => [
        DrinkerPreset(
          id: 'preset_1l',
          name: '1 Liter Refill (1.0L)',
          drainSec: 20,
          fillSec: 20,
          pauseSec: 2,
          drainSpeed: 80,
          fillSpeed: 80,
          pumpLpm: 3.0,
          targetMl: 1000,
        ),
        DrinkerPreset(
          id: 'preset_std',
          name: 'Standard Refill (1.5L)',
          drainSec: 30,
          fillSec: 40,
          pauseSec: 2,
          drainSpeed: 80,
          fillSpeed: 80,
          pumpLpm: 3.0,
          targetMl: 1500,
        ),
        DrinkerPreset(
          id: 'preset_light',
          name: 'Quick Refresh (0.5L)',
          drainSec: 15,
          fillSec: 15,
          pauseSec: 2,
          drainSpeed: 70,
          fillSpeed: 70,
          pumpLpm: 3.0,
          targetMl: 500,
        ),
        DrinkerPreset(
          id: 'preset_deep',
          name: 'Deep Clean & Flush (3.0L)',
          drainSec: 45,
          fillSec: 60,
          pauseSec: 2,
          drainSpeed: 90,
          fillSpeed: 90,
          pumpLpm: 3.0,
          targetMl: 3000,
        ),
      ];

  static String encodeList(List<DrinkerPreset> presets) =>
      jsonEncode(presets.map((p) => p.toJson()).toList());

  static List<DrinkerPreset> decodeList(String rawJson) {
    try {
      final List<dynamic> decoded = jsonDecode(rawJson);
      return decoded.map((e) => DrinkerPreset.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return defaultPresets();
    }
  }

  /// Computes the required drain seconds to completely evacuate a given volume in mL,
  /// based on pump flow rate (LPM), motor speed %, and safety buffer seconds.
  static int computeSmartDrainSec({
    required int volumeMl,
    required double pumpLpm,
    required int drainSpeedPercent,
    int safetyBufferSec = 2,
  }) {
    final effectiveMlPerSec =
        (pumpLpm * (drainSpeedPercent / 100.0) * 1000.0) / 60.0;
    if (effectiveMlPerSec <= 0) return 30;
    final drainSec = (volumeMl / effectiveMlPerSec).ceil() + safetyBufferSec;
    return drainSec.clamp(5, 300);
  }
}

class LastRefillRecord {
  final DateTime timestamp;
  final int volumeMl;
  final double liters;
  final String presetName;
  final String presetChipLabel;
  final int drainSec;
  final int fillSec;

  LastRefillRecord({
    required this.timestamp,
    required this.volumeMl,
    required this.liters,
    required this.presetName,
    required this.presetChipLabel,
    required this.drainSec,
    required this.fillSec,
  });

  /// Computes the drain seconds needed to evacuate this recorded refill volume.
  int computeSmartDrainSec({
    required double pumpLpm,
    required int drainSpeedPercent,
    int safetyBufferSec = 2,
  }) {
    return DrinkerPreset.computeSmartDrainSec(
      volumeMl: volumeMl,
      pumpLpm: pumpLpm,
      drainSpeedPercent: drainSpeedPercent,
      safetyBufferSec: safetyBufferSec,
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
      final m = timestamp.minute.toString().padLeft(2, '0');
      final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
      return '${diff.inHours}h ago ($h:$m $ampm)';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final h = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final m = timestamp.minute.toString().padLeft(2, '0');
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '${months[timestamp.month - 1]} ${timestamp.day}, $h:$m $ampm';
  }

  String get shortTimeStr {
    final h = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final m = timestamp.minute.toString().padLeft(2, '0');
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'volumeMl': volumeMl,
        'liters': liters,
        'presetName': presetName,
        'presetChipLabel': presetChipLabel,
        'drainSec': drainSec,
        'fillSec': fillSec,
      };

  factory LastRefillRecord.fromJson(Map<String, dynamic> json) =>
      LastRefillRecord(
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
        volumeMl: (json['volumeMl'] as num?)?.toInt() ?? 1000,
        liters: (json['liters'] as num?)?.toDouble() ?? 1.0,
        presetName: json['presetName'] ?? 'Standard Drinker',
        presetChipLabel: json['presetChipLabel'] ?? '1.0L',
        drainSec: (json['drainSec'] as num?)?.toInt() ?? 30,
        fillSec: (json['fillSec'] as num?)?.toInt() ?? 40,
      );
}
