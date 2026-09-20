import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';

class RelayCardWidget extends StatefulWidget {
  final int channel;
  final String label;
  final bool isOn;
  final TimerInfo? timerInfo;
  final InchingInfo? inchingInfo;
  final Function(bool) onToggle;
  final Function(int seconds, bool targetState) onSetTimer;
  final VoidCallback onCancelTimer;
  final Function(bool enable, int durationSec) onToggleInching;
  final VoidCallback onTapCard;

  const RelayCardWidget({
    Key? key,
    required this.channel,
    required this.label,
    required this.isOn,
    required this.timerInfo,
    required this.inchingInfo,
    required this.onToggle,
    required this.onSetTimer,
    required this.onCancelTimer,
    required this.onToggleInching,
    required this.onTapCard,
  }) : super(key: key);

  @override
  State<RelayCardWidget> createState() => _RelayCardWidgetState();
}

class _RelayCardWidgetState extends State<RelayCardWidget> {
  String _displayLabel = '';

  @override
  void initState() {
    super.initState();
    _displayLabel = widget.label;
    _loadCustomLabel();
  }

  Future<void> _loadCustomLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('custom_label_ch_${widget.channel}');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() {
        _displayLabel = saved;
      });
    }
  }

  String _formatSeconds(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasTimer = widget.timerInfo != null && widget.timerInfo!.active;
    final isPageInching = widget.inchingInfo != null && widget.inchingInfo!.enabled;

    return GestureDetector(
      onTap: widget.onTapCard,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isOn
                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                : (hasTimer
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08)),
            width: 1.5,
          ),
          boxShadow: widget.isOn
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Channel ${widget.channel}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (isPageInching) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF818CF8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'PULSE ${widget.inchingInfo!.durationSec}s',
                          style: const TextStyle(
                            color: Color(0xFFA5B4FC),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.isOn
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.isOn
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : const Color(0xFFEF4444).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        widget.isOn ? 'ACTIVE' : 'OFF',
                        style: TextStyle(
                          color: widget.isOn ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Description Label & Switch Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _displayLabel,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: widget.isOn,
                    activeTrackColor: const Color(0xFF10B981),
                    onChanged: (val) => widget.onToggle(val),
                  ),
                ),
              ],
            ),

            // Active Countdown Timer Banner
            if (hasTimer) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.timer, size: 16, color: Color(0xFFFCD34D)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Auto-${widget.timerInfo!.targetState ? "ON" : "OFF"} in ${_formatSeconds(widget.timerInfo!.remaining)}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFCD34D),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onCancelTimer,
                      child: const Text(
                        'Cancel',
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
          ],
        ),
      ),
    );
  }
}
