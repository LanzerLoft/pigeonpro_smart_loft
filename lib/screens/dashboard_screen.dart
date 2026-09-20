import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';
import '../widgets/relay_card_widget.dart';
import '../widgets/rfid_card_widget.dart';
import '../widgets/pump_card_widget.dart';
import 'relay_detail_screen.dart';
import 'cctv_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Esp8266Service _apiService = Esp8266Service();
  Timer? _pollingTimer;

  String _currentDeviceUrl = Esp8266Service.defaultLocalUrl;
  EspStatus? _currentStatus;
  bool _isLoading = true;

  final List<String> _relayNames = [
    'Relay 1 - Light / Lamp',
    'Relay 2 - Exhaust Fan',
    'Relay 3 - Water Pump',
    'Relay 4 - Auxiliary / Door Gate',
  ];

  @override
  void initState() {
    super.initState();
    _loadDeviceUrlAndFetch();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetchStatus());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceUrlAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentDeviceUrl = prefs.getString('active_device_url') ?? Esp8266Service.defaultLocalUrl;
    });
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    final status = await _apiService.fetchStatus(_currentDeviceUrl);
    if (!mounted) return;
    setState(() {
      _currentStatus = status;
      _isLoading = false;
      if (status != null && status.ip.isNotEmpty && status.ip != 'N/A') {
        _currentDeviceUrl = 'http://${status.ip}';
      }
    });
  }

  void _showChangeIpDialog() {
    final TextEditingController ipCtrl = TextEditingController(
      text: _currentDeviceUrl.replaceAll('http://', ''),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Set PigeonPro Board Address', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter board IP address (e.g. 192.168.1.17) or mDNS domain (pigeonpro-portal.local):',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '192.168.1.17',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
              onPressed: () async {
                var input = ipCtrl.text.trim();
                if (!input.startsWith('http://') && !input.startsWith('https://')) {
                  input = 'http://$input';
                }
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('active_device_url', input);
                if (!mounted) return;
                setState(() {
                  _currentDeviceUrl = input;
                });
                Navigator.pop(context);
                _fetchStatus();
              },
              child: const Text('Save & Connect', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Device Status Info Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _currentStatus != null ? Icons.wifi : Icons.wifi_off,
                            color: _currentStatus != null ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentStatus != null ? 'ONLINE (${_currentStatus!.ssid})' : 'OFFLINE / SEARCHING',
                            style: TextStyle(
                              color: _currentStatus != null ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _showChangeIpDialog,
                        child: Row(
                          children: [
                            Text(
                              'IP: ${_currentStatus?.ip ?? 'N/A'}',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit, size: 12, color: Color(0xFF38BDF8)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoItem('RSSI', '${_currentStatus?.rssi ?? 0} dBm'),
                      _buildInfoItem('Uptime', '${_currentStatus?.uptime ?? 0}s'),
                      _buildInfoItem('Mode', _currentStatus?.mode ?? 'N/A'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Master Control Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                    label: const Text('Turn All ON', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await _apiService.setAllRelays(_currentDeviceUrl, true);
                      _fetchStatus();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.power_settings_new, color: Colors.white),
                    label: const Text('Turn All OFF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await _apiService.setAllRelays(_currentDeviceUrl, false);
                      _fetchStatus();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 4 Relay Cards
            if (_isLoading && _currentStatus == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                ),
              )
            else
              ...List.generate(4, (index) {
                final ch = index + 1;
                final isOn = (_currentStatus != null && index < _currentStatus!.relays.length)
                    ? _currentStatus!.relays[index]
                    : false;

                final timer = (_currentStatus != null && index < _currentStatus!.timers.length)
                    ? _currentStatus!.timers[index]
                    : null;

                final inching = (_currentStatus != null && index < _currentStatus!.inching.length)
                    ? _currentStatus!.inching[index]
                    : null;

                return RelayCardWidget(
                  channel: ch,
                  label: _relayNames[index],
                  isOn: isOn,
                  timerInfo: timer,
                  inchingInfo: inching,
                  onTapCard: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RelayDetailScreen(
                          channel: ch,
                          defaultLabel: _relayNames[index],
                          isOn: isOn,
                          timerInfo: timer,
                          inchingInfo: inching,
                          deviceUrl: _currentDeviceUrl,
                        ),
                      ),
                    );
                    if (result == true) {
                      _fetchStatus();
                    }
                  },
                  onToggle: (state) async {
                    await _apiService.toggleRelay(_currentDeviceUrl, ch, state);
                    _fetchStatus();
                  },
                  onSetTimer: (sec, target) async {
                    await _apiService.setTimer(_currentDeviceUrl, ch, sec, target);
                    _fetchStatus();
                  },
                  onCancelTimer: () async {
                    await _apiService.setTimer(_currentDeviceUrl, ch, 0, false);
                    _fetchStatus();
                  },
                  onToggleInching: (enable, dur) async {
                    await _apiService.setInching(_currentDeviceUrl, ch, enable, dur);
                    _fetchStatus();
                  },
                );
              }),

            const SizedBox(height: 10),

            // 🌊 12V Submersible Pump Speed Control Card
            PumpCardWidget(
              pumpStatus: _currentStatus?.pump,
              onUpdatePump: (state, speed, dir) async {
                await _apiService.setPumpState(_currentDeviceUrl, state, speed, direction: dir);
                _fetchStatus();
              },
            ),

            // 🏷️ RDM6300 RFID Reader Card
            RfidCardWidget(
              rfidStatus: _currentStatus?.rfid,
              onClearScan: () async {
                await _apiService.clearRfidScan(_currentDeviceUrl);
                _fetchStatus();
              },
            ),

            const SizedBox(height: 16),

            // 📹 CCTV IP Camera Access Card (Overflow Protected)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.videocam, color: Color(0xFF38BDF8), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CCTV IP Cameras',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ONVIF & RTSP Live Video Stream',
                                style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                    label: const Text('Open CCTV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CctvScreen(showAppBar: true)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}
