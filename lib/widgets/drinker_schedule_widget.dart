import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../models/drinker_preset.dart';
import '../services/esp8266_service.dart';
import '../services/log_service.dart';

class DrinkerScheduleWidget extends StatefulWidget {
  final String deviceUrl;
  final int targetFilter; // 0 = All Targets, 1..4 = Relay 1..4, 5 = Water Pump / Auto Drinker
  final VoidCallback? onRefreshNeeded;

  const DrinkerScheduleWidget({
    Key? key,
    required this.deviceUrl,
    this.targetFilter = 0,
    this.onRefreshNeeded,
  }) : super(key: key);

  @override
  State<DrinkerScheduleWidget> createState() => DrinkerScheduleWidgetState();
}

class DrinkerScheduleWidgetState extends State<DrinkerScheduleWidget> {
  final Esp8266Service _apiService = Esp8266Service();
  HardwareScheduleData? _scheduleData;
  final Set<int> _deletedSlotIds = {};
  bool _isLoading = true;
  bool _isSyncingTime = false;

  List<DrinkerPreset> _savedPresets = [];
  int _savedDrainSec = 30;
  int _savedFillSec = 40;
  int _savedPauseSec = 2;
  double _savedPumpLpm = 3.0;
  int _savedFillSpeed = 80;

  final List<String> _dayAbbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _syncPhoneClockQuietly();
    _loadSavedPresets();
    _loadSchedules();
  }

  Future<void> reloadPresets() async {
    await _loadSavedPresets();
    await _loadSchedules();
  }

  Future<void> _loadSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final rawJson = prefs.getString('drinker_preset_list_json');
    final loadedPresets = rawJson != null && rawJson.isNotEmpty
        ? DrinkerPreset.decodeList(rawJson)
        : DrinkerPreset.defaultPresets();

    setState(() {
      _savedPresets = loadedPresets;
      _savedDrainSec = prefs.getInt('drinker_drain_sec') ?? 30;
      _savedFillSec = prefs.getInt('drinker_fill_sec') ?? 40;
      _savedPauseSec = prefs.getInt('drinker_pause_sec') ?? 2;
      _savedPumpLpm = prefs.getDouble('drinker_pump_lpm') ?? 3.0;
      _savedFillSpeed = prefs.getInt('drinker_fill_speed') ?? 80;
    });
  }

  Future<void> _syncPhoneClockQuietly() async {
    await _apiService.syncPhoneTime(widget.deviceUrl);
  }

  Future<void> _loadSchedules() async {
    final data = await _apiService.fetchHardwareSchedules(widget.deviceUrl);
    if (!mounted) return;
    setState(() {
      _scheduleData = data;
      _isLoading = false;
    });
  }

  Future<void> _syncPhoneClock() async {
    setState(() => _isSyncingTime = true);
    final success = await _apiService.syncPhoneTime(widget.deviceUrl);
    if (!mounted) return;
    setState(() => _isSyncingTime = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '✅ Board clock successfully synced with phone!'
              : '❌ Failed to sync time. Check Wi-Fi connection.',
        ),
        backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      ),
    );

    _loadSchedules();
  }

  void _showAddEditScheduleDialog({HardwareSchedule? existingSchedule, int? targetId}) {
    final isEditing = existingSchedule != null;
    final slotId = existingSchedule?.id ?? _firstAvailableSlotId();

    int selectedTarget = existingSchedule?.target ?? targetId ?? (widget.targetFilter != 0 ? widget.targetFilter : 5);
    int selectedHour = existingSchedule?.hour ?? 7;
    int selectedMinute = existingSchedule?.minute ?? 30;
    bool targetState = existingSchedule?.targetState ?? true;
    int durationSec = existingSchedule?.durationSec ?? ((selectedTarget == 5 || selectedTarget == 6) ? 120 : 0);
    int speedPercent = existingSchedule?.speedPercent ?? 80;
    List<bool> days = existingSchedule?.recurringDays ?? [true, true, true, true, true, true, true];
    bool enabled = existingSchedule?.enabled ?? true;
    final TextEditingController secInputCtrl = TextEditingController(text: durationSec.toString());

    int customDrainSec = (existingSchedule != null && existingSchedule.target == 7 && existingSchedule.rawState > 0)
        ? existingSchedule.rawState
        : _savedDrainSec;
    int customFillSec = (existingSchedule != null && existingSchedule.target == 7 && existingSchedule.durationSec > 0)
        ? existingSchedule.durationSec
        : _savedFillSec;
    int customSpeed = (existingSchedule != null && existingSchedule.target == 7 && existingSchedule.speedPercent > 0)
        ? existingSchedule.speedPercent
        : _savedFillSpeed;


    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
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
                        Expanded(
                          child: Text(
                            isEditing ? 'Edit Hardware Schedule (Slot #${slotId + 1})' : 'Add New Hardware Schedule',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 10),

                    // Target Selector
                    const Text('Target Hardware Device:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedTarget,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Relay 1 - Light / Lamp')),
                            DropdownMenuItem(value: 2, child: Text('Relay 2 - Exhaust Fan')),
                            DropdownMenuItem(value: 3, child: Text('Relay 3 - Auxiliary')),
                            DropdownMenuItem(value: 4, child: Text('Relay 4 - Auxiliary / Gate')),
                            DropdownMenuItem(value: 5, child: Text('🌊 Water Pump #1 (OUT1 / OUT2)')),
                            DropdownMenuItem(value: 6, child: Text('🌊 3V Submersible Pump #2 (OUT3 / OUT4)')),
                            DropdownMenuItem(value: 7, child: Text('✨ Flush & Refill Drinker (Drain ➔ Fill)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedTarget = val;
                                if ((val >= 5 && val <= 7) && durationSec == 0) durationSec = 120;
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Time Selection Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Scheduled Start Time:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                            foregroundColor: const Color(0xFF38BDF8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.access_time, size: 18),
                          label: Text(
                            _formatTimeStr(selectedHour, selectedMinute),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(hour: selectedHour, minute: selectedMinute),
                            );
                            if (picked != null) {
                              setModalState(() {
                                selectedHour = picked.hour;
                                selectedMinute = picked.minute;
                              });
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (selectedTarget == 7) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.bookmark_added_rounded, color: Color(0xFF38BDF8), size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Select Refill Preset for Schedule:',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (_savedPresets.isNotEmpty) ...[
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _savedPresets.map((p) {
                                  final isSel = customDrainSec == p.drainSec && customFillSec == p.fillSec && customSpeed == p.fillSpeed;
                                  return ChoiceChip(
                                    avatar: isSel ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0F172A), size: 15) : null,
                                    label: Text('${p.volumeChipLabel} (${p.name})'),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF38BDF8),
                                    backgroundColor: const Color(0xFF1E293B),
                                    labelStyle: TextStyle(
                                      color: isSel ? const Color(0xFF0F172A) : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                    side: BorderSide(
                                      color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                                      width: isSel ? 1.5 : 1.0,
                                    ),
                                    onSelected: (_) {
                                      setModalState(() {
                                        customDrainSec = p.drainSec;
                                        customFillSec = p.fillSec;
                                        customSpeed = p.fillSpeed;
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),

                              // Active Selected Preset Details Summary Card
                              Builder(
                                builder: (context) {
                                  final selPreset = _savedPresets.firstWhere(
                                    (p) => customDrainSec == p.drainSec && customFillSec == p.fillSec && customSpeed == p.fillSpeed,
                                    orElse: () => _savedPresets.first,
                                  );
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.water_drop_rounded, color: Color(0xFF34D399), size: 16),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Schedule Preset: ${selPreset.name}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '💧 Volume: ${selPreset.volumeMl} mL (~${selPreset.calculatedLiters.toStringAsFixed(2)} L)\n'
                                          '🌊 Drain Pump #1: ${selPreset.drainSec}s @ ${selPreset.drainSpeed}%\n'
                                          '⏸️ Settle Pause: ${selPreset.pauseSec}s delay\n'
                                          '💧 Fill Pump #2: ${selPreset.fillSec}s @ ${selPreset.fillSpeed}%',
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // Target State Switch
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Target Action State:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: true, label: Text('Turn ON')),
                              ButtonSegment(value: false, label: Text('Turn OFF')),
                            ],
                            selected: {targetState},
                            onSelectionChanged: (set) {
                              setModalState(() => targetState = set.first);
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Duration Input & Slider (Auto Off / Drinker Cycle)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (selectedTarget == 5 || selectedTarget == 6) ? 'Drinker Cycle Duration:' : 'Auto Off Duration:',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  durationSec == 0 ? 'Indefinite (Runs continuously)' : '$durationSec sec (${(durationSec / 60).toStringAsFixed(1)} mins)',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 100,
                            height: 40,
                            child: TextField(
                              controller: secInputCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              decoration: InputDecoration(
                                suffixText: 's',
                                suffixStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
                              ),
                              onChanged: (val) {
                                final parsed = int.tryParse(val);
                                if (parsed != null && parsed >= 0) {
                                  setModalState(() {
                                    durationSec = parsed;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Quick Duration Preset Chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildDurationChip('0s (Off)', 0, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                          _buildDurationChip('15s', 15, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                          _buildDurationChip('30s', 30, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                          _buildDurationChip('60s (1m)', 60, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                          _buildDurationChip('120s (2m)', 120, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                          _buildDurationChip('300s (5m)', 300, durationSec, (val) {
                            setModalState(() {
                              durationSec = val;
                              secInputCtrl.text = val.toString();
                            });
                          }),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Slider(
                        value: durationSec.toDouble().clamp(0, 600),
                        min: 0,
                        max: 600,
                        divisions: 20,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (val) => setModalState(() {
                          durationSec = val.toInt();
                          secInputCtrl.text = durationSec.toString();
                        }),
                      ),

                      if (selectedTarget == 5 || selectedTarget == 6) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pump Flow Speed:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                            Text('$speedPercent%', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        Slider(
                          value: speedPercent.toDouble(),
                          min: 10,
                          max: 100,
                          divisions: 18,
                          activeColor: const Color(0xFF10B981),
                          onChanged: (val) => setModalState(() => speedPercent = val.toInt()),
                        ),
                      ],

                      const SizedBox(height: 14),
                    ],

                    // Days of Week Selection
                    const Text('Recurring Days of Week:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (idx) {
                        final isSel = days[idx];
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              days[idx] = !days[idx];
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white10),
                            ),
                            child: Text(
                              _dayAbbrs[idx],
                              style: TextStyle(
                                color: isSel ? Colors.white : const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          isEditing ? 'Save Schedule Changes' : 'Create Schedule Slot',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          int mask = 0;
                          for (int i = 0; i < 7; i++) {
                            if (days[i]) mask |= (1 << i);
                          }

                          final newSched = HardwareSchedule(
                            id: slotId,
                            target: selectedTarget,
                            hour: selectedHour,
                            minute: selectedMinute,
                            targetState: targetState,
                            rawState: selectedTarget == 7 ? customDrainSec : (targetState ? 1 : 0),
                            durationSec: selectedTarget == 7 ? customFillSec : durationSec,
                            speedPercent: selectedTarget == 7 ? customSpeed : speedPercent,
                            daysMask: mask,
                            enabled: enabled,
                          );

                          _deletedSlotIds.remove(slotId);
                          await _apiService.syncPhoneTime(widget.deviceUrl);
                          await _apiService.setHardwareSchedule(widget.deviceUrl, newSched);
                          LogService().addLog(
                            isEditing ? '📅 Schedule Slot #${slotId + 1} Updated' : '📅 Schedule Slot #${slotId + 1} Created',
                            'Target: ${_getTargetName(selectedTarget)} at ${_formatTimeStr(selectedHour, selectedMinute)}',
                            type: 'schedule',
                          );
                          _loadSchedules();
                          widget.onRefreshNeeded?.call();
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

  int _firstAvailableSlotId() {
    if (_scheduleData == null) return 0;
    for (int i = 0; i < 8; i++) {
      final match = _scheduleData!.schedules.where((s) => s.id == i).firstOrNull;
      if (match == null || match.target <= 0 || match.daysMask <= 0 || !match.enabled || _deletedSlotIds.contains(match.id)) return i;
    }
    return 0;
  }

  String _formatTimeStr(int hour, int minute) {
    final tod = TimeOfDay(hour: hour, minute: minute);
    final hStr = tod.hourOfPeriod == 0 ? '12' : tod.hourOfPeriod.toString().padLeft(2, '0');
    final mStr = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hStr:$mStr $period';
  }

  String _getTargetName(int target) {
    switch (target) {
      case 1:
        return 'Relay 1 (Lamp)';
      case 2:
        return 'Relay 2 (Fan)';
      case 3:
        return 'Relay 3 (Auxiliary)';
      case 4:
        return 'Relay 4 (Aux/Gate)';
      case 5:
        return '🌊 Water Pump #1 (OUT1/OUT2)';
      case 6:
        return '🌊 3V Submersible Pump #2 (OUT3/OUT4)';
      case 7:
        return '✨ Flush & Refill (Drain ➔ Fill)';
      default:
        return 'Device $target';
    }
  }

  void showAddScheduleDialog({int targetId = 7}) {
    _showAddEditScheduleDialog(targetId: targetId);
  }

  @override
  Widget build(BuildContext context) {
    final allSchedules = _scheduleData?.schedules ?? [];
    final validSchedules = allSchedules
        .where((s) => s.target > 0 && s.daysMask > 0 && !_deletedSlotIds.contains(s.id))
        .toList();
    final filteredSchedules = widget.targetFilter == 0
        ? validSchedules
        : (widget.targetFilter == 5 || widget.targetFilter == 6 || widget.targetFilter == 7
            ? validSchedules.where((s) => s.target == widget.targetFilter || s.target == 7).toList()
            : validSchedules.where((s) => s.target == widget.targetFilter).toList());

    final activeCount = filteredSchedules.where((s) => s.enabled).length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.schedule, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (widget.targetFilter == 5 || widget.targetFilter == 6 || widget.targetFilter == 7)
                                ? 'Automatic Drinker Schedules'
                                : 'Hardware Schedule Manager',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            '$activeCount active hardware schedule(s)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF10B981), size: 28),
                tooltip: 'Add New Schedule',
                onPressed: () => _showAddEditScheduleDialog(targetId: widget.targetFilter != 0 ? widget.targetFilter : 7),
              ),
            ],
          ),

          // Board Clock Info Bar
          if (_scheduleData != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_filled, color: Color(0xFF6EE7B7), size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Board Time: ${_scheduleData!.currentTime.isEmpty ? "Syncing..." : _scheduleData!.currentTime}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSyncingTime ? null : _syncPhoneClock,
                    child: Text(
                      _isSyncingTime ? 'Syncing...' : 'Sync Phone Time',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Schedules List
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ),
            )
          else if (filteredSchedules.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.event_note, color: Color(0xFF64748B), size: 36),
                  SizedBox(height: 8),
                  Text(
                    'No Hardware Schedules Found',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap + above to create a 24/7 hardware schedule on NodeMCU.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: filteredSchedules.map((sched) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sched.enabled ? const Color(0xFF38BDF8).withValues(alpha: 0.3) : Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: sched.enabled
                              ? (sched.targetState
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : const Color(0xFFEF4444).withValues(alpha: 0.15))
                              : const Color(0xFF64748B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          sched.target == 7
                              ? Icons.autorenew_rounded
                              : ((sched.target == 5 || sched.target == 6) ? Icons.water_drop : Icons.flash_on),
                          color: sched.enabled
                              ? (sched.targetState ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                              : const Color(0xFF64748B),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Text(
                                  _formatTimeStr(sched.hour, sched.minute),
                                  style: TextStyle(
                                    color: sched.enabled ? Colors.white : const Color(0xFF94A3B8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: sched.enabled
                                        ? (sched.target == 7
                                            ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
                                            : (sched.targetState
                                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                                : const Color(0xFFEF4444).withValues(alpha: 0.2)))
                                        : Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sched.enabled
                                        ? (sched.target == 7 ? 'FLUSH & REFILL' : (sched.targetState ? 'TURN ON' : 'TURN OFF'))
                                        : 'PAUSED',
                                    style: TextStyle(
                                      color: sched.enabled
                                          ? (sched.target == 7
                                              ? const Color(0xFF38BDF8)
                                              : (sched.targetState ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5)))
                                          : const Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Builder(
                              builder: (context) {
                                final slotDrainSec = (sched.target == 7 && sched.rawState > 0) ? sched.rawState : _savedDrainSec;
                                final slotFillSec = (sched.target == 7 && sched.durationSec > 0) ? sched.durationSec : _savedFillSec;
                                final slotSpeed = (sched.target == 7 && sched.speedPercent > 0) ? sched.speedPercent : _savedFillSpeed;
                                final slotLiters = (slotFillSec / 60.0) * _savedPumpLpm;

                                return Text(
                                  '${_getTargetName(sched.target)}${sched.target == 7 ? " • ${slotDrainSec}s drain ➔ ${_savedPauseSec}s pause ➔ ${slotFillSec}s fill (~${slotLiters.toStringAsFixed(2)}L) @ $slotSpeed% speed" : (sched.durationSec > 0 ? " • ${sched.durationSec}s auto-off" : " • Indefinite")}${sched.target >= 5 && sched.target <= 6 ? " • ${sched.speedPercent}% speed" : ""}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: sched.enabled,
                        activeThumbColor: const Color(0xFF10B981),
                        onChanged: (val) async {
                          final updatedSched = HardwareSchedule(
                            id: sched.id,
                            target: sched.target,
                            hour: sched.hour,
                            minute: sched.minute,
                            targetState: sched.targetState,
                            rawState: sched.rawState,
                            durationSec: sched.durationSec,
                            speedPercent: sched.speedPercent,
                            daysMask: sched.daysMask,
                            enabled: val,
                          );
                          final newData = await _apiService.setHardwareSchedule(widget.deviceUrl, updatedSched);
                          if (mounted && newData != null) {
                            setState(() {
                              _scheduleData = newData;
                            });
                          } else {
                            _loadSchedules();
                          }
                          widget.onRefreshNeeded?.call();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF38BDF8), size: 18),
                        onPressed: () => _showAddEditScheduleDialog(existingSchedule: sched),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                        onPressed: () async {
                          setState(() {
                            _deletedSlotIds.add(sched.id);
                          });
                          LogService().addLog(
                            '🗑️ Schedule Slot #${sched.id + 1} Deleted',
                            'Target: ${_getTargetName(sched.target)}',
                            type: 'schedule',
                          );
                          final newData = await _apiService.deleteHardwareSchedule(widget.deviceUrl, sched.id);
                          if (mounted) {
                            if (newData != null) {
                              setState(() {
                                _scheduleData = newData;
                              });
                            } else {
                              _loadSchedules();
                            }
                            widget.onRefreshNeeded?.call();
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDurationChip(String label, int value, int currentSec, Function(int) onSelect) {
    final isSel = currentSec == value;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

}
