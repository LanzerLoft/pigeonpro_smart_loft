import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';
import '../widgets/drinker_schedule_widget.dart';

class RelayDetailScreen extends StatefulWidget {
  final int channel;
  final String defaultLabel;
  final bool isOn;
  final TimerInfo? timerInfo;
  final InchingInfo? inchingInfo;
  final String deviceUrl;

  const RelayDetailScreen({
    Key? key,
    required this.channel,
    required this.defaultLabel,
    required this.isOn,
    required this.timerInfo,
    required this.inchingInfo,
    required this.deviceUrl,
  }) : super(key: key);

  @override
  State<RelayDetailScreen> createState() => _RelayDetailScreenState();
}

class _RelayDetailScreenState extends State<RelayDetailScreen> {
  final Esp8266Service _apiService = Esp8266Service();

  late bool _currentState;
  late String _customLabel;
  final TextEditingController _labelCtrl = TextEditingController();

  // List of Multiple Scheduled Tasks
  List<ScheduledTask> _schedules = [];

  // Custom Timer State
  int _timerHours = 0;
  int _timerMinutes = 0;
  int _timerSeconds = 0;

  // Inching State
  bool _inchingEnabled = false;
  int _inchingSec = 2;

  final List<String> _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _currentState = widget.isOn;
    _customLabel = widget.defaultLabel;
    _labelCtrl.text = widget.defaultLabel;
    if (widget.inchingInfo != null) {
      _inchingEnabled = widget.inchingInfo!.enabled;
      _inchingSec = widget.inchingInfo!.durationSec;
    }
    _loadData();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Custom Name
    final savedLabel = prefs.getString('custom_label_ch_${widget.channel}');
    if (savedLabel != null && savedLabel.isNotEmpty && mounted) {
      setState(() {
        _customLabel = savedLabel;
        _labelCtrl.text = savedLabel;
      });
    }

    // Load Multiple Scheduled Tasks
    final jsonString = prefs.getString('multiple_schedules_ch_${widget.channel}');
    if (jsonString != null && jsonString.isNotEmpty && mounted) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        setState(() {
          _schedules = decoded.map((item) => ScheduledTask.fromJson(item as Map<String, dynamic>)).toList();
        });
      } catch (e) {
        // Failed to decode schedules
      }
    }
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_schedules.map((s) => s.toJson()).toList());
    await prefs.setString('multiple_schedules_ch_${widget.channel}', jsonString);
    _syncClosestScheduleToBoard();
  }

  // Find closest enabled schedule and sync timer to ESP8266 board
  Future<void> _syncClosestScheduleToBoard() async {
    int minSeconds = 99999999;
    ScheduledTask? nextTask;

    final now = DateTime.now();

    for (var task in _schedules) {
      if (!task.enabled) continue;

      if (task.scheduleType == 'ONCE' && task.targetDateTime != null) {
        int diff = task.targetDateTime!.difference(now).inSeconds;
        if (diff > 0 && diff < minSeconds) {
          minSeconds = diff;
          nextTask = task;
        }
      } else if (task.scheduleType == 'WEEKLY') {
        int targetSec = _calculateNextRecurringSeconds(task.hour, task.minute, task.recurringDays);
        if (targetSec > 0 && targetSec < minSeconds) {
          minSeconds = targetSec;
          nextTask = task;
        }
      }
    }

    if (nextTask != null && minSeconds < 99999999) {
      await _apiService.setTimer(widget.deviceUrl, widget.channel, minSeconds, nextTask.targetState);
    }
  }

  int _calculateNextRecurringSeconds(int hour, int minute, List<bool> days) {
    final now = DateTime.now();
    int minSeconds = 99999999;
    int currentDayIndex = now.weekday % 7;

    for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
      if (days[dayIdx]) {
        int daysAhead = dayIdx - currentDayIndex;
        if (daysAhead < 0) daysAhead += 7;

        var targetDate = DateTime(now.year, now.month, now.day + daysAhead, hour, minute);

        if (targetDate.isBefore(now) || targetDate.isAtSameMomentAs(now)) {
          targetDate = targetDate.add(const Duration(days: 7));
        }

        int diff = targetDate.difference(now).inSeconds;
        if (diff < minSeconds) {
          minSeconds = diff;
        }
      }
    }
    return minSeconds;
  }

  Future<void> _saveCustomLabel(String newLabel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_label_ch_${widget.channel}', newLabel);
    if (mounted) {
      setState(() {
        _customLabel = newLabel;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Channel ${widget.channel} renamed to "$newLabel"')),
      );
    }
  }

  Future<void> _toggleState() async {
    final newState = !_currentState;
    setState(() {
      _currentState = newState;
    });
    await _apiService.toggleRelay(widget.deviceUrl, widget.channel, newState);
  }

  // Open "Add / Edit Schedule" Bottom Sheet
  void _showScheduleFormBottomSheet({ScheduledTask? existingTask}) {
    String tempType = existingTask?.scheduleType ?? 'ONCE';
    bool tempTargetState = existingTask?.targetState ?? true;
    DateTime? tempDateTime = existingTask?.targetDateTime;
    TimeOfDay? tempTime = existingTask != null ? TimeOfDay(hour: existingTask.hour, minute: existingTask.minute) : TimeOfDay.now();
    List<bool> tempDays = existingTask != null
        ? List.from(existingTask.recurringDays)
        : [false, false, false, false, false, false, false];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                        Text(
                          existingTask == null ? 'Add New Schedule' : 'Edit Schedule',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Schedule Mode Switcher (Once vs Weekly)
                    Row(
                      children: [
                        const Text('Type:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('Once'),
                          selected: tempType == 'ONCE',
                          selectedColor: const Color(0xFF38BDF8),
                          backgroundColor: const Color(0xFF334155),
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (val) => setModalState(() => tempType = 'ONCE'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Weekly Repeat'),
                          selected: tempType == 'WEEKLY',
                          selectedColor: const Color(0xFF38BDF8),
                          backgroundColor: const Color(0xFF334155),
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (val) => setModalState(() => tempType = 'WEEKLY'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Target Action (Auto ON vs Auto OFF)
                    Row(
                      children: [
                        const Text('Action:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('Turn ON'),
                          selected: tempTargetState == true,
                          selectedColor: const Color(0xFF10B981),
                          backgroundColor: const Color(0xFF334155),
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (val) => setModalState(() => tempTargetState = true),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Turn OFF'),
                          selected: tempTargetState == false,
                          selectedColor: const Color(0xFFEF4444),
                          backgroundColor: const Color(0xFF334155),
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          onSelected: (val) => setModalState(() => tempTargetState = false),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (tempType == 'ONCE') ...[
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: tempDateTime ?? now,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (date == null) return;
                          if (!context.mounted) return;
                          final time = await showTimePicker(context: context, initialTime: tempTime ?? TimeOfDay.now());
                          if (time == null) return;

                          setModalState(() {
                            tempDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                            tempTime = time;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tempDateTime == null
                                    ? 'Tap to select Date & Time'
                                    : '${tempDateTime!.year}-${tempDateTime!.month.toString().padLeft(2, '0')}-${tempDateTime!.day.toString().padLeft(2, '0')} at ${tempTime!.hour.toString().padLeft(2, '0')}:${tempTime!.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Icon(Icons.calendar_today, color: Color(0xFF38BDF8), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      const Text('Repeat Days:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: List.generate(7, (index) {
                            final isSel = tempDays[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: GestureDetector(
                                onTap: () => setModalState(() => tempDays[index] = !tempDays[index]),
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSel ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
                                    border: Border.all(color: isSel ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.15)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _dayNames[index],
                                      style: TextStyle(color: isSel ? Colors.white : const Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () async {
                          final time = await showTimePicker(context: context, initialTime: tempTime ?? TimeOfDay.now());
                          if (time != null) setModalState(() => tempTime = time);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tempTime == null
                                    ? 'Select Time'
                                    : 'At ${tempTime!.hour.toString().padLeft(2, '0')}:${tempTime!.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Icon(Icons.access_time, color: Color(0xFF38BDF8), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          existingTask == null ? 'Save Schedule' : 'Update Schedule',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          if (tempType == 'ONCE' && tempDateTime == null) return;
                          if (tempType == 'WEEKLY' && (!tempDays.contains(true) || tempTime == null)) return;

                          final task = ScheduledTask(
                            id: existingTask?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                            channel: widget.channel,
                            scheduleType: tempType,
                            targetDateTime: tempDateTime,
                            recurringDays: tempDays,
                            hour: tempTime!.hour,
                            minute: tempTime!.minute,
                            targetState: tempTargetState,
                            enabled: existingTask?.enabled ?? true,
                          );

                          setState(() {
                            if (existingTask != null) {
                              final index = _schedules.indexWhere((s) => s.id == existingTask.id);
                              if (index != -1) _schedules[index] = task;
                            } else {
                              _schedules.add(task);
                            }
                          });
                          _saveSchedules();
                          Navigator.pop(context);
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

  // Confirm Schedule Deletion Dialog
  void _confirmDeleteSchedule(ScheduledTask task) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Delete Schedule?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to delete this schedule?\n\n'
            '${task.targetState ? "AUTO ON" : "AUTO OFF"} • ${_getScheduleSubtitle(task)}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _schedules.removeWhere((item) => item.id == task.id);
                });
                _saveSchedules();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Schedule deleted')),
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyCustomTimer() async {
    final totalSec = (_timerHours * 3600) + (_timerMinutes * 60) + _timerSeconds;
    if (totalSec <= 0) return;

    final success = await _apiService.setTimer(
      widget.deviceUrl,
      widget.channel,
      totalSec,
      !_currentState,
    );

    if (success && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _cancelTimer() async {
    await _apiService.setTimer(widget.deviceUrl, widget.channel, 0, false);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  String _formatSeconds(int totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _getScheduleSubtitle(ScheduledTask task) {
    final timeStr = '${task.hour.toString().padLeft(2, '0')}:${task.minute.toString().padLeft(2, '0')}';
    if (task.scheduleType == 'ONCE' && task.targetDateTime != null) {
      final dt = task.targetDateTime!;
      return 'Single: ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} at $timeStr';
    } else {
      List<String> activeDays = [];
      for (int i = 0; i < 7; i++) {
        if (task.recurringDays[i]) activeDays.add(_dayNames[i]);
      }
      return 'Every ${activeDays.join(', ')} at $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(_customLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF38BDF8)),
            tooltip: 'Rename Channel',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E293B),
                    title: const Text('Rename Channel', style: TextStyle(color: Colors.white, fontSize: 16)),
                    content: TextField(
                      controller: _labelCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter new channel name',
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                        onPressed: () {
                          _saveCustomLabel(_labelCtrl.text.trim());
                          Navigator.pop(context);
                        },
                        child: const Text('Save Name', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Big Neon Switch Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _currentState
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 2,
                ),
                boxShadow: _currentState
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 4,
                        )
                      ]
                    : [],
              ),
              child: Column(
                children: [
                  Text(
                    'Channel ${widget.channel}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _toggleState,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentState ? const Color(0xFF10B981) : const Color(0xFF334155),
                        boxShadow: _currentState
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                )
                              ]
                            : [],
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        size: 44,
                        color: _currentState ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _currentState ? 'ACTIVE / ON' : 'POWERED OFF',
                    style: TextStyle(
                      color: _currentState ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Active Countdown Timer Banner (if any)
            if (widget.timerInfo != null && widget.timerInfo!.active)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, color: Color(0xFFFCD34D), size: 22),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-${widget.timerInfo!.targetState ? "ON" : "OFF"} in Progress',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Remaining: ${_formatSeconds(widget.timerInfo!.remaining)}',
                              style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: _cancelTimer,
                      child: const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
              ),

            DrinkerScheduleWidget(
              deviceUrl: widget.deviceUrl,
              targetFilter: widget.channel,
            ),

            const SizedBox(height: 16),

            // 📅 MULTIPLE SCHEDULES MANAGER CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.calendar_month, color: Color(0xFF38BDF8), size: 20),
                          SizedBox(width: 6),
                          Text(
                            'Schedules Manager',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add, size: 16, color: Colors.white),
                        label: const Text('Add Schedule', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _showScheduleFormBottomSheet(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_schedules.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No active schedules set.\nTap "Add Schedule" to set any date & time!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ..._schedules.map((task) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: task.targetState
                                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                          : const Color(0xFFEF4444).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      task.targetState ? 'AUTO ON' : 'AUTO OFF',
                                      style: TextStyle(
                                        color: task.targetState ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getScheduleSubtitle(task),
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Switch(
                                  value: task.enabled,
                                  activeTrackColor: const Color(0xFF38BDF8),
                                  onChanged: (val) {
                                    setState(() {
                                      task.enabled = val;
                                    });
                                    _saveSchedules();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 18),
                                  onPressed: () => _showScheduleFormBottomSheet(existingTask: task),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () => _confirmDeleteSchedule(task),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ⏱️ Countdown Timer Picker
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.hourglass_bottom, color: Color(0xFFF59E0B), size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Quick Countdown Timer',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNumberPicker('Hours', _timerHours, (val) => setState(() => _timerHours = val), 24),
                      _buildNumberPicker('Mins', _timerMinutes, (val) => setState(() => _timerMinutes = val), 60),
                      _buildNumberPicker('Secs', _timerSeconds, (val) => setState(() => _timerSeconds = val), 60),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.timer, color: Colors.white, size: 16),
                      label: const Text(
                        'Start Countdown Timer',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _applyCustomTimer,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ⚡ Inching Pulse Mode Configuration Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bolt, color: Color(0xFF818CF8), size: 20),
                          SizedBox(width: 6),
                          Text(
                            'Inching Pulse Mode',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Switch(
                        value: _inchingEnabled,
                        activeTrackColor: const Color(0xFF818CF8),
                        onChanged: (val) async {
                          setState(() {
                            _inchingEnabled = val;
                          });
                          await _apiService.setInching(widget.deviceUrl, widget.channel, val, _inchingSec);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Automatically turns OFF after a brief pulse duration (useful for gates, garage doors, and triggers).',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pulse Duration:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF94A3B8), size: 20),
                            onPressed: _inchingSec > 1
                                ? () async {
                                    setState(() => _inchingSec--);
                                    await _apiService.setInching(widget.deviceUrl, widget.channel, _inchingEnabled, _inchingSec);
                                  }
                                : null,
                          ),
                          Text('$_inchingSec sec', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF94A3B8), size: 20),
                            onPressed: () async {
                              setState(() => _inchingSec++);
                              await _apiService.setInching(widget.deviceUrl, widget.channel, _inchingEnabled, _inchingSec);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPicker(String label, int val, Function(int) onChanged, int maxVal) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: val,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              items: List.generate(maxVal, (i) => i).map((itemVal) {
                return DropdownMenuItem<int>(
                  value: itemVal,
                  child: Text(itemVal.toString().padLeft(2, '0')),
                );
              }).toList(),
              onChanged: (newVal) {
                if (newVal != null) onChanged(newVal);
              },
            ),
          ),
        ),
      ],
    );
  }
}
