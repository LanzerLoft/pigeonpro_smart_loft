import 'package:flutter/material.dart';
import '../services/log_service.dart';

class LogSessionWidget extends StatefulWidget {
  final VoidCallback? onLogCleared;

  const LogSessionWidget({
    Key? key,
    this.onLogCleared,
  }) : super(key: key);

  @override
  State<LogSessionWidget> createState() => _LogSessionWidgetState();
}

class _LogSessionWidgetState extends State<LogSessionWidget> {
  final LogService _logService = LogService();
  String _selectedFilter = 'all'; // 'all', 'clean', 'pump', 'schedule', 'rfid'
  int _currentPage = 1;
  int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    await _logService.loadLogs();
    if (mounted) {
      setState(() {});
    }
  }

  IconData _getLogIcon(String type) {
    switch (type) {
      case 'clean':
        return Icons.autorenew_rounded;
      case 'pump1':
      case 'pump2':
      case 'pump':
        return Icons.water_drop_rounded;
      case 'relay':
        return Icons.flash_on_rounded;
      case 'schedule':
        return Icons.schedule_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'clean':
        return const Color(0xFF38BDF8); // Cyan
      case 'pump1':
        return const Color(0xFF10B981); // Emerald
      case 'pump2':
        return const Color(0xFF34D399); // Mint
      case 'pump':
        return const Color(0xFF10B981); // Emerald
      case 'relay':
        return const Color(0xFFF59E0B); // Amber
      case 'schedule':
        return const Color(0xFF818CF8); // Indigo
      default:
        return const Color(0xFF94A3B8); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = _logService.logs;
    final filteredLogs = allLogs.where((l) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'clean') return l.type == 'clean';
      if (_selectedFilter == 'schedule') return l.type == 'schedule';
      if (_selectedFilter == 'pump1') {
        if (l.type == 'pump1') return true;
        if (l.type == 'pump') {
          final text = '${l.title} ${l.details}'.toLowerCase();
          return text.contains('pump #1') || text.contains('pump 1') || text.contains('main drinker') || (!text.contains('pump 2') && !text.contains('pump #2'));
        }
        return false;
      }
      if (_selectedFilter == 'pump2') {
        if (l.type == 'pump2') return true;
        if (l.type == 'pump') {
          final text = '${l.title} ${l.details}'.toLowerCase();
          return text.contains('pump #2') || text.contains('pump 2') || text.contains('submersible');
        }
        return false;
      }
      return l.type == _selectedFilter;
    }).toList();

    final int totalItems = filteredLogs.length;
    final int totalPages = totalItems == 0 ? 1 : (totalItems / _itemsPerPage).ceil();

    if (_currentPage > totalPages) {
      _currentPage = totalPages;
    }
    if (_currentPage < 1) {
      _currentPage = 1;
    }

    final int startIndex = totalItems == 0 ? 0 : (_currentPage - 1) * _itemsPerPage;
    final int endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
    final pageLogs = (totalItems == 0 || startIndex >= totalItems)
        ? <LogEntry>[]
        : filteredLogs.sublist(startIndex, endIndex);

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
          // Header Row (Fixed layout to prevent overflow & text overlap)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session Operation Logs',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalItems event(s) logged in session',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh Logs',
                onPressed: _loadLogs,
              ),
              if (allLogs.isNotEmpty) ...[
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Clear Log Session',
                  onPressed: () async {
                    await _logService.clearLogs();
                    if (mounted) {
                      setState(() {
                        _currentPage = 1;
                      });
                      widget.onLogCleared?.call();
                    }
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Events (${allLogs.length})', 'all'),
                const SizedBox(width: 6),
                _buildFilterChip('✨ Clean & Refill', 'clean'),
                const SizedBox(width: 6),
                _buildFilterChip('🌊 Pump #1', 'pump1'),
                const SizedBox(width: 6),
                _buildFilterChip('🌊 Pump #2', 'pump2'),
                const SizedBox(width: 6),
                _buildFilterChip('📅 Schedules', 'schedule'),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Logs List View
          if (filteredLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                children: [
                  Icon(Icons.history_toggle_off_rounded, color: Color(0xFF64748B), size: 36),
                  SizedBox(height: 8),
                  Text(
                    'No Session Logs Recorded Yet',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Operations, drinker refills, and schedule events will be recorded here live.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageLogs.length,
              itemBuilder: (context, index) {
                final log = pageLogs[index];
                final color = _getLogColor(log.type);
                final icon = _getLogIcon(log.type);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    log.title,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  log.timestamp,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (log.details.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                log.details,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Pagination Controls
          if (filteredLogs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Page $_currentPage of $totalPages ($totalItems items)',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _itemsPerPage,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            isDense: true,
                            items: const [5, 10, 20, 50].map((count) {
                              return DropdownMenuItem<int>(
                                value: count,
                                child: Text('$count / pg'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _itemsPerPage = val;
                                  _currentPage = 1;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 20,
                        color: _currentPage > 1 ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Previous Page',
                        onPressed: _currentPage > 1
                            ? () {
                                setState(() {
                                  _currentPage--;
                                });
                              }
                            : null,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 20,
                        color: _currentPage < totalPages ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Next Page',
                        onPressed: _currentPage < totalPages
                            ? () {
                                setState(() {
                                  _currentPage++;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey) {
    final isSel = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSel,
      selectedColor: const Color(0xFF38BDF8),
      backgroundColor: const Color(0xFF0F172A),
      labelStyle: TextStyle(
        color: isSel ? const Color(0xFF0F172A) : Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      onSelected: (_) {
        setState(() {
          _selectedFilter = filterKey;
          _currentPage = 1;
        });
      },
    );
  }
}
