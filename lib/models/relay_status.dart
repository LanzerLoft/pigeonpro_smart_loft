class EspStatus {
  final String ip;
  final String ssid;
  final int rssi;
  final int uptime;
  final String mode;
  final String? currentTime;
  final List<bool> relays;
  final List<TimerInfo> timers;
  final List<InchingInfo> inching;
  final RfidStatus? rfid;
  final PumpStatus? pump;
  final PumpStatus? pump2;
  final AutoCycleStatus? autoCycle;

  EspStatus({
    required this.ip,
    required this.ssid,
    required this.rssi,
    required this.uptime,
    required this.mode,
    this.currentTime,
    required this.relays,
    required this.timers,
    required this.inching,
    this.rfid,
    this.pump,
    this.pump2,
    this.autoCycle,
  });

  factory EspStatus.fromJson(Map<String, dynamic> json) {
    return EspStatus(
      ip: json['ip'] ?? 'N/A',
      ssid: json['ssid'] ?? 'N/A',
      rssi: json['rssi'] ?? 0,
      uptime: json['uptime'] ?? 0,
      mode: json['mode'] ?? 'UNKNOWN',
      currentTime: json['currentTime'],
      relays: (json['relays'] as List<dynamic>?)?.map((e) => e as bool).toList() ?? [],
      timers: (json['timers'] as List<dynamic>?)
              ?.map((e) => TimerInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      inching: (json['inching'] as List<dynamic>?)
              ?.map((e) => InchingInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      rfid: json['rfid'] != null ? RfidStatus.fromJson(json['rfid'] as Map<String, dynamic>) : null,
      pump: json['pump'] != null ? PumpStatus.fromJson(json['pump'] as Map<String, dynamic>) : null,
      pump2: json['pump2'] != null ? PumpStatus.fromJson(json['pump2'] as Map<String, dynamic>) : null,
      autoCycle: json['autocycle'] != null ? AutoCycleStatus.fromJson(json['autocycle'] as Map<String, dynamic>) : null,
    );
  }
}

class TimerInfo {
  final bool active;
  final int remaining;
  final bool targetState;

  TimerInfo({
    required this.active,
    required this.remaining,
    required this.targetState,
  });

  factory TimerInfo.fromJson(Map<String, dynamic> json) {
    return TimerInfo(
      active: json['active'] ?? false,
      remaining: json['remaining'] ?? 0,
      targetState: json['targetState'] ?? false,
    );
  }
}

class InchingInfo {
  final bool enabled;
  final int durationSec;

  InchingInfo({
    required this.enabled,
    required this.durationSec,
  });

  factory InchingInfo.fromJson(Map<String, dynamic> json) {
    return InchingInfo(
      enabled: json['enabled'] ?? false,
      durationSec: json['durationSec'] ?? 2,
    );
  }
}

class RfidStatus {
  final String tagHex;
  final String tagDec;
  final int scans;
  final int secondsAgo;

  RfidStatus({
    required this.tagHex,
    required this.tagDec,
    required this.scans,
    required this.secondsAgo,
  });

  factory RfidStatus.fromJson(Map<String, dynamic> json) {
    return RfidStatus(
      tagHex: json['tagHex'] ?? '',
      tagDec: json['tagDec'] ?? '',
      scans: json['scans'] ?? 0,
      secondsAgo: json['secondsAgo'] ?? 0,
    );
  }
}

class ScheduledTask {
  final String id;
  final int channel;
  final String scheduleType; // 'ONCE' or 'WEEKLY'
  final DateTime? targetDateTime;
  final List<bool> recurringDays; // [Sun, Mon, Tue, Wed, Thu, Fri, Sat]
  final int hour;
  final int minute;
  final bool targetState; // true = Turn ON, false = Turn OFF
  bool enabled;

  ScheduledTask({
    required this.id,
    required this.channel,
    required this.scheduleType,
    this.targetDateTime,
    required this.recurringDays,
    required this.hour,
    required this.minute,
    required this.targetState,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel,
        'scheduleType': scheduleType,
        'targetDateTime': targetDateTime?.toIso8601String(),
        'recurringDays': recurringDays,
        'hour': hour,
        'minute': minute,
        'targetState': targetState,
        'enabled': enabled,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> rawJson) => ScheduledTask(
        id: rawJson['id'] ?? '',
        channel: rawJson['channel'] ?? 1,
        scheduleType: rawJson['scheduleType'] ?? 'ONCE',
        targetDateTime: rawJson['targetDateTime'] != null ? DateTime.parse(rawJson['targetDateTime']) : null,
        recurringDays: (rawJson['recurringDays'] as List<dynamic>?)?.map((e) => e as bool).toList() ?? [false, false, false, false, false, false, false],
        hour: rawJson['hour'] ?? 0,
        minute: rawJson['minute'] ?? 0,
        targetState: rawJson['targetState'] ?? true,
        enabled: rawJson['enabled'] ?? true,
      );
}

class WifiNetwork {
  final String ssid;
  final int rssi;

  WifiNetwork({
    required this.ssid,
    required this.rssi,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] ?? '',
      rssi: json['rssi'] ?? 0,
    );
  }
}

class PumpStatus {
  final bool active;
  final String direction;
  final int speed;
  final int pwm;
  final TimerInfo? timer;

  PumpStatus({
    required this.active,
    required this.direction,
    required this.speed,
    required this.pwm,
    this.timer,
  });

  factory PumpStatus.fromJson(Map<String, dynamic> json) {
    return PumpStatus(
      active: json['active'] ?? false,
      direction: json['direction'] ?? 'fwd',
      speed: json['speed'] ?? 0,
      pwm: json['pwm'] ?? 0,
      timer: json['timer'] != null ? TimerInfo.fromJson(json['timer'] as Map<String, dynamic>) : null,
    );
  }
}

class AutoCycleStatus {
  final bool active;
  final int phase; // 0 = idle, 1 = stage 1 draining (pump 1), 2 = settle pause, 3 = stage 2 filling (pump 2)
  final int remaining;
  final int drainSec;
  final int fillSec;
  final int drainSpeed;
  final int fillSpeed;
  final int pauseSec;
  final int speed;

  AutoCycleStatus({
    required this.active,
    required this.phase,
    required this.remaining,
    required this.drainSec,
    required this.fillSec,
    required this.drainSpeed,
    required this.fillSpeed,
    required this.pauseSec,
    required this.speed,
  });

  factory AutoCycleStatus.fromJson(Map<String, dynamic> json) {
    return AutoCycleStatus(
      active: json['active'] ?? false,
      phase: json['phase'] ?? 0,
      remaining: json['remaining'] ?? 0,
      drainSec: json['drainSec'] ?? 30,
      fillSec: json['fillSec'] ?? 40,
      drainSpeed: json['drainSpeed'] ?? json['speed'] ?? 80,
      fillSpeed: json['fillSpeed'] ?? json['speed'] ?? 80,
      pauseSec: json['pauseSec'] ?? 2,
      speed: json['speed'] ?? 80,
    );
  }
}

class HardwareSchedule {
  final int id;
  final int target; // 1..4 = Relay 1..4, 5 = Water Pump
  final int hour;
  final int minute;
  final bool targetState;
  final int rawState;
  final int durationSec;
  final int speedPercent;
  final int daysMask; // Bitmask: Bit 0=Sun..Bit 6=Sat
  final bool enabled;

  HardwareSchedule({
    required this.id,
    required this.target,
    required this.hour,
    required this.minute,
    required this.targetState,
    this.rawState = 1,
    required this.durationSec,
    required this.speedPercent,
    required this.daysMask,
    required this.enabled,
  });

  factory HardwareSchedule.fromJson(Map<String, dynamic> json) {
    int parseNum(dynamic val, int defaultVal) {
      if (val is int) return val;
      if (val is double) return val.toInt();
      if (val is String) return int.tryParse(val) ?? defaultVal;
      return defaultVal;
    }

    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is int) return val > 0;
      if (val is String) return val.toLowerCase() == 'true' || (int.tryParse(val) ?? 0) > 0;
      return false;
    }

    final rawStateVal = parseNum(json['state'], 1);

    return HardwareSchedule(
      id: parseNum(json['id'], 0),
      target: parseNum(json['target'], 1),
      hour: parseNum(json['hour'], 0),
      minute: parseNum(json['minute'], 0),
      targetState: parseBool(json['state']),
      rawState: rawStateVal,
      durationSec: parseNum(json['duration'], 0),
      speedPercent: parseNum(json['speed'], 80),
      daysMask: parseNum(json['days'], 127),
      enabled: parseBool(json['enabled']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'target': target,
        'hour': hour,
        'minute': minute,
        'state': target == 7 ? rawState : (targetState ? 1 : 0),
        'duration': durationSec,
        'speed': speedPercent,
        'days': daysMask,
        'enabled': enabled ? 1 : 0,
      };

  List<bool> get recurringDays {
    return List.generate(7, (i) => (daysMask & (1 << i)) != 0);
  }
}

class HardwareScheduleData {
  final String currentTime;
  final int epoch;
  final int tzOffset;
  final List<HardwareSchedule> schedules;

  HardwareScheduleData({
    required this.currentTime,
    required this.epoch,
    required this.tzOffset,
    required this.schedules,
  });

  factory HardwareScheduleData.fromJson(Map<String, dynamic> json) {
    return HardwareScheduleData(
      currentTime: json['currentTime'] ?? '',
      epoch: json['epoch'] ?? 0,
      tzOffset: json['tzOffset'] ?? 28800,
      schedules: (json['schedules'] as List<dynamic>?)
              ?.map((e) => HardwareSchedule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class WifiSaveResult {
  final bool success;
  final String? ip;
  final String? ssid;
  final String? error;

  WifiSaveResult({
    required this.success,
    this.ip,
    this.ssid,
    this.error,
  });

  factory WifiSaveResult.success({String? ip, String? ssid}) {
    return WifiSaveResult(success: true, ip: ip, ssid: ssid);
  }

  factory WifiSaveResult.failure(String error) {
    return WifiSaveResult(success: false, error: error);
  }
}
