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

  double get calculatedLiters => (fillSec / 60.0) * pumpLpm;

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
}
