import 'package:flutter/material.dart';
import '../models/relay_status.dart';

class PumpCardWidget extends StatefulWidget {
  final PumpStatus? pumpStatus;
  final Function(bool state, int speed, String direction) onUpdatePump;
  final Function(int seconds, bool targetState, int speed, String direction)? onSetTimer;
  final String title;
  final String subtitle;
  final VoidCallback? onEditTitle;

  const PumpCardWidget({
    Key? key,
    required this.pumpStatus,
    required this.onUpdatePump,
    this.onSetTimer,
    this.title = '12V Submersible Water Pump',
    this.subtitle = 'L298N Dual-Channel H-Bridge Driver',
    this.onEditTitle,
  }) : super(key: key);

  @override
  State<PumpCardWidget> createState() => _PumpCardWidgetState();
}

class _PumpCardWidgetState extends State<PumpCardWidget> with SingleTickerProviderStateMixin {
  late double _currentSpeed;
  late String _currentDir;
  late AnimationController _pulseController;
  late TextEditingController _manualSecController;
  int _maxRemainingSec = 0;

  @override
  void initState() {
    super.initState();
    _currentSpeed = (widget.pumpStatus?.speed ?? 80).toDouble();
    _currentDir = widget.pumpStatus?.direction ?? 'fwd';
    _manualSecController = TextEditingController(text: '30');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _manualSecController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PumpCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pumpStatus != null) {
      if (widget.pumpStatus?.speed != oldWidget.pumpStatus?.speed) {
        _currentSpeed = widget.pumpStatus!.speed.toDouble();
      }
      if (widget.pumpStatus?.direction != oldWidget.pumpStatus?.direction) {
        _currentDir = widget.pumpStatus!.direction;
      }
    }
  }

  String _formatRemainingTime(int sec) {
    int m = sec ~/ 60;
    int s = sec % 60;
    if (m > 0) {
      return '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.pumpStatus?.active ?? false;
    final pwmValue = widget.pumpStatus?.pwm ?? ((_currentSpeed / 100) * 1023).round();
    final isFwd = _currentDir == 'fwd';
    final timer = widget.pumpStatus?.timer;
    final hasActiveTimer = timer != null && timer.active && timer.remaining > 0;

    if (hasActiveTimer) {
      if (timer.remaining > _maxRemainingSec) {
        _maxRemainingSec = timer.remaining;
      }
    } else {
      _maxRemainingSec = 0;
    }

    final double progressFactor = (hasActiveTimer && _maxRemainingSec > 0)
        ? (timer.remaining / _maxRemainingSec.toDouble()).clamp(0.02, 1.0)
        : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
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
              blurRadius: 18,
              spreadRadius: 2,
            ),
        ],
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
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.water_drop, color: Color(0xFF38BDF8), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (widget.onEditTitle != null)
                                GestureDetector(
                                  onTap: widget.onEditTitle,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.edit, color: Color(0xFF38BDF8), size: 14),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Main Toggle Switch
              Switch(
                value: isActive,
                activeThumbColor: const Color(0xFF38BDF8),
                activeTrackColor: const Color(0xFF0EA5E9).withValues(alpha: 0.4),
                inactiveThumbColor: const Color(0xFF94A3B8),
                inactiveTrackColor: const Color(0xFF334155),
                onChanged: (val) {
                  if (val) {
                    final sec = int.tryParse(_manualSecController.text) ?? 0;
                    if (sec > 0 && widget.onSetTimer != null) {
                      widget.onSetTimer!(sec, false, _currentSpeed.round(), _currentDir);
                    } else {
                      widget.onUpdatePump(true, _currentSpeed.round(), _currentDir);
                    }
                  } else {
                    if (widget.onSetTimer != null) {
                      widget.onSetTimer!(0, false, _currentSpeed.round(), _currentDir);
                    }
                    widget.onUpdatePump(false, _currentSpeed.round(), _currentDir);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 🌊 ONGOING AUTOMATIC DRINKER & COUNTDOWN ANIMATION BANNER
          if (isActive || hasActiveTimer) ...[
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulseVal = _pulseController.value;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Color.lerp(
                        const Color(0xFF0EA5E9),
                        const Color(0xFF38BDF8),
                        pulseVal,
                      )!.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.15 + (pulseVal * 0.15)),
                        blurRadius: 12 + (pulseVal * 8),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Animated Pulsing Water Drop Icon
                          Transform.scale(
                            scale: 1.0 + (pulseVal * 0.1),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF38BDF8).withValues(alpha: 0.5 * pulseVal),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.water_drop, color: Color(0xFF38BDF8), size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                      ),
                                      child: const Text(
                                        'AUTO DRINKER RUNNING',
                                        style: TextStyle(
                                          color: Color(0xFF6EE7B7),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (hasActiveTimer)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'COUNTDOWN',
                                          style: TextStyle(
                                            color: Color(0xFFFBBF24),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasActiveTimer
                                      ? 'Scheduled auto-off countdown in progress...'
                                      : 'Pigeon drinker actively dispensing water...',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (hasActiveTimer) ...[
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'REMAINING',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _formatRemainingTime(timer.remaining),
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Animated Time-Based Water Flow Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              color: const Color(0xFF1E293B),
                            ),
                            if (hasActiveTimer)
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 800),
                                    curve: Curves.easeOutCubic,
                                    height: 8,
                                    width: (constraints.maxWidth * progressFactor).clamp(4.0, constraints.maxWidth),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8), Color(0xFF6EE7B7)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF38BDF8).withValues(alpha: 0.5 * pulseVal),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            else
                              FractionallySizedBox(
                                widthFactor: (0.3 + (pulseVal * 0.7)),
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8), Color(0xFF6EE7B7)],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],

          // Flow Speed & PWM Status Display Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT FLOW SPEED',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${_currentSpeed.round()}%',
                          style: TextStyle(
                            color: isActive ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                : const Color(0xFFEF4444).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isActive ? (isFwd ? 'FORWARD' : 'REVERSE') : 'OFF',
                            style: TextStyle(
                              color: isActive
                                  ? (isFwd ? const Color(0xFF6EE7B7) : const Color(0xFF38BDF8))
                                  : const Color(0xFFFCA5A5),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'PWM SIGNAL',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PWM: $pwmValue / 1023',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Flow Speed Slider
          Row(
            children: [
              const Icon(Icons.speed, color: Color(0xFF64748B), size: 16),
              const SizedBox(width: 6),
              const Text(
                'Adjust Flow Rate:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_currentSpeed.round()}% Speed',
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF38BDF8),
              inactiveTrackColor: const Color(0xFF334155),
              thumbColor: const Color(0xFF38BDF8),
              overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
              trackHeight: 6,
            ),
            child: Slider(
              value: _currentSpeed,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (newVal) {
                setState(() {
                  _currentSpeed = newVal;
                });
              },
              onChangeEnd: (finalVal) {
                final speed = finalVal.round();
                widget.onUpdatePump(speed > 0, speed, _currentDir);
              },
            ),
          ),

          const SizedBox(height: 6),

          // Quick Speed Presets
          Row(
            children: [
              _buildPresetButton('25% Low', 25, isActive),
              const SizedBox(width: 8),
              _buildPresetButton('50% Med', 50, isActive),
              const SizedBox(width: 8),
              _buildPresetButton('75% High', 75, isActive),
              const SizedBox(width: 8),
              _buildPresetButton('100% Max', 100, isActive),
            ],
          ),

          // ⏱️ MANUAL TIMED RUN & PRESET SECONDS CONTROL
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.timer, color: Color(0xFFF59E0B), size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Manual Run Duration (Sec):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 90,
                height: 36,
                child: TextField(
                  controller: _manualSecController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  decoration: InputDecoration(
                    suffixText: 's',
                    suffixStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
                  ),
                  onChanged: (val) {
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Quick Manual Preset Seconds Buttons
          Row(
            children: [
              _buildManualTimerPresetBtn('15s', 15),
              const SizedBox(width: 6),
              _buildManualTimerPresetBtn('30s', 30),
              const SizedBox(width: 6),
              _buildManualTimerPresetBtn('60s', 60),
              const SizedBox(width: 6),
              _buildManualTimerPresetBtn('120s', 120),
              const SizedBox(width: 6),
              _buildManualTimerPresetBtn('300s', 300),
            ],
          ),

          const SizedBox(height: 10),

          if (hasActiveTimer)
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.cancel, color: Colors.white, size: 16),
                label: const Text('Cancel Active Timer & Stop Pump', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  widget.onSetTimer?.call(0, false, _currentSpeed.round(), _currentDir);
                  widget.onUpdatePump(false, _currentSpeed.round(), _currentDir);
                },
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isActive ? Icons.timer : Icons.play_arrow, color: const Color(0xFF0F172A), size: 18),
                label: Text(
                  isActive
                      ? 'Apply Auto-Off Timer (${_manualSecController.text.isEmpty ? "0" : _manualSecController.text}s)'
                      : 'Turn ON Pump (${_manualSecController.text.isEmpty ? "Indefinite" : "${_manualSecController.text}s Timer"})',
                  style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () {
                  final sec = int.tryParse(_manualSecController.text) ?? 0;
                  if (sec > 0 && widget.onSetTimer != null) {
                    widget.onSetTimer!(sec, false, _currentSpeed.round(), _currentDir);
                  } else {
                    widget.onUpdatePump(true, _currentSpeed.round(), _currentDir);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManualTimerPresetBtn(String label, int seconds) {
    final currentSec = int.tryParse(_manualSecController.text) ?? 0;
    final isSelected = currentSec == seconds;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _manualSecController.text = seconds.toString();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B).withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFFBBF24),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, int value, bool isPumpActive) {
    final isSelected = _currentSpeed.round() == value && isPumpActive;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _currentSpeed = value.toDouble();
          });
          widget.onUpdatePump(true, value, _currentDir);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0EA5E9) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class SmallPumpCardWidget extends StatelessWidget {
  final int pumpId;
  final String title;
  final String subtitle;
  final PumpStatus? pumpStatus;
  final Function(bool state, int speed, String direction) onUpdatePump;
  final VoidCallback onTapDetails;

  const SmallPumpCardWidget({
    Key? key,
    required this.pumpId,
    required this.title,
    required this.subtitle,
    required this.pumpStatus,
    required this.onUpdatePump,
    required this.onTapDetails,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isActive = pumpStatus?.active ?? false;
    final rawSpeed = pumpStatus?.speed ?? 80;
    final speed = rawSpeed < 10 ? 80 : rawSpeed;
    final timer = pumpStatus?.timer;
    final hasActiveTimer = timer != null && timer.active && timer.remaining > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
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
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.water_drop,
                  color: isActive ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                  size: 20,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Color(0xFF38BDF8), size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Configure Pump Settings',
                onPressed: onTapDetails,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFF64748B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isActive ? 'RUNNING ($speed%)' : 'OFF / IDLE',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    if (hasActiveTimer) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⏳ ${timer.remaining}s left',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: isActive,
                activeThumbColor: const Color(0xFF10B981),
                inactiveThumbColor: const Color(0xFF64748B),
                inactiveTrackColor: const Color(0xFF334155),
                onChanged: (val) {
                  onUpdatePump(val, speed, pumpStatus?.direction ?? 'fwd');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

