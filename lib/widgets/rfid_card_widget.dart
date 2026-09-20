import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/relay_status.dart';

class RfidCardWidget extends StatelessWidget {
  final RfidStatus? rfidStatus;
  final VoidCallback? onClearScan;

  const RfidCardWidget({
    Key? key,
    required this.rfidStatus,
    this.onClearScan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasTag = rfidStatus != null && rfidStatus!.tagHex.isNotEmpty;
    final tagHex = hasTag ? rfidStatus!.tagHex : '-- -- -- --';
    final tagDec = hasTag ? rfidStatus!.tagDec : '--';
    final scans = rfidStatus?.scans ?? 0;
    final secondsAgo = rfidStatus?.secondsAgo ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasTag
              ? const Color(0xFFA855F7).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: [
          if (hasTag)
            BoxShadow(
              color: const Color(0xFFA855F7).withValues(alpha: 0.15),
              blurRadius: 16,
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
                        color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.nfc, color: Color(0xFFA855F7), size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '125kHz RFID Reader',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasTag
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFFA855F7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasTag
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : const Color(0xFFA855F7).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      size: 8,
                      color: hasTag ? const Color(0xFF10B981) : const Color(0xFFA855F7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hasTag ? 'TAG DETECTED' : 'READY TO SCAN',
                      style: TextStyle(
                        color: hasTag ? const Color(0xFF6EE7B7) : const Color(0xFFC084FC),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Main Tag Display Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TAG ID (HEX)',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tagHex,
                        style: TextStyle(
                          color: hasTag ? const Color(0xFFC084FC) : const Color(0xFF94A3B8),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'DEC: $tagDec',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (hasTag)
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFF38BDF8), size: 20),
                    tooltip: 'Copy Tag ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tagHex));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied Tag ID: $tagHex'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: const Color(0xFF1E293B),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Footer Metrics & Action Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: Color(0xFF64748B), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    hasTag ? 'Scanned ${secondsAgo}s ago' : 'No recent scans',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Total Scans: $scans',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  if (hasTag && onClearScan != null) ...[
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: onClearScan,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.clear, color: Color(0xFFEF4444), size: 14),
                            SizedBox(width: 2),
                            Text('Clear', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
