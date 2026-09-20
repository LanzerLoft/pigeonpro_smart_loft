import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';
import 'dashboard_screen.dart';
import 'pump_screen.dart';
import 'cctv_screen.dart';
import 'add_device_screen.dart';
import '../widgets/rfid_card_widget.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final Esp8266Service _apiService = Esp8266Service();
  Timer? _pollingTimer;

  String _currentDeviceUrl = Esp8266Service.defaultLocalUrl;
  EspStatus? _currentStatus;

  @override
  void initState() {
    super.initState();
    _loadDeviceUrlAndFetch();
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _fetchStatus());
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
      _currentDeviceUrl = prefs.getString('active_device_url') ??
          Esp8266Service.defaultLocalUrl;
    });
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    final status = await _apiService.fetchStatus(_currentDeviceUrl);
    if (!mounted) return;
    setState(() {
      _currentStatus = status;
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
          title: const Text('Set PigeonPro Board Address',
              style: TextStyle(color: Colors.white, fontSize: 16)),
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
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8)),
              onPressed: () async {
                var input = ipCtrl.text.trim();
                if (!input.startsWith('http://') &&
                    !input.startsWith('https://')) {
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
              child: const Text('Save & Connect',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  String get _appBarTitle {
    switch (_currentIndex) {
      case 0:
        return 'Relays & Power';
      case 1:
        return 'Automatic Drinker';
      case 2:
        return 'RFID 125kHz Scanner';
      case 3:
        return 'CCTV Live Cameras';
      case 4:
        return 'Device Setup';
      default:
        return 'PigeonPro Control';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      PumpScreen(
        status: _currentStatus,
        deviceUrl: _currentDeviceUrl,
        onRefresh: _fetchStatus,
      ),
      _buildRfidTabContent(),
      const CctvScreen(showAppBar: false),
      AddDeviceScreen(
        onGoToDashboard: () {
          setState(() {
            _currentIndex = 0;
          });
          _fetchStatus();
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      // Single Clean Futuristic AppBar
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF38BDF8), size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _appBarTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'PigeonPro IoT Suite',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Compact Connection Status Chip
          GestureDetector(
            onTap: _showChangeIpDialog,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _currentStatus != null
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _currentStatus != null
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : const Color(0xFFEF4444).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 8,
                    color: _currentStatus != null
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _currentStatus != null ? 'ONLINE' : 'CONNECTING',
                    style: TextStyle(
                      color: _currentStatus != null
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFFFCA5A5),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.link, color: Color(0xFF38BDF8), size: 20),
            tooltip: 'Set Board IP',
            onPressed: _showChangeIpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _fetchStatus,
          ),
        ],
      ),

      // Screen Body Content
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      // Floating Modern Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: const Color(0xFF1E293B),
          selectedItemColor: const Color(0xFF38BDF8),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.flash_on),
              activeIcon: Icon(Icons.flash_on, color: Color(0xFF38BDF8)),
              label: 'Relays',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.water_drop_outlined),
              activeIcon: Icon(Icons.water_drop, color: Color(0xFF38BDF8)),
              label: 'Water Pump',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.nfc_outlined),
              activeIcon: Icon(Icons.nfc, color: Color(0xFFA855F7)),
              label: 'RFID',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.videocam_outlined),
              activeIcon: Icon(Icons.videocam, color: Color(0xFF38BDF8)),
              label: 'CCTV Live',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_input_antenna),
              activeIcon:
                  Icon(Icons.settings_input_antenna, color: Color(0xFF38BDF8)),
              label: 'Provision',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRfidTabContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.nfc, color: Color(0xFFA855F7), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RDM6300 RFID Card Scanner',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '125kHz EM4100 Transponder Reader (UART 9600 Baud @ GPIO 13 / D7)',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          RfidCardWidget(
            rfidStatus: _currentStatus?.rfid,
            onClearScan: () async {
              await _apiService.clearRfidScan(_currentDeviceUrl);
              _fetchStatus();
            },
          ),
        ],
      ),
    );
  }
}
