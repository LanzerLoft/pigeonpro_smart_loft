import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../models/drinker_preset.dart';
import '../services/esp8266_service.dart';
import '../services/log_service.dart';
import '../widgets/pump_card_widget.dart';
import '../widgets/drinker_schedule_widget.dart';
import '../widgets/log_session_widget.dart';
import '../widgets/cylinder_water_tank_widget.dart';
import 'pump_detail_screen.dart';

class PumpScreen extends StatefulWidget {
  final EspStatus? status;
  final String deviceUrl;
  final VoidCallback onRefresh;

  const PumpScreen({
    super.key,
    required this.status,
    required this.deviceUrl,
    required this.onRefresh,
  });

  @override
  State<PumpScreen> createState() => _PumpScreenState();
}

class _PumpScreenState extends State<PumpScreen>
    with TickerProviderStateMixin {
  final Esp8266Service _apiService = Esp8266Service();
  final GlobalKey<DrinkerScheduleWidgetState> _drinkerSchedKey =
      GlobalKey<DrinkerScheduleWidgetState>();
  String _pump1Name = 'Water Pump #1 (Main Drinker)';
  String _pump2Name = '3V Submersible Pump #2';

  late TextEditingController _drainSecController;
  late TextEditingController _fillSecController;
  late TextEditingController _lpmController;

  List<DrinkerPreset> _presets = DrinkerPreset.defaultPresets();
  String _activePresetId = 'preset_std';

  int _drainSpeed = 80;
  int _fillSpeed = 80;
  int _pauseSec = 2;
  double _pumpLpm = 3.0; // Pump Flow Rate rating in Liters per minute

  bool _wasCycleActive = false;
  bool _isCycleCompleted = false;
  LastRefillRecord? _lastRefill;
  int _cycleStartMl = 0;

  // Real-time water volume level in the drinker bowl (decreases on drain, increases on refill)
  int _currentWaterLevelMl = 1500;
  Timer? _manualDrainTrackingTimer;
  Timer? _manualRefillTrackingTimer;
  int _manualDrainElapsedSec = 0;
  int _manualRefillElapsedSec = 0;
  bool _isPump1ManuallyActive = false;
  bool _isPump2ManuallyActive = false;

  // Set Bowl to Empty drain animation
  AnimationController? _drainToEmptyAnimController;
  Animation<double>? _drainToEmptyProgressAnim;
  Animation<int>? _drainToEmptyMlAnim;
  bool _isDrainingToEmpty = false;

  DrinkerPreset get _activePreset {
    return _presets.firstWhere(
      (p) => p.id == _activePresetId,
      orElse: () => _presets.isNotEmpty
          ? _presets.first
          : DrinkerPreset.defaultPresets().first,
    );
  }

  @override
  void initState() {
    super.initState();
    _drainSecController = TextEditingController(text: '30');
    _fillSecController = TextEditingController(text: '40');
    _lpmController = TextEditingController(text: '3.0');
    _wasCycleActive = widget.status?.autoCycle?.active ?? false;
    _loadCustomPumpNamesAndSettings();
  }

  @override
  void didUpdateWidget(PumpScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.status?.autoCycle?.active ?? false;
    final isNowActive = widget.status?.autoCycle?.active ?? false;

    if (isNowActive) {
      _wasCycleActive = true;
      _isCycleCompleted = false;
    } else if (wasActive && !isNowActive && _wasCycleActive) {
      final completedPreset = _activePreset;
      final record = LastRefillRecord(
        timestamp: DateTime.now(),
        volumeMl: completedPreset.volumeMl,
        liters: completedPreset.calculatedLiters,
        presetName: completedPreset.name,
        presetChipLabel: completedPreset.volumeChipLabel,
        drainSec: completedPreset.drainSec,
        fillSec: completedPreset.fillSec,
      );
      _saveLastRefill(record);
      setState(() {
        _lastRefill = record;
        _currentWaterLevelMl = completedPreset.volumeMl;
        _isCycleCompleted = true;
        _wasCycleActive = false;
      });
      _saveCurrentWaterLevel();
    }

    // Monitor manual pump activity outside of auto-cycle
    final isAutoCycle = widget.status?.autoCycle?.active ?? false;
    final isPump1On = (widget.status?.pump?.active ?? false) &&
        !isAutoCycle &&
        !_isDrainingToEmpty;
    final isPump2On = (widget.status?.pump2?.active ?? false) && !isAutoCycle;

    if (isPump1On) {
      if (_manualDrainTrackingTimer == null || !_manualDrainTrackingTimer!.isActive) {
        _startManualDrainTracking();
      }
    } else {
      if (_manualDrainTrackingTimer != null) {
        _stopManualDrainTracking();
      }
    }

    if (isPump2On) {
      if (_manualRefillTrackingTimer == null || !_manualRefillTrackingTimer!.isActive) {
        _startManualRefillTracking();
      }
    } else {
      if (_manualRefillTrackingTimer != null) {
        _stopManualRefillTracking();
      }
    }
  }

  void _startManualDrainTracking() {
    _isPump1ManuallyActive = true;
    _manualDrainTrackingTimer?.cancel();
    _manualDrainTrackingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isAutoCycle = widget.status?.autoCycle?.active ?? false;
      final isPump1On =
          (_isPump1ManuallyActive || (widget.status?.pump?.active ?? false)) &&
              !isAutoCycle &&
              !_isDrainingToEmpty;
      if (!isPump1On) {
        _stopManualDrainTracking();
        return;
      }

      final speed = widget.status?.pump?.speed ?? _drainSpeed;
      final effectiveSpeed = speed < 10 ? 80 : speed;
      final mlPerSec = (_pumpLpm * (effectiveSpeed / 100.0) * 1000.0) / 60.0;
      final drainedMlThisSecond = mlPerSec.round();

      setState(() {
        _manualDrainElapsedSec++;
        _currentWaterLevelMl =
            math.max(0, _currentWaterLevelMl - drainedMlThisSecond);
      });
      _saveCurrentWaterLevel();
    });
  }

  void _stopManualDrainTracking() {
    _isPump1ManuallyActive = false;
    if (_manualDrainTrackingTimer != null) {
      _manualDrainTrackingTimer?.cancel();
      _manualDrainTrackingTimer = null;
      if (_manualDrainElapsedSec > 0) {
        final drainedTotal = (_manualDrainElapsedSec *
                ((_pumpLpm * (_drainSpeed / 100.0) * 1000.0) / 60.0))
            .round();
        LogService().addLog(
          '💧 Manual Drain Ended',
          'Drain pump was ON for ${_manualDrainElapsedSec}s (drained ~$drainedTotal mL). Current bowl water level: $_currentWaterLevelMl mL.',
          type: 'clean',
        );
        setState(() {
          _manualDrainElapsedSec = 0;
        });
      }
    }
  }

  void _startManualRefillTracking() {
    _isPump2ManuallyActive = true;
    _manualRefillTrackingTimer?.cancel();
    _manualRefillTrackingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isAutoCycle = widget.status?.autoCycle?.active ?? false;
      final isPump2On = _isPump2ManuallyActive || (widget.status?.pump2?.active ?? false);
      if (!isPump2On || isAutoCycle) {
        _stopManualRefillTracking();
        return;
      }

      final speed = widget.status?.pump2?.speed ?? _fillSpeed;
      final effectiveSpeed = speed < 10 ? 80 : speed;
      final mlPerSec = (_pumpLpm * (effectiveSpeed / 100.0) * 1000.0) / 60.0;
      final filledMlThisSecond = mlPerSec.round();

      setState(() {
        _manualRefillElapsedSec++;
        _currentWaterLevelMl =
            math.min(3000, _currentWaterLevelMl + filledMlThisSecond);
      });
      _saveCurrentWaterLevel();
    });
  }

  void _stopManualRefillTracking() {
    _isPump2ManuallyActive = false;
    if (_manualRefillTrackingTimer != null) {
      _manualRefillTrackingTimer?.cancel();
      _manualRefillTrackingTimer = null;
      if (_manualRefillElapsedSec > 0) {
        final filledTotal = (_manualRefillElapsedSec *
                ((_pumpLpm * (_fillSpeed / 100.0) * 1000.0) / 60.0))
            .round();
        LogService().addLog(
          '🚰 Manual Refill Ended',
          'Refill pump was ON for ${_manualRefillElapsedSec}s (filled ~$filledTotal mL). Current bowl water level: $_currentWaterLevelMl mL.',
          type: 'clean',
        );
        setState(() {
          _manualRefillElapsedSec = 0;
        });
      }
    }
  }

  Future<void> _saveLastRefill(LastRefillRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'drinker_last_refill_json', jsonEncode(record.toJson()));
    } catch (_) {}
  }

  Future<void> _saveCurrentWaterLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'drinker_current_water_level_ml', _currentWaterLevelMl);
    } catch (_) {}
  }

  int _computeSmartDrainSec({DrinkerPreset? preset, int? targetDrainMl}) {
    if (targetDrainMl != null) {
      if (targetDrainMl <= 0) return 0;
      final p = preset ?? _activePreset;
      return DrinkerPreset.computeSmartDrainSec(
        volumeMl: targetDrainMl,
        pumpLpm: p.pumpLpm,
        drainSpeedPercent: p.drainSpeed,
        safetyBufferSec: 2,
      );
    }

    if (_currentWaterLevelMl <= 0) return 0;

    // Check last fill up: if none recorded, set to 10sec default
    if (_lastRefill != null && _lastRefill!.drainSec > 0) {
      if (_currentWaterLevelMl < _lastRefill!.volumeMl) {
        return math.max(
            3,
            (_lastRefill!.drainSec *
                    (_currentWaterLevelMl / _lastRefill!.volumeMl))
                .round());
      }
      return _lastRefill!.drainSec;
    }
    if (_lastRefill == null) {
      final p = preset ?? _activePreset;
      if (_currentWaterLevelMl < p.volumeMl) {
        return math.max(3, (10 * (_currentWaterLevelMl / p.volumeMl)).round());
      }
      return 10;
    }

    final p = preset ?? _activePreset;
    return DrinkerPreset.computeSmartDrainSec(
      volumeMl: _currentWaterLevelMl,
      pumpLpm: p.pumpLpm,
      drainSpeedPercent: p.drainSpeed,
      safetyBufferSec: 2,
    );
  }

  Future<void> _triggerSequence(DrinkerPreset preset) async {
    final smartDrain = _computeSmartDrainSec(preset: preset);
    final lastMl = _currentWaterLevelMl;
    setState(() {
      _wasCycleActive = true;
      _isCycleCompleted = false;
      _cycleStartMl = 0;
    });
    await _apiService.triggerDrinkerAutoCycle(
      widget.deviceUrl,
      smartDrain,
      preset.fillSec,
      drainSpeed: preset.drainSpeed,
      fillSpeed: preset.fillSpeed,
      pauseSec: preset.pauseSec,
    );
    LogService().addLog(
      '✨ Clean & Refill Started',
      'Preset: ${preset.name} | Smart Drain ${smartDrain}s (computed from ${lastMl}mL in bowl) @ ${preset.drainSpeed}%, Settle ${preset.pauseSec}s, Refill ${preset.fillSec}s (~${preset.calculatedLiters.toStringAsFixed(2)}L) @ ${preset.fillSpeed}%',
      type: 'clean',
    );
    widget.onRefresh();
  }

  void _drainBowlToEmpty() async {
    if (_isDrainingToEmpty) return;

    if (_currentWaterLevelMl <= 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.0),
          ),
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drinker bowl is already marked empty (0 mL). Next flush will skip draining.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Check last fill up: if none recorded, set to 10sec default!
    final int drainSec = _lastRefill != null && _lastRefill!.drainSec > 0
        ? (_currentWaterLevelMl < _lastRefill!.volumeMl
            ? math.max(
                3,
                (_lastRefill!.drainSec *
                        (_currentWaterLevelMl / _lastRefill!.volumeMl))
                    .round())
            : _lastRefill!.drainSec)
        : 10;

    final startMl = _currentWaterLevelMl > 0
        ? _currentWaterLevelMl
        : (_lastRefill?.volumeMl ?? _activePreset.volumeMl);
    final activePreset = _activePreset;
    final startProgress =
        (startMl / activePreset.volumeMl.toDouble()).clamp(0.0, 1.0);

    _drainToEmptyAnimController?.dispose();
    _drainToEmptyAnimController = AnimationController(
      vsync: this,
      duration: Duration(seconds: drainSec),
    );

    _drainToEmptyProgressAnim = Tween<double>(
      begin: startProgress,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _drainToEmptyAnimController!,
      curve: Curves.easeInOutCubic,
    ));

    _drainToEmptyMlAnim = IntTween(
      begin: startMl,
      end: 0,
    ).animate(CurvedAnimation(
      parent: _drainToEmptyAnimController!,
      curve: Curves.easeInOutCubic,
    ));

    setState(() {
      _isDrainingToEmpty = true;
      _isCycleCompleted = false;
      _wasCycleActive = false;
    });

    _drainToEmptyAnimController!.addListener(() {
      setState(() {});
    });

    _drainToEmptyAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() {
          _isDrainingToEmpty = false;
          _currentWaterLevelMl = 0;
          _isCycleCompleted = false;
          _wasCycleActive = false;
        });
        _saveCurrentWaterLevel();

        LogService().addLog(
          '💧 Drinker Bowl Emptied',
          'Drinker bowl evacuated to 0 mL (${drainSec}s drain). Next flush sequence will skip draining phase.',
          type: 'clean',
        );

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF34D399), width: 1.2),
            ),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF34D399), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Drinker bowl drained & marked Empty (0 mL • ${drainSec}s). Next flush will skip draining.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    _drainToEmptyAnimController!.forward();

    // Trigger physical drain pump on ESP8266 for the drain duration
    try {
      _apiService.setPumpTimer(
        widget.deviceUrl,
        drainSec,
        false, // targetState: 0 (turn off after drainSec)
        speed: _drainSpeed,
        direction: 'fwd',
      );
    } catch (_) {}
  }

  void _stopDrainToEmpty() async {
    _drainToEmptyAnimController?.stop();
    _drainToEmptyAnimController?.reset();
    try {
      await _apiService.setPumpState(widget.deviceUrl, false, _drainSpeed);
    } catch (_) {}
    _stopManualDrainTracking();
    _isPump1ManuallyActive = false;

    final currentMl = _drainToEmptyMlAnim?.value ?? _currentWaterLevelMl;
    setState(() {
      _isDrainingToEmpty = false;
      _currentWaterLevelMl = currentMl.clamp(0, _activePreset.volumeMl);
      _isCycleCompleted = false;
      _wasCycleActive = false;
    });
    await _saveCurrentWaterLevel();
    widget.onRefresh();

    LogService().addLog(
      '🛑 Drain Evacuation Stopped',
      'Drain to empty stopped early. Water remaining in bowl: $_currentWaterLevelMl mL.',
      type: 'clean',
    );
  }


  Future<void> _triggerRefillOnly(DrinkerPreset preset) async {
    // Stop drain if running
    if (_isDrainingToEmpty) {
      _drainToEmptyAnimController?.stop();
      _drainToEmptyAnimController?.reset();
      try {
        await _apiService.setPumpState(widget.deviceUrl, false, _drainSpeed);
      } catch (_) {}
    }
    _stopManualDrainTracking();
    _isPump1ManuallyActive = false;

    // Calculate needed fill seconds based on current water level vs target
    final missingMl =
        (preset.volumeMl - _currentWaterLevelMl).clamp(0, preset.volumeMl);
    final int fillSec = missingMl > 0
        ? math.max(3, ((missingMl / 1000.0) / _pumpLpm * 60.0).round())
        : preset.fillSec;

    final startMl = _currentWaterLevelMl;

    setState(() {
      _wasCycleActive = true;
      _isCycleCompleted = false;
      _isDrainingToEmpty = false;
      _cycleStartMl = startMl;
    });

    await _apiService.triggerDrinkerAutoCycle(
      widget.deviceUrl,
      0, // 0 drain seconds: SKIPS DRAIN COMPLETELY ON ESP8266!
      fillSec,
      drainSpeed: preset.drainSpeed,
      fillSpeed: preset.fillSpeed,
      pauseSec: 0,
    );

    LogService().addLog(
      '💧 Refill Only Started',
      'Preset: ${preset.name} | Refilling for ${fillSec}s (~${(missingMl > 0 ? missingMl : preset.volumeMl)} mL) @ ${preset.fillSpeed}% speed. Draining skipped.',
      type: 'clean',
    );
    widget.onRefresh();
  }

  @override
  void dispose() {
    _drainToEmptyAnimController?.dispose();
    _manualDrainTrackingTimer?.cancel();
    _manualRefillTrackingTimer?.cancel();
    _drainSecController.dispose();
    _fillSecController.dispose();
    _lpmController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomPumpNamesAndSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final rawPresetsJson = prefs.getString('drinker_preset_list_json');
    List<DrinkerPreset> loadedPresets;
    if (rawPresetsJson != null && rawPresetsJson.isNotEmpty) {
      loadedPresets = DrinkerPreset.decodeList(rawPresetsJson);
    } else {
      loadedPresets = DrinkerPreset.defaultPresets();
    }

    String activeId =
        prefs.getString('drinker_active_preset_id') ?? 'preset_std';
    DrinkerPreset activePreset = loadedPresets.firstWhere(
      (p) => p.id == activeId,
      orElse: () => loadedPresets.first,
    );

    final lastRefillRaw = prefs.getString('drinker_last_refill_json');
    LastRefillRecord? loadedLastRefill;
    if (lastRefillRaw != null && lastRefillRaw.isNotEmpty) {
      try {
        loadedLastRefill =
            LastRefillRecord.fromJson(jsonDecode(lastRefillRaw));
      } catch (_) {}
    }

    final savedWaterLevel = prefs.getInt('drinker_current_water_level_ml');
    final initialWaterLevel =
        savedWaterLevel ?? (loadedLastRefill?.volumeMl ?? 0);

    setState(() {
      _pump1Name = prefs.getString('custom_pump_1_name') ??
          'Water Pump #1 (Main Drinker)';
      _pump2Name =
          prefs.getString('custom_pump_2_name') ?? '3V Submersible Pump #2';

      _presets = loadedPresets;
      _activePresetId = activePreset.id;
      _lastRefill = loadedLastRefill;
      _currentWaterLevelMl = initialWaterLevel;

      _drainSpeed = activePreset.drainSpeed;
      _fillSpeed = activePreset.fillSpeed;
      _pauseSec = activePreset.pauseSec;
      _pumpLpm = activePreset.pumpLpm;
      _drainSecController.text = activePreset.drainSec.toString();
      _fillSecController.text = activePreset.fillSec.toString();
      _lpmController.text = _pumpLpm.toStringAsFixed(1);
    });
  }

  Future<void> _savePresetsAndSyncActive() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
        'drinker_preset_list_json', DrinkerPreset.encodeList(_presets));
    await prefs.setString('drinker_active_preset_id', _activePresetId);

    final activePreset = _activePreset;
    await prefs.setInt('drinker_drain_sec', activePreset.drainSec);
    await prefs.setInt('drinker_fill_sec', activePreset.fillSec);
    await prefs.setInt('drinker_drain_speed', activePreset.drainSpeed);
    await prefs.setInt('drinker_fill_speed', activePreset.fillSpeed);
    await prefs.setInt('drinker_pause_sec', activePreset.pauseSec);
    await prefs.setDouble('drinker_pump_lpm', activePreset.pumpLpm);

    setState(() {
      _drainSpeed = activePreset.drainSpeed;
      _fillSpeed = activePreset.fillSpeed;
      _pauseSec = activePreset.pauseSec;
      _pumpLpm = activePreset.pumpLpm;
      _drainSecController.text = activePreset.drainSec.toString();
      _fillSecController.text = activePreset.fillSec.toString();
      _lpmController.text = _pumpLpm.toStringAsFixed(1);
    });

    _drinkerSchedKey.currentState?.reloadPresets();
  }

  Future<void> _saveSettings() async {
    await _savePresetsAndSyncActive();
  }





  Future<void> _promptCustomMlDialog(
    BuildContext context,
    Function(double targetLiters, int targetMl) onApplyVolume,
  ) async {
    final TextEditingController mlCtrl = TextEditingController(text: '750');
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 22),
              SizedBox(width: 8),
              Text(
                'Custom Refill Volume',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter exact target refill volume in milliliters (mL):',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mlCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  suffixText: 'mL',
                  suffixStyle: const TextStyle(
                      color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final mlInt = int.tryParse(mlCtrl.text);
                if (mlInt != null && mlInt > 0) {
                  onApplyVolume(mlInt / 1000.0, mlInt);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Apply Volume',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<double?> _showCalibrationWizard({
    int initialPumpNumber = 2,
    int? drainSpeed,
    int? fillSpeed,
  }) async {
    final TextEditingController testMlCtrl =
        TextEditingController(text: '500');
    bool isRunningTest = false;
    int secondsLeft = 10;
    int selectedPump = initialPumpNumber;

    return await showDialog<double>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final mlTested = double.tryParse(testMlCtrl.text) ?? 500;
            final mlPerSec = mlTested / 10.0;
            final secPerMl = mlTested > 0 ? (10.0 / mlTested) : 0.0;
            final lpm = (mlTested * 6.0) / 1000.0;

            final effectiveDrainSpeed = drainSpeed ?? _drainSpeed;
            final effectiveFillSpeed = fillSpeed ?? _fillSpeed;
            final activeSpeed = selectedPump == 1 ? effectiveDrainSpeed : effectiveFillSpeed;
            final pumpLabel = selectedPump == 1 ? 'Drain Pump #1' : 'Refill Pump #2';

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.science_rounded,
                      color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exact Pump Calibration',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Select pump & run 10-second test.\n'
                      '2. Flow speed during test: $activeSpeed% (${((activeSpeed / 100.0) * 1023).round()} PWM).\n'
                      '3. Measure collected water in mL & save calibration.',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
                    ),
                    const SizedBox(height: 12),

                    // Pump Selection Toggle
                    const Text('Select Pump to Test & Calibrate:',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            avatar: Icon(Icons.water_drop_rounded,
                                size: 14,
                                color: selectedPump == 2
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF10B981)),
                            label: Text('💧 Refill Pump #2 ($effectiveFillSpeed%)'),
                            selected: selectedPump == 2,
                            selectedColor: const Color(0xFF10B981),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: TextStyle(
                              color: selectedPump == 2
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            onSelected: isRunningTest
                                ? null
                                : (_) => setDialogState(() => selectedPump = 2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            avatar: Icon(Icons.waves_rounded,
                                size: 14,
                                color: selectedPump == 1
                                    ? Colors.white
                                    : const Color(0xFFEF4444)),
                            label: Text('🌊 Drain Pump #1 ($effectiveDrainSpeed%)'),
                            selected: selectedPump == 1,
                            selectedColor: const Color(0xFFEF4444),
                            backgroundColor: const Color(0xFF0F172A),
                            labelStyle: TextStyle(
                              color: selectedPump == 1
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            onSelected: isRunningTest
                                ? null
                                : (_) => setDialogState(() => selectedPump = 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunningTest
                              ? const Color(0xFFF59E0B)
                              : (selectedPump == 1
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF0EA5E9)),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: isRunningTest
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          isRunningTest
                              ? 'Running $pumpLabel... ${secondsLeft}s left'
                              : '🧪 Run 10s Test ($pumpLabel @ $activeSpeed%)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: isRunningTest
                            ? null
                            : () async {
                                setDialogState(() {
                                  isRunningTest = true;
                                  secondsLeft = 10;
                                });

                                LogService().addLog(
                                  '🧪 Calibration 10s Test Started',
                                  'Testing $pumpLabel @ $activeSpeed% speed for 10 seconds',
                                  type: 'pump',
                                );

                                if (selectedPump == 1) {
                                  await _apiService.setPumpState(
                                      widget.deviceUrl, true, activeSpeed);
                                  await _apiService.setPumpTimer(
                                      widget.deviceUrl, 10, false,
                                      speed: activeSpeed);
                                } else {
                                  await _apiService.setPump2State(
                                      widget.deviceUrl, true, activeSpeed);
                                  await _apiService.setPump2Timer(
                                      widget.deviceUrl, 10, false,
                                      speed: activeSpeed);
                                }

                                for (int i = 10; i > 0; i--) {
                                  if (!context.mounted) break;
                                  setDialogState(() => secondsLeft = i);
                                  await Future.delayed(
                                      const Duration(seconds: 1));
                                }

                                if (context.mounted) {
                                  setDialogState(() => isRunningTest = false);
                                  widget.onRefresh();
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Collected Water Amount (mL):',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: testMlCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        suffixText: 'mL in 10s',
                        suffixStyle: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFF334155))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF38BDF8), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Dynamic Flow Rate Metrics Preview Card
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF34D399)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CALIBRATED METRICS',
                            style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⚡ Flow Speed: ${mlPerSec.toStringAsFixed(1)} mL/sec (@ $activeSpeed% speed)',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          Text(
                            '⏱️ Time per mL: ${secPerMl.toStringAsFixed(3)} sec/mL',
                            style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                          Text(
                            '📊 Flow Rate Rating: ${lpm.toStringAsFixed(2)} L/min',
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final mlCollected =
                        double.tryParse(testMlCtrl.text) ?? 500;
                    if (mlCollected > 0) {
                      final newLpm = (mlCollected * 6.0) / 1000.0;
                      setState(() {
                        _pumpLpm = newLpm;
                        _lpmController.text = newLpm.toStringAsFixed(2);
                      });
                      _saveSettings();
                      Navigator.pop(context, newLpm);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Pump Calibrated! Flow rate set to ${(mlCollected / 10).toStringAsFixed(1)} mL/sec (${(10 / mlCollected).toStringAsFixed(3)} s/mL | ${newLpm.toStringAsFixed(2)} L/min).',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          backgroundColor: const Color(0xFF059669),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const Text('Save Calibration',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPresetManagerModal(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune_rounded,
                              color: Color(0xFF38BDF8), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Manage Drinker Presets',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Text(
                    'Select an active preset for manual cleaning or edit timing and pump speeds.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _presets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final preset = _presets[index];
                        final isSelected = preset.id == _activePresetId;

                        return InkWell(
                          onTap: () async {
                            setModalState(() {
                              _activePresetId = preset.id;
                            });
                            await _savePresetsAndSyncActive();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0EA5E9)
                                      .withValues(alpha: 0.15)
                                  : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF334155),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: preset.id,
                                  groupValue: _activePresetId,
                                  activeColor: const Color(0xFF38BDF8),
                                  onChanged: (val) async {
                                    if (val != null) {
                                      setModalState(() {
                                        _activePresetId = val;
                                      });
                                      await _savePresetsAndSyncActive();
                                    }
                                  },
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              preset.name,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : const Color(0xFFE2E8F0),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF38BDF8),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'ACTIVE',
                                                style: TextStyle(
                                                  color: Color(0xFF0F172A),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '💧 Refill ~${preset.calculatedLiters.toStringAsFixed(2)}L (${preset.fillSec}s @ ${preset.fillSpeed}%) • Drain ${preset.drainSec}s @ ${preset.drainSpeed}%\n⏸️ Pause: ${preset.pauseSec}s delay  •  Rate: ${preset.pumpLpm.toStringAsFixed(1)} L/min',
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded,
                                      color: Color(0xFF38BDF8), size: 18),
                                  tooltip: 'Edit Preset',
                                  onPressed: () {
                                    _showAddEditPresetModal(
                                      context,
                                      presetToEdit: preset,
                                      onSaved: () => setModalState(() {}),
                                    );
                                  },
                                ),
                                if (_presets.length > 1)
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 18),
                                    tooltip: 'Delete Preset',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF1E293B),
                                          title: const Text('Delete Preset?',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          content: Text(
                                            'Are you sure you want to delete "${preset.name}"?',
                                            style: const TextStyle(
                                                color: Color(0xFF94A3B8)),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFFEF4444),
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        setState(() {
                                          _presets.removeWhere(
                                              (p) => p.id == preset.id);
                                          if (_activePresetId == preset.id) {
                                            _activePresetId = _presets.first.id;
                                          }
                                        });
                                        await _savePresetsAndSyncActive();
                                        setModalState(() {});
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text(
                        'Create New Preset',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () {
                        _showAddEditPresetModal(
                          context,
                          onSaved: () => setModalState(() {}),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddEditPresetModal(
    BuildContext context, {
    DrinkerPreset? presetToEdit,
    VoidCallback? onSaved,
  }) async {
    final isEditing = presetToEdit != null;
    final nameCtrl = TextEditingController(
      text: presetToEdit?.name ?? 'Custom Preset',
    );
    int pauseSec = presetToEdit?.pauseSec ?? 2;
    int drainSpeed = presetToEdit?.drainSpeed ?? 80;
    int fillSpeed = presetToEdit?.fillSpeed ?? 80;
    double pumpLpm = presetToEdit?.pumpLpm ?? _pumpLpm;
    int currentTargetMl = presetToEdit?.volumeMl ?? 1500;

    int calcSmartDrainSec(int targetMl, double lpm, int speedPercent, {int safetyBufferSec = 2}) {
      final effectiveMlPerSec = (lpm * (speedPercent / 100.0) * 1000.0) / 60.0;
      if (effectiveMlPerSec <= 0) return 30;
      return (targetMl / effectiveMlPerSec).ceil() + safetyBufferSec;
    }

    final drainCtrl = TextEditingController(
      text: (presetToEdit?.drainSec ?? calcSmartDrainSec(currentTargetMl, pumpLpm, drainSpeed)).toString(),
    );
    final fillCtrl = TextEditingController(
      text: (presetToEdit?.fillSec ?? 40).toString(),
    );
    final lpmCtrl = TextEditingController(
      text: (presetToEdit?.pumpLpm ?? _pumpLpm).toStringAsFixed(1),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final List<int> volumeOptions = [
              ...{
                250,
                500,
                750,
                1000,
                1500,
                2000,
                3000,
                ..._presets.map((p) => p.volumeMl),
                currentTargetMl,
              }
            ]..sort();

            void applyVolume(double liters, int targetMl) {
              final fill = ((liters / pumpLpm) * 60.0).round();
              fillCtrl.text = '$fill';
              final smartDrain = calcSmartDrainSec(targetMl, pumpLpm, drainSpeed);
              drainCtrl.text = '$smartDrain';
              setModalState(() {
                currentTargetMl = targetMl;
              });
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing
                              ? 'Edit Drinker Preset'
                              : 'Create Drinker Preset',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.close, color: Color(0xFF94A3B8)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 10),

                    // Preset Name
                    const Text('Preset Title Name:',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Daily Morning Refill (1.5L)',
                        hintStyle: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFF334155))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF38BDF8), width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // STEP 1: Pump Speeds & Flow Rate Calibration
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Row(
                                  children: [
                                    Icon(Icons.science_rounded,
                                        color: Color(0xFF38BDF8), size: 16),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'STEP 1: PUMP SPEED & CALIBRATION',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${((pumpLpm * 1000) / 60).toStringAsFixed(1)} mL/sec',
                                style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Drain Speed ($drainSpeed%):',
                                        style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11)),
                                    Slider(
                                      value: drainSpeed
                                          .toDouble()
                                          .clamp(10.0, 100.0),
                                      min: 10,
                                      max: 100,
                                      divisions: 18,
                                      activeColor: const Color(0xFFEF4444),
                                      onChanged: (val) {
                                        setModalState(() {
                                          drainSpeed = val.round();
                                          final smartDrain = calcSmartDrainSec(currentTargetMl, pumpLpm, drainSpeed);
                                          drainCtrl.text = '$smartDrain';
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Fill Speed ($fillSpeed%):',
                                        style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11)),
                                    Slider(
                                      value: fillSpeed
                                          .toDouble()
                                          .clamp(10.0, 100.0),
                                      min: 10,
                                      max: 100,
                                      divisions: 18,
                                      activeColor: const Color(0xFF10B981),
                                      onChanged: (val) {
                                        setModalState(() {
                                          fillSpeed = val.round();
                                          final fill = (((currentTargetMl /
                                                          1000.0) /
                                                      pumpLpm) *
                                                  60.0)
                                              .round();
                                          fillCtrl.text = '$fill';
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8),
                                side: const BorderSide(
                                    color: Color(0xFF38BDF8), width: 1.2),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              icon: const Icon(Icons.science_rounded, size: 16),
                              label: const Text(
                                  '🧪 Run 10s Test Pump to Calibrate Rate',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11)),
                              onPressed: () async {
                                final newLpm = await _showCalibrationWizard(
                                  initialPumpNumber: 2,
                                  drainSpeed: drainSpeed,
                                  fillSpeed: fillSpeed,
                                );
                                if (newLpm != null) {
                                  lpmCtrl.text = newLpm.toStringAsFixed(2);
                                  setModalState(() {
                                    pumpLpm = newLpm;
                                    final fill = (((currentTargetMl / 1000.0) /
                                                pumpLpm) *
                                            60.0)
                                        .round();
                                    fillCtrl.text = '$fill';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // STEP 2: Target Volume & Sequence Timings
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF34D399)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Row(
                                  children: [
                                    Icon(Icons.water_rounded,
                                        color: Color(0xFF34D399), size: 16),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'STEP 2: TARGET VOLUME & TIMINGS',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Color(0xFF34D399),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$currentTargetMl mL (~${(currentTargetMl / 1000.0).toStringAsFixed(2)} L)',
                                style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...volumeOptions.map((ml) {
                                final liters = ml / 1000.0;
                                final isSel = currentTargetMl == ml;
                                final labelText = ml >= 1000
                                    ? '${(ml / 1000.0).toStringAsFixed(ml % 1000 == 0 ? 0 : 1)}L'
                                    : '${ml}mL';
                                return ChoiceChip(
                                  label: Text(labelText),
                                  selected: isSel,
                                  selectedColor: const Color(0xFF0EA5E9),
                                  backgroundColor: const Color(0xFF1E293B),
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? const Color(0xFF0F172A)
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  onSelected: (_) => applyVolume(liters, ml),
                                );
                              }),
                              ActionChip(
                                avatar: const Icon(Icons.edit_note_rounded,
                                    color: Color(0xFF38BDF8), size: 15),
                                label: const Text('Custom mL'),
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11),
                                side: const BorderSide(
                                    color: Color(0xFF38BDF8), width: 1),
                                onPressed: () => _promptCustomMlDialog(
                                    context, applyVolume),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Timing Inputs Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Drain Time (P1):',
                                        style: TextStyle(
                                            color: Color(0xFFEF4444),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: drainCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                      onChanged: (_) => setModalState(() {}),
                                      decoration: InputDecoration(
                                        suffixText: 's',
                                        suffixStyle: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 6),
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF334155))),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFEF4444),
                                                width: 1.5)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Pause Delay:',
                                        style: TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    DropdownButtonFormField<int>(
                                      initialValue: pauseSec,
                                      dropdownColor: const Color(0xFF1E293B),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 6),
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF334155))),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFF59E0B),
                                                width: 1.5)),
                                      ),
                                      items: [0, 1, 2, 3, 5, 10].map((sec) {
                                        return DropdownMenuItem<int>(
                                          value: sec,
                                          child: Text('${sec}s'),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setModalState(() => pauseSec = val);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Fill Time (P2):',
                                        style: TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: fillCtrl,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                      onChanged: (_) => setModalState(() {}),
                                      decoration: InputDecoration(
                                        suffixText: 's',
                                        suffixStyle: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 6),
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF334155))),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF10B981),
                                                width: 1.5)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 20),
                        label: Text(
                          isEditing ? 'Save Preset Changes' : 'Create Preset',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final drainSec = int.tryParse(drainCtrl.text) ?? 30;
                          final fillSec = int.tryParse(fillCtrl.text) ?? 40;

                          if (name.isEmpty) return;

                          final newPreset = DrinkerPreset(
                            id: presetToEdit?.id ??
                                'preset_${DateTime.now().millisecondsSinceEpoch}',
                            name: name,
                            drainSec: drainSec,
                            fillSec: fillSec,
                            pauseSec: pauseSec,
                            drainSpeed: drainSpeed,
                            fillSpeed: fillSpeed,
                            pumpLpm: pumpLpm,
                            targetMl: currentTargetMl,
                          );

                          setState(() {
                            if (isEditing) {
                              final idx = _presets
                                  .indexWhere((p) => p.id == presetToEdit.id);
                              if (idx != -1) {
                                _presets[idx] = newPreset;
                              }
                            } else {
                              _presets.add(newPreset);
                              _activePresetId = newPreset.id;
                            }
                          });

                          await _savePresetsAndSyncActive();
                          if (context.mounted) {
                            Navigator.pop(context);
                            onSaved?.call();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✅ Preset "$name" saved! ($currentTargetMl mL • ${(currentTargetMl / 1000.0).toStringAsFixed(currentTargetMl % 1000 == 0 ? 0 : (currentTargetMl % 100 == 0 ? 1 : 2))}L)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                backgroundColor: const Color(0xFF059669),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                action: SnackBarAction(
                                  label: '🧪 Calibrate',
                                  textColor: const Color(0xFF6EE7B7),
                                  onPressed: () => _showCalibrationWizard(),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAutoCycleCard() {
    final autoCycle = widget.status?.autoCycle;
    final isDeviceCycleActive = autoCycle?.active ?? false;
    final isActive = isDeviceCycleActive || _isDrainingToEmpty;
    final phase = _isDrainingToEmpty ? 1 : (autoCycle?.phase ?? 0);

    String phaseText = _isDrainingToEmpty
        ? 'DRAINING BOWL TO EMPTY...'
        : 'STAGE 1: DRAINING OLD WATER';
    Color phaseColor = const Color(0xFFEF4444);
    String activePumpDesc = _isDrainingToEmpty
        ? 'Evacuating Drinker Bowl to 0 mL...'
        : 'Active Pump: $_pump1Name (Drain @ ${autoCycle?.drainSpeed ?? _drainSpeed}%)';

    if (!_isDrainingToEmpty) {
      if (phase == 2) {
        phaseText = 'SETTLE PAUSE DELAY';
        phaseColor = const Color(0xFFF59E0B);
        activePumpDesc =
            'Pausing ${_pauseSec}s to allow residual water to settle before refilling...';
      } else if (phase == 3) {
        phaseText = 'STAGE 2: REFILLING FRESH WATER';
        phaseColor = const Color(0xFF10B981);
        activePumpDesc =
            'Active Pump: $_pump2Name (Fill @ ${autoCycle?.fillSpeed ?? _fillSpeed}%)';
      }
    }

    int totalDrainSec =
        autoCycle?.drainSec ?? (int.tryParse(_drainSecController.text) ?? 30);
    if (totalDrainSec <= 0) totalDrainSec = 30;
    int totalFillSec =
        autoCycle?.fillSec ?? (int.tryParse(_fillSecController.text) ?? 40);
    if (totalFillSec <= 0) totalFillSec = 40;
    int remainingSec = autoCycle?.remaining ?? 0;
    int elapsedDrainSec = (totalDrainSec - remainingSec).clamp(0, totalDrainSec);
    double drainProgressPercent =
        (elapsedDrainSec / totalDrainSec.toDouble()).clamp(0.0, 1.0);
    int elapsedFillSec = (totalFillSec - remainingSec).clamp(0, totalFillSec);

    final activePreset = _activePreset;

    // Use activePreset's volumeMl (e.g. 1000 mL = 1.0L) so that UI volume readouts
    // reflect the exact volume selected by the user instead of drifting to 988mL due to integer second rounding
    final int targetVolumeMl = activePreset.volumeMl;
    final double targetVolumeLiters = activePreset.calculatedLiters;

    double fillProgressPercent =
        (elapsedFillSec / totalFillSec.toDouble()).clamp(0.0, 1.0);
    int refilledMl = _cycleStartMl +
        (fillProgressPercent * (targetVolumeMl - _cycleStartMl)).round();
    int targetMl = targetVolumeMl;
    double targetLiters = targetVolumeLiters;

    final isDrainPumpRunningManually =
        ((widget.status?.pump?.active ?? false) || _isPump1ManuallyActive) &&
            !isActive;
    final isRefillPumpRunningManually =
        ((widget.status?.pump2?.active ?? false) || _isPump2ManuallyActive) &&
            !isActive;
    final smartDrainSec = _computeSmartDrainSec(preset: activePreset);
    final effectiveDrainMlPerSec =
        (activePreset.pumpLpm * (activePreset.drainSpeed / 100.0) * 1000.0) /
            60.0;

    final int drainToEmptySec = _lastRefill != null && _lastRefill!.drainSec > 0
        ? (_currentWaterLevelMl < _lastRefill!.volumeMl
            ? math.max(
                3,
                (_lastRefill!.drainSec *
                        (_currentWaterLevelMl / _lastRefill!.volumeMl))
                    .round())
            : _lastRefill!.drainSec)
        : 10;
    final int drainToEmptyRemainingSec = _isDrainingToEmpty
        ? (drainToEmptySec -
                ((_drainToEmptyAnimController?.value ?? 0.0) * drainToEmptySec)
                    .round())
            .clamp(0, drainToEmptySec)
        : 0;

    final double effectiveDisplayProgress = _isDrainingToEmpty
        ? (_drainToEmptyProgressAnim?.value ?? 0.0)
        : (isDeviceCycleActive
            ? (phase == 1
                ? (1.0 - drainProgressPercent)
                : (phase == 2
                    ? 0.08
                    : ((_cycleStartMl / targetVolumeMl.toDouble()) +
                            (fillProgressPercent *
                                (1.0 -
                                    (_cycleStartMl /
                                        targetVolumeMl.toDouble()))))
                        .clamp(0.0, 1.0)))
            : (_currentWaterLevelMl <= 0
                ? 0.0
                : (isDrainPumpRunningManually || isRefillPumpRunningManually
                    ? (_currentWaterLevelMl / activePreset.volumeMl.toDouble()).clamp(0.0, 1.0)
                    : (_isCycleCompleted
                        ? 1.0
                        : (_currentWaterLevelMl / activePreset.volumeMl.toDouble()).clamp(0.0, 1.0)))));

    final int? effectiveDisplayMl = _isDrainingToEmpty
        ? _drainToEmptyMlAnim?.value
        : (isDeviceCycleActive
            ? (phase == 3 ? refilledMl : null)
            : _currentWaterLevelMl);

    final int currentOrAnimMl = effectiveDisplayMl ?? _currentWaterLevelMl;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? phaseColor.withValues(alpha: 0.6)
              : (isDrainPumpRunningManually
                  ? const Color(0xFFEF4444).withValues(alpha: 0.7)
                  : (isRefillPumpRunningManually
                      ? const Color(0xFF10B981).withValues(alpha: 0.7)
                      : (_currentWaterLevelMl <= 0
                          ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                          : (_isCycleCompleted
                              ? const Color(0xFF10B981).withValues(alpha: 0.5)
                              : const Color(0xFF38BDF8).withValues(alpha: 0.3))))),
          width: (isDrainPumpRunningManually || isRefillPumpRunningManually) ? 2.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isActive
                    ? phaseColor
                    : (isDrainPumpRunningManually
                        ? const Color(0xFFEF4444)
                        : (isRefillPumpRunningManually
                            ? const Color(0xFF10B981)
                            : (_currentWaterLevelMl <= 0
                                ? const Color(0xFFEF4444)
                                : (_isCycleCompleted
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF38BDF8))))))
                .withValues(alpha: 0.15),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? phaseColor.withValues(alpha: 0.2)
                      : (isDrainPumpRunningManually
                          ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                          : (isRefillPumpRunningManually
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : (_currentWaterLevelMl <= 0
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                  : (_isCycleCompleted
                                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                      : const Color(0xFF38BDF8).withValues(alpha: 0.15))))),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive
                      ? Icons.cleaning_services_rounded
                      : (isDrainPumpRunningManually
                          ? Icons.water_damage_rounded
                          : (isRefillPumpRunningManually
                              ? Icons.water_drop_rounded
                              : (_currentWaterLevelMl <= 0
                                  ? Icons.warning_amber_rounded
                                  : (_isCycleCompleted
                                      ? Icons.check_circle_rounded
                                      : Icons.autorenew_rounded)))),
                  color: isActive
                      ? phaseColor
                      : (isDrainPumpRunningManually
                          ? const Color(0xFFEF4444)
                          : (isRefillPumpRunningManually
                              ? const Color(0xFF10B981)
                              : (_currentWaterLevelMl <= 0
                                  ? const Color(0xFFEF4444)
                                  : (_isCycleCompleted
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF38BDF8))))),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '2-Stage Drinker Flush & Refill Suite',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? (_isDrainingToEmpty
                              ? 'Evacuating Drinker Bowl (${drainToEmptyRemainingSec}s left • $currentOrAnimMl mL)...'
                              : 'Sequence Active (${remainingSec}s left)')
                          : (isDrainPumpRunningManually
                              ? 'Manual Drain Active (${_manualDrainElapsedSec}s) • Evacuating water...'
                              : (isRefillPumpRunningManually
                                  ? 'Manual Refill Active (${_manualRefillElapsedSec}s) • Adding water...'
                                  : (_currentWaterLevelMl <= 0
                                      ? 'Drinker Bowl Empty (0 mL) • Ready to Refill'
                                      : (_isCycleCompleted
                                          ? 'Drinker Refilled & Ready'
                                          : 'Bowl Level: $_currentWaterLevelMl mL • Stage 1: Drain ➔ Settle ➔ Stage 2: Refill')))),
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Status Pill Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? phaseColor.withValues(alpha: 0.2)
                      : (_currentWaterLevelMl <= 0
                          ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                          : (isDrainPumpRunningManually
                              ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                              : (isRefillPumpRunningManually
                                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                  : (_isCycleCompleted
                                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                      : const Color(0xFF38BDF8).withValues(alpha: 0.15))))),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? phaseColor.withValues(alpha: 0.5)
                        : (_currentWaterLevelMl <= 0
                            ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                            : (isDrainPumpRunningManually
                                ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                                : (isRefillPumpRunningManually
                                    ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                    : (_isCycleCompleted
                                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                        : const Color(0xFF38BDF8).withValues(alpha: 0.4))))),
                    width: 1,
                  ),
                ),
                child: Text(
                  isActive
                      ? (_isDrainingToEmpty
                          ? 'DRAINING (${drainToEmptyRemainingSec}s)'
                          : (phase == 1
                              ? 'DRAINING'
                              : (phase == 2 ? 'SETTLING' : 'REFILLING')))
                      : (_currentWaterLevelMl <= 0
                          ? 'DRY / EMPTY'
                          : (isDrainPumpRunningManually
                              ? 'MANUAL DRAIN'
                              : (isRefillPumpRunningManually
                                  ? 'MANUAL REFILL'
                                  : (_isCycleCompleted ? 'COMPLETED' : 'READY')))),
                  style: TextStyle(
                    color: isActive
                        ? phaseColor
                        : (_currentWaterLevelMl <= 0
                            ? const Color(0xFFEF4444)
                            : (isDrainPumpRunningManually
                                ? const Color(0xFFEF4444)
                                : (isRefillPumpRunningManually
                                    ? const Color(0xFF10B981)
                                    : (_isCycleCompleted
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF38BDF8))))),
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Central 3D Cylinder Liquid Wave Tank (Permanently visible in all states!)
          Center(
            child: CylinderWaterTankWidget(
              progress: effectiveDisplayProgress,
              phase: isActive
                  ? phase
                  : (_currentWaterLevelMl <= 0
                      ? 0
                      : (isDrainPumpRunningManually
                          ? 1
                          : (isRefillPumpRunningManually
                              ? 3
                              : (_isCycleCompleted ? 4 : 0)))),
              phaseText: isActive
                  ? (_isDrainingToEmpty
                      ? 'DRAINING BOWL TO EMPTY (${drainToEmptyRemainingSec}s)'
                      : phaseText)
                  : (_currentWaterLevelMl <= 0
                      ? 'DRINKER BOWL DRY'
                      : (isDrainPumpRunningManually
                          ? 'MANUAL DRAIN ACTIVE'
                          : (isRefillPumpRunningManually
                              ? 'MANUAL REFILL ACTIVE'
                              : (_isCycleCompleted
                                  ? 'CYCLE COMPLETED'
                                  : (_lastRefill != null
                                      ? 'LAST REFILL: ${_lastRefill!.timeAgo.toUpperCase()}'
                                      : 'PRESET: ${activePreset.volumeChipLabel}'))))),
              remainingSec: isDeviceCycleActive
                  ? remainingSec
                  : (_isDrainingToEmpty
                      ? drainToEmptyRemainingSec
                      : (isDrainPumpRunningManually
                          ? _manualDrainElapsedSec
                          : (isRefillPumpRunningManually ? _manualRefillElapsedSec : 0))),
              currentMl: effectiveDisplayMl,
              targetMl: isActive
                  ? (phase == 3 ? targetMl : null)
                  : (_isCycleCompleted
                      ? targetMl
                      : activePreset.volumeMl),
              currentLiters: effectiveDisplayMl != null
                  ? effectiveDisplayMl / 1000.0
                  : null,
              targetLiters: isActive
                  ? (phase == 3 ? targetLiters : null)
                  : (_isCycleCompleted
                      ? targetLiters
                      : activePreset.calculatedLiters),
              flowRateLpm: _pumpLpm,
              pumpName: isActive
                  ? activePumpDesc
                  : (_currentWaterLevelMl <= 0
                      ? 'Drinker Empty • Needs Refill'
                      : (isDrainPumpRunningManually
                          ? '$_pump1Name (Draining)'
                          : (isRefillPumpRunningManually
                              ? '$_pump2Name (Refilling)'
                              : (_isCycleCompleted
                                  ? '✓ Drinker Refilled & Ready'
                                  : (_lastRefill != null
                                      ? 'Last: ${_lastRefill!.presetName}'
                                      : 'Preset: ${activePreset.name} (${activePreset.volumeChipLabel})'))))),
              lastRefill: _lastRefill,
              smartDrainSec: smartDrainSec,
              width: 210,
              height: 250,
            ),
          ),

          const SizedBox(height: 16),

          // Controls & Action Area
          if (isDeviceCycleActive) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFEF4444).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFFFCA5A5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.stop_circle, size: 20),
                label: const Text('Cancel Active Flush & Refill Sequence',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await _apiService.stopDrinkerAutoCycle(widget.deviceUrl);
                  setState(() {
                    _wasCycleActive = false;
                    _isCycleCompleted = false;
                  });
                  LogService().addLog(
                    '🛑 Clean & Refill Cancelled',
                    'Sequence manually stopped by user.',
                    type: 'clean',
                  );
                  widget.onRefresh();
                },
              ),
            ),
          ],
          if (!isDeviceCycleActive &&
              _isCycleCompleted &&
              _currentWaterLevelMl > 0 &&
              !_isDrainingToEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF34D399), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Drinker cycle completed! Bowl refilled with fresh water (~$currentOrAnimMl mL).',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF94A3B8), size: 16),
                    onPressed: () {
                      setState(() {
                        _isCycleCompleted = false;
                        _wasCycleActive = false;
                      });
                    },
                    tooltip: 'Dismiss',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
            if (_isDrainingToEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Draining Drinker Bowl to Empty... (${drainToEmptyRemainingSec}s left • $currentOrAnimMl mL)',
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Default View: Drinker Bowl Water Monitor & Smart Check Banner
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDrainPumpRunningManually || _isDrainingToEmpty
                      ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                      : const Color(0xFF38BDF8).withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isDrainPumpRunningManually || _isDrainingToEmpty
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF38BDF8))
                        .withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (isDrainPumpRunningManually || _isDrainingToEmpty
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF38BDF8))
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDrainPumpRunningManually || _isDrainingToEmpty
                              ? Icons.water_damage_rounded
                              : Icons.sensors_rounded,
                          color: isDrainPumpRunningManually || _isDrainingToEmpty
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF38BDF8),
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isDrainPumpRunningManually
                              ? 'MANUAL DRAIN IN PROGRESS'
                              : (_isDrainingToEmpty
                                  ? 'DRAINING TO EMPTY (${drainToEmptyRemainingSec}s • $currentOrAnimMl mL)'
                                  : 'DRINKER BOWL MONITOR'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDrainPumpRunningManually || _isDrainingToEmpty
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF38BDF8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (_lastRefill != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history_rounded,
                                  color: Color(0xFF34D399), size: 12),
                              const SizedBox(width: 4),
                              Text(
                                _lastRefill!.timeAgo,
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1120),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF334155).withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniRefillStat(
                          label: 'CURRENT IN BOWL',
                          value: '$currentOrAnimMl mL',
                          sub: currentOrAnimMl <= 0
                              ? 'Bowl Empty'
                              : (_isDrainingToEmpty
                                  ? 'Draining to 0 mL...'
                                  : (_lastRefill != null && currentOrAnimMl < _lastRefill!.volumeMl
                                      ? '-${_lastRefill!.volumeMl - currentOrAnimMl} mL drained'
                                      : '~${(currentOrAnimMl / 1000.0).toStringAsFixed(2)} L')),
                          icon: currentOrAnimMl <= 0
                              ? Icons.warning_amber_rounded
                              : (_isDrainingToEmpty
                                  ? Icons.water_damage_rounded
                                  : Icons.water_drop_rounded),
                          iconColor: currentOrAnimMl <= 0 || _isDrainingToEmpty
                              ? const Color(0xFFEF4444)
                              : (isDrainPumpRunningManually
                                  ? const Color(0xFFF97316)
                                  : const Color(0xFF38BDF8)),
                        ),
                        Container(
                            width: 1,
                            height: 28,
                            color: const Color(0xFF334155)),
                        _buildMiniRefillStat(
                          label: 'LAST REFILL',
                          value: _lastRefill != null ? '${_lastRefill!.volumeMl} mL' : 'None (10s Default)',
                          sub: _lastRefill?.presetName ?? 'No prior fill recorded',
                          icon: Icons.bookmarks_rounded,
                          iconColor: const Color(0xFFA78BFA),
                        ),
                        Container(
                            width: 1,
                            height: 28,
                            color: const Color(0xFF334155)),
                        _buildMiniRefillStat(
                          label: 'DRAIN RATE',
                          value: '${effectiveDrainMlPerSec.toStringAsFixed(1)} mL/s',
                          sub: '@ ${activePreset.drainSpeed}% speed',
                          icon: Icons.speed_rounded,
                          iconColor: const Color(0xFF34D399),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Smart Drain Computation Explanation
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: currentOrAnimMl <= 0
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : (_isDrainingToEmpty
                                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                : const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: (currentOrAnimMl <= 0
                                    ? const Color(0xFF10B981)
                                    : (_isDrainingToEmpty
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF38BDF8)))
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            currentOrAnimMl <= 0
                                ? Icons.check_circle_rounded
                                : (_isDrainingToEmpty
                                    ? Icons.water_damage_rounded
                                    : Icons.auto_awesome_rounded),
                            color: currentOrAnimMl <= 0
                                ? const Color(0xFF34D399)
                                : (_isDrainingToEmpty
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF38BDF8)),
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      currentOrAnimMl <= 0
                                          ? 'SMART DRAIN: 0s (BOWL EMPTY)'
                                          : (_isDrainingToEmpty
                                              ? 'DRAINING TO EMPTY IN PROGRESS'
                                              : (_lastRefill != null
                                                  ? 'SMART DRAIN (LAST: ${_lastRefill!.volumeMl} mL)'
                                                  : 'SMART DRAIN (DEFAULT: 10s)')),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: currentOrAnimMl <= 0
                                            ? const Color(0xFF34D399)
                                            : (_isDrainingToEmpty
                                                ? const Color(0xFFFCA5A5)
                                                : const Color(0xFF38BDF8)),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currentOrAnimMl <= 0
                                        ? '0s (Dry)'
                                        : (_isDrainingToEmpty
                                            ? '${drainToEmptyRemainingSec}s left'
                                            : '${smartDrainSec}s to drain'),
                                    style: TextStyle(
                                      color: currentOrAnimMl <= 0
                                          ? const Color(0xFF94A3B8)
                                          : (_isDrainingToEmpty
                                              ? const Color(0xFFFCA5A5)
                                              : const Color(0xFF34D399)),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentOrAnimMl <= 0
                                    ? 'Bowl is dry. Next flush skips drain phase and refills fresh water immediately.'
                                    : (_isDrainingToEmpty
                                        ? 'Evacuating drinker bowl to 0 mL (${drainToEmptySec}s duration). Bowl will be marked dry upon completion.'
                                        : (_lastRefill != null
                                            ? 'Evacuating last fill (${_lastRefill!.volumeMl} mL) in ${smartDrainSec}s @ ${activePreset.drainSpeed}% speed + air purge'
                                            : 'No prior fill recorded. Using default 10s drain duration to evacuate bowl.')),
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Quick Calibration Action Buttons
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF87171),
                          side: BorderSide(
                            color: currentOrAnimMl == 0
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFEF4444).withValues(alpha: 0.4),
                            width: currentOrAnimMl == 0 ? 1.5 : 1.0,
                          ),
                          backgroundColor: currentOrAnimMl == 0
                              ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                              : const Color(0xFFEF4444).withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: _isDrainingToEmpty
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFEF4444),
                                ),
                              )
                            : Icon(
                                currentOrAnimMl == 0
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.remove_circle_outline_rounded,
                                size: 13,
                              ),
                        label: Text(
                          _isDrainingToEmpty
                              ? 'Draining Bowl (${drainToEmptyRemainingSec}s)...'
                              : (currentOrAnimMl == 0
                                  ? 'Bowl is Empty (0 mL)'
                                  : 'Set Empty (0 mL)'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 10.5),
                        ),
                        onPressed: _isDrainingToEmpty
                            ? _stopDrainToEmpty
                            : _drainBowlToEmpty,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF34D399),
                          side: const BorderSide(
                            color: Color(0xFF10B981),
                            width: 1.0,
                          ),
                          backgroundColor:
                              const Color(0xFF10B981).withValues(alpha: 0.1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.water_drop_rounded,
                            size: 13, color: Color(0xFF34D399)),
                        label: Text(
                          activePreset.volumeMl > currentOrAnimMl
                              ? 'Refill (+${activePreset.volumeMl - currentOrAnimMl} mL)'
                              : 'Refill Bowl',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 10.5),
                        ),
                        onPressed: (isDeviceCycleActive ||
                                currentOrAnimMl >=
                                    (_lastRefill?.volumeMl ??
                                        activePreset.volumeMl))
                            ? null
                            : () => _triggerRefillOnly(activePreset),
                      ),

                    ],
                  ),
                ],
              ),
            ),
            // Default View: Redesigned Volume Preset Selector & Sequence Specs
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row: Title & Manage Presets
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bookmarks_rounded,
                              color: Color(0xFF38BDF8), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'SELECT REFILL VOLUME',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(
                              color: Color(0xFF38BDF8), width: 1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 13),
                        label: const Text('Manage All',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 10)),
                        onPressed: () => _showPresetManagerModal(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Horizontal Preset Choice Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._presets.map((preset) {
                          final isSel = preset.id == _activePresetId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              avatar: isSel
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF0F172A), size: 15)
                                  : null,
                              label: Text(
                                '${preset.volumeChipLabel} (${preset.name})',
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF38BDF8),
                              backgroundColor: const Color(0xFF1E293B),
                              labelStyle: TextStyle(
                                color: isSel
                                    ? const Color(0xFF0F172A)
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              side: BorderSide(
                                color: isSel
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF334155),
                                width: isSel ? 1.5 : 1.0,
                              ),
                              onSelected: (_) async {
                                setState(() {
                                  _activePresetId = preset.id;
                                });
                                await _savePresetsAndSyncActive();
                              },
                            ),
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add_circle_outline_rounded,
                              color: Color(0xFF10B981), size: 15),
                          label: const Text('+ Custom Volume'),
                          backgroundColor:
                              const Color(0xFF10B981).withValues(alpha: 0.15),
                          labelStyle: const TextStyle(
                            color: Color(0xFF34D399),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          side: const BorderSide(
                              color: Color(0xFF34D399), width: 1),
                          onPressed: () {
                            _showAddEditPresetModal(
                              context,
                              onSaved: () => setState(() {}),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3-Step Sequence Specs Bar (Drain ➔ Settle ➔ Refill)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Drain Step (Smart computed from remaining water in bowl)
                        _buildStepMetric(
                          icon: Icons.cleaning_services_rounded,
                          iconColor: const Color(0xFFEF4444),
                          title: 'Stage 1: Drain',
                          value: '${smartDrainSec}s',
                          sub: currentOrAnimMl <= 0
                              ? 'Dry (Skip)'
                              : 'Smart (${currentOrAnimMl}mL)',
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color(0xFF334155),
                        ),
                        // Settle Step
                        _buildStepMetric(
                          icon: Icons.hourglass_top_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Pause Delay',
                          value: '${activePreset.pauseSec}s',
                          sub: 'Settle residual',
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color(0xFF334155),
                        ),
                        // Refill Step
                        _buildStepMetric(
                          icon: Icons.water_drop_rounded,
                          iconColor: const Color(0xFF10B981),
                          title: 'Stage 2: Refill',
                          value: '${activePreset.fillSec}s',
                          sub:
                              '~${activePreset.calculatedLiters.toStringAsFixed(2)} L',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (_isDrainingToEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shadowColor: const Color(0xFFDC2626).withValues(alpha: 0.4),
                  ),
                  icon: const Icon(Icons.stop_circle_rounded, size: 22),
                  label: Text(
                    'Stop Draining Early (${drainToEmptyRemainingSec}s left • $currentOrAnimMl mL in bowl)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                  onPressed: _stopDrainToEmpty,
                ),
              ),
            ] else if (currentOrAnimMl <= 0) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 4,
                    shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                  icon: const Icon(Icons.water_drop_rounded, size: 22),
                  label: Text(
                    'Start Refill (${activePreset.volumeChipLabel} • ${activePreset.volumeMl} mL)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                  onPressed: () => _triggerRefillOnly(activePreset),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 4,
                    shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                  icon: const Icon(Icons.water_drop_rounded, size: 22),
                  label: Text(
                    activePreset.volumeMl > currentOrAnimMl
                        ? 'Refill Drinker Bowl (+${activePreset.volumeMl - currentOrAnimMl} mL • Skip Drain)'
                        : 'Top-Up Drinker Bowl (${activePreset.volumeChipLabel} • Skip Drain)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                  onPressed: () => _triggerRefillOnly(activePreset),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7), width: 1.3),
                    backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: Text(
                    'Full Flush (${smartDrainSec}s) & Refill (${activePreset.volumeChipLabel})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                  onPressed: () => _triggerSequence(activePreset),
                ),
              ),
            ],
          ],
      ),
    );
  }

  Widget _buildMiniRefillStat({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 11),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepMetric({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String sub,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        Text(
          sub,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pump1 = widget.status?.pump;
    final pump2 = widget.status?.pump2;
    final isCycleActive = widget.status?.autoCycle?.active ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.water_drop,
                      color: Color(0xFF38BDF8), size: 30),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Automatic Water Drinker',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Dual-Channel Automatic Drinkers & Motor Control',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2-Stage Automated Drinker Flush & Refill Suite Card
          // (Contains the Cancel button which remains interactive when active)
          _buildAutoCycleCard(),

          if (isCycleActive) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: Color(0xFFFCA5A5), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manual pump controls & schedules are locked during active sequence. Tap "Cancel" above to stop.',
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Lock & Dim all other controls when a Flush & Refill sequence is active
          IgnorePointer(
            ignoring: isCycleActive,
            child: Opacity(
              opacity: isCycleActive ? 0.45 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dual Submersible Pumps Grid Layout Section
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.grid_view_rounded,
                            color: Color(0xFF38BDF8), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dual Submersible Pump Controllers',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SmallPumpCardWidget(
                          pumpId: 1,
                          title: _pump1Name,
                          subtitle: 'Channel A',
                          pumpStatus: pump1,
                          onUpdatePump: (state, speed, dir) async {
                            final targetSpeed = speed < 10 ? 80 : speed;
                            if (state) {
                              _startManualDrainTracking();
                            } else {
                              _stopManualDrainTracking();
                            }
                            await _apiService.setPumpState(
                                widget.deviceUrl, state, targetSpeed,
                                direction: dir);
                            LogService().addLog(
                              state
                                  ? '🌊 $_pump1Name Started'
                                  : '🛑 $_pump1Name Stopped',
                              'Flow speed set to $targetSpeed%',
                              type: 'pump1',
                            );
                            widget.onRefresh();
                          },
                          onTapDetails: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PumpDetailScreen(
                                  pumpId: 1,
                                  initialName: _pump1Name,
                                  pumpStatus: pump1,
                                  deviceUrl: widget.deviceUrl,
                                  onRefresh: widget.onRefresh,
                                  onNameChanged: (newName) {
                                    setState(() => _pump1Name = newName);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SmallPumpCardWidget(
                          pumpId: 2,
                          title: _pump2Name,
                          subtitle: 'Channel B',
                          pumpStatus: pump2,
                          onUpdatePump: (state, speed, dir) async {
                            final targetSpeed = speed < 10 ? 80 : speed;
                            if (state) {
                              _startManualRefillTracking();
                            } else {
                              _stopManualRefillTracking();
                            }
                            await _apiService.setPump2State(
                                widget.deviceUrl, state, targetSpeed,
                                direction: dir);
                            LogService().addLog(
                              state
                                  ? '🌊 $_pump2Name Started'
                                  : '🛑 $_pump2Name Stopped',
                              'Flow speed set to $targetSpeed%',
                              type: 'pump2',
                            );
                            widget.onRefresh();
                          },
                          onTapDetails: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PumpDetailScreen(
                                  pumpId: 2,
                                  initialName: _pump2Name,
                                  pumpStatus: pump2,
                                  deviceUrl: widget.deviceUrl,
                                  onRefresh: widget.onRefresh,
                                  onNameChanged: (newName) {
                                    setState(() => _pump2Name = newName);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Unified Hardware Drinker Schedule Manager
                  DrinkerScheduleWidget(
                    key: _drinkerSchedKey,
                    deviceUrl: widget.deviceUrl,
                    targetFilter: 0,
                    onRefreshNeeded: widget.onRefresh,
                  ),

                  const SizedBox(height: 16),

                  // In-App Session Activity & Refill Log Widget
                  const LogSessionWidget(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
