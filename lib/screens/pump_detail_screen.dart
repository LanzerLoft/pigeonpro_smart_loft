import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';
import '../services/log_service.dart';
import '../widgets/drinker_schedule_widget.dart';

class PumpDetailScreen extends StatefulWidget {
  final int pumpId; // 1 or 2
  final String initialName;
  final PumpStatus? pumpStatus;
  final String deviceUrl;
  final VoidCallback onRefresh;
  final Function(String newName) onNameChanged;

  const PumpDetailScreen({
    Key? key,
    required this.pumpId,
    required this.initialName,
    required this.pumpStatus,
    required this.deviceUrl,
    required this.onRefresh,
    required this.onNameChanged,
  }) : super(key: key);

  @override
  State<PumpDetailScreen> createState() => _PumpDetailScreenState();
}

class _PumpDetailScreenState extends State<PumpDetailScreen> {
  final Esp8266Service _apiService = Esp8266Service();
  late String _pumpName;
  late double _currentSpeed;
  late bool _isActive;
  TimerInfo? _timerInfo;
  final TextEditingController _timerSecController = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _pumpName = widget.initialName;
    int rawSpeed = widget.pumpStatus?.speed ?? 80;
    _currentSpeed = (rawSpeed < 10 ? 80 : rawSpeed).toDouble().clamp(10.0, 100.0);
    _isActive = widget.pumpStatus?.active ?? false;
    _timerInfo = widget.pumpStatus?.timer;
    _fetchLatestStatus();
  }

  @override
  void dispose() {
    _timerSecController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PumpDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pumpStatus != null) {
      if (widget.pumpStatus?.speed != oldWidget.pumpStatus?.speed) {
        int rawSpeed = widget.pumpStatus!.speed;
        if (rawSpeed >= 10) {
          _currentSpeed = rawSpeed.toDouble().clamp(10.0, 100.0);
        }
      }
      if (widget.pumpStatus?.active != oldWidget.pumpStatus?.active) {
        _isActive = widget.pumpStatus!.active;
      }
      if (widget.pumpStatus?.timer != oldWidget.pumpStatus?.timer) {
        _timerInfo = widget.pumpStatus?.timer;
      }
    }
  }

  Future<void> _fetchLatestStatus() async {
    final status = await _apiService.fetchStatus(widget.deviceUrl);
    if (mounted && status != null) {
      final pStatus = widget.pumpId == 1 ? status.pump : status.pump2;
      setState(() {
        if (pStatus != null) {
          _isActive = pStatus.active;
          _timerInfo = pStatus.timer;
          if (pStatus.speed >= 10) {
            _currentSpeed = pStatus.speed.toDouble().clamp(10.0, 100.0);
          }
        }
      });
    }
  }

  Future<void> _renamePumpDialog() async {
    final TextEditingController nameCtrl = TextEditingController(text: _pumpName);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Rename Pump #${widget.pumpId}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.pumpId == 1 ? 'Channel A (OUT1 / OUT2)' : 'Channel B (OUT3 / OUT4)',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Pump Display Name',
                  labelStyle: const TextStyle(color: Color(0xFF38BDF8)),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                if (newName.isNotEmpty) {
                  final navigator = Navigator.of(context);
                  final prefs = await SharedPreferences.getInstance();
                  final key = widget.pumpId == 1 ? 'custom_pump_1_name' : 'custom_pump_2_name';
                  await prefs.setString(key, newName);
                  if (mounted) {
                    setState(() => _pumpName = newName);
                    widget.onNameChanged(newName);
                  }
                  navigator.pop();
                }
              },
              child: const Text('Save Name', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updatePumpState(bool state, {int? speed}) async {
    final targetSpeed = speed ?? _currentSpeed.round();
    setState(() {
      _isActive = state;
    });

    if (widget.pumpId == 1) {
      await _apiService.setPumpState(widget.deviceUrl, state, targetSpeed);
    } else {
      await _apiService.setPump2State(widget.deviceUrl, state, targetSpeed);
    }
    LogService().addLog(
      state ? '🌊 $_pumpName Started' : '🛑 $_pumpName Stopped',
      'Flow speed set to $targetSpeed%',
      type: 'pump',
    );
    await _fetchLatestStatus();
    widget.onRefresh();
  }

  Future<void> _triggerTimer(int seconds, bool targetState) async {
    final speed = _currentSpeed.round();
    setState(() {
      _isActive = seconds > 0;
    });

    if (widget.pumpId == 1) {
      if (seconds > 0) {
        await _apiService.setPumpTimer(widget.deviceUrl, seconds, targetState, speed: speed);
      } else {
        await _apiService.setPumpTimer(widget.deviceUrl, 0, false);
        await _apiService.setPumpState(widget.deviceUrl, false, speed);
      }
    } else {
      if (seconds > 0) {
        await _apiService.setPump2Timer(widget.deviceUrl, seconds, targetState, speed: speed);
      } else {
        await _apiService.setPump2Timer(widget.deviceUrl, 0, false);
        await _apiService.setPump2State(widget.deviceUrl, false, speed);
      }
    }
    LogService().addLog(
      seconds > 0 ? '⏱️ $_pumpName Timer Set' : '🛑 $_pumpName Timer Cancelled',
      seconds > 0 ? 'Running for ${seconds}s @ $speed% speed' : 'Pump stopped',
      type: 'pump',
    );
    await _fetchLatestStatus();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isActive;
    final pwmValue = ((_currentSpeed / 100) * 1023).round();
    final timer = _timerInfo;
    final hasActiveTimer = timer != null && timer.active && timer.remaining > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          _pumpName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF38BDF8)),
            tooltip: 'Rename Pump',
            onPressed: _renamePumpDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (isActive || hasActiveTimer)
                      ? const Color(0xFF0EA5E9).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  if (isActive || hasActiveTimer)
                    BoxShadow(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFF64748B).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.water_drop,
                          color: isActive ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pumpName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.pumpId == 1
                                  ? 'Channel A • OUT1 (+) / OUT2 (-)'
                                  : 'Channel B • OUT3 (+) / OUT4 (-)',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                    : const Color(0xFF64748B).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isActive ? 'RUNNING @ ${_currentSpeed.round()}% ($pwmValue PWM)' : 'PUMP OFF / IDLE',
                                style: TextStyle(
                                  color: isActive ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isActive,
                        activeThumbColor: const Color(0xFF10B981),
                        activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                        inactiveThumbColor: const Color(0xFF64748B),
                        inactiveTrackColor: const Color(0xFF334155),
                        onChanged: (val) => _updatePumpState(val),
                      ),
                    ],
                  ),

                  if (hasActiveTimer) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Auto-Off Countdown Active',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Pump will automatically stop in ${timer.remaining}s',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
                              foregroundColor: const Color(0xFFFCA5A5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () => _triggerTimer(0, false),
                            child: const Text('Cancel Timer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Speed & Flow Rate Settings Card
            Container(
              padding: const EdgeInsets.all(18),
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
                          Icon(Icons.speed, color: Color(0xFF38BDF8), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Pump Speed Control',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Text(
                        '${_currentSpeed.round()}%',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: _currentSpeed.clamp(10.0, 100.0),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (val) {
                      setState(() => _currentSpeed = val);
                      _updatePumpState(isActive, speed: val.round());
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Drinker Timer Card
            Container(
              padding: const EdgeInsets.all(18),
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
                      Icon(Icons.hourglass_bottom, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Drinker Auto-Off Duration Timer',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Automatically turns pump off after the specified duration.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // Quick Duration Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [15, 30, 60, 120, 300].map((sec) {
                      return ChoiceChip(
                        label: Text('${sec}s ${sec >= 60 ? "(${sec ~/ 60}m)" : ""}'),
                        selected: _timerSecController.text == '$sec',
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF0F172A),
                        labelStyle: TextStyle(
                          color: _timerSecController.text == '$sec' ? const Color(0xFF0F172A) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        onSelected: (_) {
                          setState(() => _timerSecController.text = '$sec');
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _timerSecController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            labelText: 'Custom Seconds',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            suffixText: 'sec',
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Timer', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final sec = int.tryParse(_timerSecController.text) ?? 30;
                          _triggerTimer(sec, false);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Hardware Schedule Manager for this Pump
            DrinkerScheduleWidget(
              deviceUrl: widget.deviceUrl,
              targetFilter: widget.pumpId == 1 ? 5 : 6,
              onRefreshNeeded: widget.onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}
