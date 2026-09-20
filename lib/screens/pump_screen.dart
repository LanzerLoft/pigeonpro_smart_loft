import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../models/drinker_preset.dart';
import '../services/esp8266_service.dart';
import '../services/log_service.dart';
import '../widgets/pump_card_widget.dart';
import '../widgets/drinker_schedule_widget.dart';
import '../widgets/log_session_widget.dart';
import 'pump_detail_screen.dart';

class PumpScreen extends StatefulWidget {
  final EspStatus? status;
  final String deviceUrl;
  final VoidCallback onRefresh;

  const PumpScreen({
    Key? key,
    required this.status,
    required this.deviceUrl,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<PumpScreen> createState() => _PumpScreenState();
}

class _PumpScreenState extends State<PumpScreen> {
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
    _loadCustomPumpNamesAndSettings();
  }

  @override
  void dispose() {
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

    setState(() {
      _pump1Name = prefs.getString('custom_pump_1_name') ??
          'Water Pump #1 (Main Drinker)';
      _pump2Name =
          prefs.getString('custom_pump_2_name') ?? '3V Submersible Pump #2';

      _presets = loadedPresets;
      _activePresetId = activePreset.id;

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
                              '✅ Pump Calibrated! Flow rate set to ${(mlCollected / 10).toStringAsFixed(1)} mL/sec (${(10 / mlCollected).toStringAsFixed(3)} s/mL | ${newLpm.toStringAsFixed(2)} L/min).'),
                          backgroundColor: const Color(0xFF10B981),
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

            double calcLiters() {
              final fill = int.tryParse(fillCtrl.text) ?? 40;
              return (fill / 60.0) * pumpLpm;
            }

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
                                    '✅ Preset "$name" saved! (${(calcLiters() * 1000).round()} mL)'),
                                backgroundColor: const Color(0xFF10B981),
                                action: SnackBarAction(
                                  label: '🧪 Calibrate',
                                  textColor: Colors.white,
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
    final isActive = autoCycle?.active ?? false;
    final phase = autoCycle?.phase ?? 0;

    String phaseText = 'STAGE 1: DRAINING OLD WATER';
    Color phaseColor = const Color(0xFFEF4444);
    String activePumpDesc =
        'Active Pump: $_pump1Name (Drain @ ${autoCycle?.drainSpeed ?? _drainSpeed}%)';

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

    int totalFillSec =
        autoCycle?.fillSec ?? (int.tryParse(_fillSecController.text) ?? 40);
    if (totalFillSec <= 0) totalFillSec = 40;
    int remainingSec = autoCycle?.remaining ?? 0;
    int elapsedFillSec = (totalFillSec - remainingSec).clamp(0, totalFillSec);

    double refilledLiters = (elapsedFillSec / 60.0) * _pumpLpm;
    double targetLiters = (totalFillSec / 60.0) * _pumpLpm;
    int refilledMl = (refilledLiters * 1000).round();
    int targetMl = (targetLiters * 1000).round();
    double fillProgressPercent =
        (elapsedFillSec / totalFillSec.toDouble()).clamp(0.0, 1.0);

    final activePreset = _activePreset;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? phaseColor.withValues(alpha: 0.6)
              : const Color(0xFF38BDF8).withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: phaseColor.withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? phaseColor.withValues(alpha: 0.2)
                      : const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.cleaning_services : Icons.autorenew_rounded,
                  color: isActive ? phaseColor : const Color(0xFF38BDF8),
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
                          ? 'Sequence Active (${remainingSec}s left)'
                          : 'Stage 1: Drain ➔ ${_pauseSec}s Settle Delay ➔ Stage 2: Refill',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isActive) ...[
            // Active 2-Stage Progress Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: phaseColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: phaseColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          phaseText,
                          style: TextStyle(
                            color: phaseColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        '${remainingSec}s left',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activePumpDesc,
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: phase == 3 ? fillProgressPercent : null,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
                      minHeight: 6,
                    ),
                  ),

                  // Live Refill Volume Gauge (Stage 2 Filling)
                  if (phase == 3) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color(0xFF34D399).withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.water_drop_rounded,
                                      color: Color(0xFF34D399), size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Live Water Refill Progress:',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                              Text(
                                '${(fillProgressPercent * 100).toStringAsFixed(1)}% Filled',
                                style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '💧 $refilledMl mL / $targetMl mL  (~${refilledLiters.toStringAsFixed(2)} L of ${targetLiters.toStringAsFixed(2)} L)',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: fillProgressPercent,
                              backgroundColor: const Color(0xFF334155),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF34D399)),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pump Flow Rate: ${_pumpLpm.toStringAsFixed(1)} L/min (~${(_pumpLpm * 1000 / 60).round()} mL/sec)',
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFEF4444).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFFFCA5A5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.stop_circle, size: 20),
                label: const Text('Cancel Active Flush & Refill Sequence',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await _apiService.stopDrinkerAutoCycle(widget.deviceUrl);
                  LogService().addLog(
                    '🛑 Clean & Refill Cancelled',
                    'Sequence manually stopped by user.',
                    type: 'clean',
                  );
                  widget.onRefresh();
                },
              ),
            ),
          ] else ...[
            // Active Preset Selector & Volume Chips Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_added_rounded,
                                color: Color(0xFF38BDF8), size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'REFILL PRESET: ${activePreset.volumeChipLabel}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
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

                  // Volume Chips Selector Row
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

                  // Selected Preset Parameters Detail Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.water_drop_rounded,
                                color: Color(0xFF34D399), size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Volume: ${activePreset.volumeMl} mL (~${activePreset.calculatedLiters.toStringAsFixed(2)} L)',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💧 Fill Pump #2: ${activePreset.fillSec}s @ ${activePreset.fillSpeed}%\n'
                          '🌊 Drain Pump #1: ${activePreset.drainSec}s @ ${activePreset.drainSpeed}%\n'
                          '⏸️ Settle Pause: ${activePreset.pauseSec}s delay  •  Rate: ${activePreset.pumpLpm.toStringAsFixed(1)} L/min (~${(activePreset.pumpLpm * 1000 / 60).round()} mL/s)',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Action Button: Clean & Refill
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  '✨ Clean & Refill (${activePreset.name})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
                onPressed: () async {
                  await _apiService.triggerDrinkerAutoCycle(
                    widget.deviceUrl,
                    activePreset.drainSec,
                    activePreset.fillSec,
                    drainSpeed: activePreset.drainSpeed,
                    fillSpeed: activePreset.fillSpeed,
                    pauseSec: activePreset.pauseSec,
                  );
                  LogService().addLog(
                    '✨ Clean & Refill Started',
                    'Preset: ${activePreset.name} | Drain ${activePreset.drainSec}s @ ${activePreset.drainSpeed}%, Settle ${activePreset.pauseSec}s, Refill ${activePreset.fillSec}s (~${activePreset.calculatedLiters.toStringAsFixed(2)}L) @ ${activePreset.fillSpeed}%',
                    type: 'clean',
                  );
                  widget.onRefresh();
                },
              ),
            ),
          ],
        ],
      ),
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
