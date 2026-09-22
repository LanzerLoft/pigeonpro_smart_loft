import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';

class AddDeviceScreen extends StatefulWidget {
  final VoidCallback? onGoToDashboard;

  const AddDeviceScreen({super.key, this.onGoToDashboard});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final Esp8266Service _apiService = Esp8266Service();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _manualSsidCtrl = TextEditingController();
  final TextEditingController _manualIpCtrl = TextEditingController();

  List<WifiNetwork> _scannedNetworks = [];
  String? _selectedSsid;
  bool _isManualSsid = false;
  bool _obscurePassword = true;

  bool _isCheckingConnection = true;
  bool _isAlreadyConnected = false;
  EspStatus? _connectedStatus;

  bool _isScanning = false;
  bool _isProvisioningLoading = false;
  bool _provisioningTimedOut = false;
  bool _justProvisioned = false;
  int _provisioningSeconds = 0;
  String _targetProvisioningSsid = '';
  String _statusMsg = '';
  String? _assignedBoardIp;
  RawDatagramSocket? _udpSocket;

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
  }

  @override
  void dispose() {
    _udpSocket?.close();
    _passCtrl.dispose();
    _manualSsidCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  // Check if device is already paired and online
  Future<void> _checkExistingConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('active_device_url') ?? Esp8266Service.defaultLocalUrl;

    final status = await _apiService.fetchStatus(savedUrl);

    if (!mounted) return;

    if (status != null && status.mode == 'STA_ONLINE') {
      setState(() {
        _isCheckingConnection = false;
        _isAlreadyConnected = true;
        _connectedStatus = status;
      });
    } else {
      final apStatus = await _apiService.fetchStatus(Esp8266Service.defaultProvisioningUrl);
      if (!mounted) return;

      if (apStatus != null && apStatus.mode == 'STA_ONLINE') {
        setState(() {
          _isCheckingConnection = false;
          _isAlreadyConnected = true;
          _connectedStatus = apStatus;
        });
      } else {
        setState(() {
          _isCheckingConnection = false;
          _isAlreadyConnected = false;
        });
        _startWifiScan();
      }
    }
  }

  Future<void> _startWifiScan() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _statusMsg = 'Scanning nearby 2.4GHz Wi-Fi networks...';
    });

    final networks = await _apiService.scanWifi(Esp8266Service.defaultProvisioningUrl);

    if (!mounted) return;

    // Deduplicate SSIDs to prevent DropdownButton assertion crashes
    // Keep the AP with highest RSSI (strongest signal) and ignore empty SSIDs
    final Map<String, WifiNetwork> uniqueMap = {};
    for (final net in networks) {
      final trimmed = net.ssid.trim();
      if (trimmed.isEmpty) continue;
      if (!uniqueMap.containsKey(trimmed) || net.rssi > uniqueMap[trimmed]!.rssi) {
        uniqueMap[trimmed] = net;
      }
    }

    final uniqueNetworks = uniqueMap.values.toList();
    // Sort by signal strength (strongest first)
    uniqueNetworks.sort((a, b) => b.rssi.compareTo(a.rssi));

    setState(() {
      _isScanning = false;
      _scannedNetworks = uniqueNetworks;
      if (uniqueNetworks.isNotEmpty) {
        if (_selectedSsid == null || !uniqueNetworks.any((n) => n.ssid == _selectedSsid)) {
          _selectedSsid = uniqueNetworks.first.ssid;
        }
        _statusMsg = 'Found ${uniqueNetworks.length} Wi-Fi networks!';
      } else {
        _selectedSsid = null;
        _statusMsg = 'No networks found. Connect phone to "pigeonpro-portal" Wi-Fi and tap Scan Again.';
      }
    });
  }

  Future<void> _saveAndProvision() async {
    final targetSsid = _isManualSsid ? _manualSsidCtrl.text.trim() : _selectedSsid?.trim();

    if (targetSsid == null || targetSsid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select or enter a Wi-Fi network name')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _targetProvisioningSsid = targetSsid;
      _isProvisioningLoading = true;
      _provisioningTimedOut = false;
      _provisioningSeconds = 0;
      _statusMsg = 'Sending credentials to PigeonPro board...';
    });

    final result = await _apiService.saveWifi(
      Esp8266Service.defaultProvisioningUrl,
      targetSsid,
      _passCtrl.text,
    );

    if (!mounted) return;

    if (!result.success) {
      final errMsg = result.error ?? 'Failed to send credentials.';
      setState(() {
        _isProvisioningLoading = false;
        _statusMsg = '❌ $errMsg';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ $errMsg'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Success! Save assigned IP if returned by board
    if (result.ip != null && result.ip!.isNotEmpty) {
      _assignedBoardIp = result.ip;
      final targetUrl = 'http://${result.ip}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_url', targetUrl);
      await prefs.setString('paired_wifi_ssid', targetSsid);
    }

    // Begin active verification loop with UDP listener
    _pollForBoardOnline(targetSsid, directIp: result.ip);
  }

  Future<void> _startUdpDiscovery(Function(String ip) onIpDiscovered) async {
    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4210);
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket?.receive();
          if (dg != null) {
            final msg = utf8.decode(dg.data);
            try {
              final data = jsonDecode(msg);
              if (data['device'] == 'pigeonpro' && data['ip'] != null) {
                onIpDiscovered(data['ip'] as String);
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _pollForBoardOnline(String targetSsid, {String? directIp}) async {
    final startTime = DateTime.now();
    EspStatus? onlineStatus;
    String? testIp = directIp ?? _assignedBoardIp;

    _startUdpDiscovery((discoveredIp) {
      if ((testIp == null || testIp!.isEmpty) && mounted) {
        setState(() {
          testIp = discoveredIp;
          _assignedBoardIp = discoveredIp;
          _statusMsg = 'PigeonPro detected at $discoveredIp! Verifying connection...';
        });
      }
    });

    while (DateTime.now().difference(startTime).inSeconds < 35 && mounted) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      setState(() {
        _provisioningSeconds = elapsed;
        if (testIp != null && testIp!.isNotEmpty) {
          _statusMsg = 'PigeonPro found at $testIp! Verifying dashboard connection (${elapsed}s)...';
        } else if (elapsed < 8) {
          _statusMsg = 'Credentials saved! Board is rebooting and joining "$targetSsid"...';
        } else if (elapsed < 16) {
          _statusMsg = 'Connecting board to "$targetSsid"... Please ensure phone is connected to "$targetSsid"';
        } else {
          _statusMsg = 'Searching for PigeonPro on "$targetSsid" (${elapsed}s)...';
        }
      });

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // 1. Try direct IP (discovered via UDP or returned during save)
      if (testIp != null && testIp!.isNotEmpty) {
        onlineStatus = await _apiService.fetchStatus('http://$testIp');
        if (onlineStatus != null && onlineStatus.mode == 'STA_ONLINE') {
          break;
        }
      }

      // 2. Try local mDNS URL
      onlineStatus = await _apiService.fetchStatus(Esp8266Service.defaultLocalUrl);
      if (onlineStatus != null && onlineStatus.mode == 'STA_ONLINE') {
        break;
      }

      // 3. Try default provisioning URL in case still on AP
      onlineStatus = await _apiService.fetchStatus(Esp8266Service.defaultProvisioningUrl);
      if (onlineStatus != null && onlineStatus.mode == 'STA_ONLINE') {
        break;
      }
    }

    _udpSocket?.close();

    if (!mounted) return;

    if (onlineStatus != null && onlineStatus.mode == 'STA_ONLINE') {
      final finalIp = (onlineStatus.ip.isNotEmpty && onlineStatus.ip != 'N/A' && onlineStatus.ip != '0.0.0.0')
          ? onlineStatus.ip
          : (testIp != null && testIp!.isNotEmpty ? testIp! : '');
      final targetUrl = finalIp.isNotEmpty ? 'http://$finalIp' : Esp8266Service.defaultLocalUrl;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_url', targetUrl);
      await prefs.setString('paired_wifi_ssid', targetSsid);

      setState(() {
        _isProvisioningLoading = false;
        _isAlreadyConnected = true;
        _justProvisioned = true;
        _connectedStatus = onlineStatus;
      });
    } else if (testIp != null && testIp!.isNotEmpty) {
      final targetUrl = 'http://$testIp';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_url', targetUrl);
      await prefs.setString('paired_wifi_ssid', targetSsid);

      setState(() {
        _isProvisioningLoading = false;
        _isAlreadyConnected = true;
        _justProvisioned = true;
        _connectedStatus = EspStatus(
          ip: testIp!,
          ssid: targetSsid,
          rssi: -55,
          uptime: 10,
          mode: 'STA_ONLINE',
          relays: [false, false, false, false],
          timers: [],
          inching: [],
        );
      });
    } else {
      setState(() {
        _isProvisioningLoading = false;
        _provisioningTimedOut = true;
      });
    }
  }

  void _confirmResetWifi() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Reset Wi-Fi Connection?',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'This will clear the saved Wi-Fi from the board.\n\n'
            'The board will reboot and broadcast its setup Wi-Fi: "pigeonpro-portal".\n\n'
            'You will need to connect your phone to "pigeonpro-portal" Wi-Fi to select your new network.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final url = _connectedStatus != null ? 'http://${_connectedStatus!.ip}' : Esp8266Service.defaultLocalUrl;
                await _apiService.resetWifi(url);

                if (!mounted || !context.mounted) return;
                setState(() {
                  _isAlreadyConnected = false;
                  _justProvisioned = false;
                  _provisioningTimedOut = false;
                  _statusMsg = 'Connect phone to Wi-Fi "pigeonpro-portal" to setup new network.';
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Board reset! Connect phone to "pigeonpro-portal" Wi-Fi to configure new network.'),
                    duration: Duration(seconds: 5),
                  ),
                );

                _startWifiScan();
              },
              child: const Text('Reset Wi-Fi Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('PigeonPro Device Status', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isCheckingConnection
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpinKitThreeBounce(color: Color(0xFF38BDF8), size: 30),
                  SizedBox(height: 14),
                  Text('Checking PigeonPro connection...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                ],
              ),
            )
          : _isProvisioningLoading
              ? _buildProvisioningLoadingView()
              : _provisioningTimedOut
                  ? _buildProvisioningTimeoutView()
                  : _isAlreadyConnected
                      ? _buildAlreadyConnectedView()
                      : _buildProvisioningWizardView(),
    );
  }

  // 1. Loading screen displayed right after clicking Connect & Save Credentials
  Widget _buildProvisioningLoadingView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), width: 2),
              ),
              child: const SpinKitRing(
                color: Color(0xFF38BDF8),
                size: 54,
                lineWidth: 4,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Connecting to "$_targetProvisioningSsid"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 32),

            // Step Progress Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  _buildProgressStep(
                    icon: Icons.check_circle,
                    color: const Color(0xFF10B981),
                    title: '1. Wi-Fi Credentials Saved',
                    subtitle: 'Sent to PigeonPro board successfully',
                    isDone: true,
                  ),
                  const Divider(color: Color(0xFF334155), height: 20),
                  _buildProgressStep(
                    icon: Icons.sync,
                    color: const Color(0xFF38BDF8),
                    title: '2. Board Reboot & Association',
                    subtitle: 'Joining "$_targetProvisioningSsid"... (${_provisioningSeconds}s elapsed)',
                    isDone: _provisioningSeconds > 6,
                    isActive: _provisioningSeconds <= 6,
                  ),
                  const Divider(color: Color(0xFF334155), height: 20),
                  _buildProgressStep(
                    icon: Icons.wifi_find,
                    color: const Color(0xFFA855F7),
                    title: '3. Verifying Online Status',
                    subtitle: 'Checking connection on local network',
                    isDone: false,
                    isActive: _provisioningSeconds > 6,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Make sure your phone reconnects to "$_targetProvisioningSsid" so it can detect the board on your home network.',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStep({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isDone,
    bool isActive = false,
  }) {
    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle : (isActive ? Icons.autorenew : icon),
          color: isDone ? const Color(0xFF10B981) : (isActive ? const Color(0xFF38BDF8) : const Color(0xFF64748B)),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDone ? Colors.white : (isActive ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
        ),
        if (isActive)
          const SpinKitThreeBounce(color: Color(0xFF38BDF8), size: 14),
      ],
    );
  }

  // 2. Timeout view if the phone hasn't detected board yet
  Widget _buildProvisioningTimeoutView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 2),
            ),
            child: const Icon(Icons.wifi_tethering_error, color: Color(0xFFF59E0B), size: 54),
          ),
          const SizedBox(height: 20),
          const Text(
            'Still Searching for PigeonPro',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'The board received the credentials for "$_targetProvisioningSsid".\n'
            'Ensure your phone is connected to "$_targetProvisioningSsid" Wi-Fi and tap Check Connection Again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Check Connection Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() {
                  _isProvisioningLoading = true;
                  _provisioningTimedOut = false;
                  _provisioningSeconds = 0;
                });
                _pollForBoardOnline(_targetProvisioningSsid);
              },
            ),
          ),
          const SizedBox(height: 20),

          // Direct IP Connection Card (Fallback)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lan, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Know the Board\'s IP Address?',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'If your router assigned an IP (or shown on serial monitor), enter it below to connect directly:',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIpCtrl,
                        keyboardType: TextInputType.datetime,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. 192.168.1.150',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: _connectDirectManualIp,
                      child: const Text('Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {
              setState(() {
                _provisioningTimedOut = false;
                _isProvisioningLoading = false;
              });
            },
            child: const Text('Back to Wi-Fi Setup', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDirectManualIp() async {
    final ip = _manualIpCtrl.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _isProvisioningLoading = true;
      _provisioningTimedOut = false;
      _statusMsg = 'Testing direct connection to http://$ip...';
    });

    final status = await _apiService.fetchStatus('http://$ip');
    if (!mounted) return;

    if (status != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_url', 'http://$ip');
      await prefs.setString('paired_wifi_ssid', _targetProvisioningSsid.isNotEmpty ? _targetProvisioningSsid : status.ssid);

      setState(() {
        _isProvisioningLoading = false;
        _isAlreadyConnected = true;
        _justProvisioned = true;
        _connectedStatus = status;
      });
    } else {
      setState(() {
        _isProvisioningLoading = false;
        _provisioningTimedOut = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Could not reach board at http://$ip. Ensure phone is on the same Wi-Fi.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  // 3. Celebratory view displaying STATUS: CONNECTED & ONLINE
  Widget _buildAlreadyConnectedView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 2),
            ),
            child: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 64),
          ),

          const SizedBox(height: 18),

          Text(
            _justProvisioned ? '🎉 Connected Successfully!' : 'PigeonPro is Connected!',
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _justProvisioned
                ? 'Your PigeonPro board has joined your Wi-Fi network and is fully operational.'
                : 'Your device is online and actively communicating on your network.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                _buildDetailRow('Status', '🟢 Connected & Online', isHighlight: true),
                const Divider(color: Color(0xFF334155), height: 20),
                _buildDetailRow('Wi-Fi Network', _connectedStatus?.ssid ?? (_selectedSsid ?? 'N/A')),
                const Divider(color: Color(0xFF334155), height: 20),
                _buildDetailRow('IP Address', _connectedStatus?.ip ?? 'N/A'),
                const Divider(color: Color(0xFF334155), height: 20),
                _buildDetailRow('Signal Strength', '${_connectedStatus?.rssi ?? 0} dBm'),
                const Divider(color: Color(0xFF334155), height: 20),
                _buildDetailRow('mDNS Domain', 'http://pigeonpro-portal.local'),
                const Divider(color: Color(0xFF334155), height: 20),
                _buildDetailRow('Uptime', '${_connectedStatus?.uptime ?? 0} seconds'),
              ],
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.dashboard_outlined, color: Colors.white),
              label: const Text(
                'Go to Control Dashboard',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context, true);
                } else if (widget.onGoToDashboard != null) {
                  widget.onGoToDashboard!();
                } else {
                  _checkExistingConnection();
                }
              },
            ),
          ),

          const SizedBox(height: 12),

          TextButton.icon(
            icon: const Icon(Icons.settings_backup_restore, color: Color(0xFFEF4444), size: 18),
            label: const Text('Reconfigure / Reset Wi-Fi', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
            onPressed: _confirmResetWifi,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isHighlight ? const Color(0xFF6EE7B7) : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  // 4. Initial Provisioning Form View
  Widget _buildProvisioningWizardView() {
    // Determine the safe dropdown value: must match exactly one net in _scannedNetworks
    final bool hasValidSelected = _selectedSsid != null && _scannedNetworks.any((n) => n.ssid == _selectedSsid);
    final String? effectiveDropdownValue = hasValidSelected
        ? _selectedSsid
        : (_scannedNetworks.isNotEmpty ? _scannedNetworks.first.ssid : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi, color: Color(0xFF38BDF8), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 1: Connect Phone to Wi-Fi',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Connect your phone to Wi-Fi: "pigeonpro-portal"',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Step 2: Select Home Wi-Fi',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Scan Again',
                onPressed: _isScanning ? null : _startWifiScan,
                icon: const Icon(Icons.refresh, color: Color(0xFF38BDF8), size: 20),
              ),
            ],
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              setState(() {
                _isManualSsid = !_isManualSsid;
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isManualSsid ? Icons.list_rounded : Icons.edit_note_rounded,
                    size: 15,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isManualSsid ? 'Choose from scanned Wi-Fi list' : 'Can\'t find network? Enter SSID manually',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    SpinKitThreeBounce(color: Color(0xFF38BDF8), size: 30),
                    SizedBox(height: 10),
                    Text('Scanning Wi-Fi networks...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_isManualSsid) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _manualSsidCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Wi-Fi Network Name (SSID)',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                hintText: 'e.g. MyHome_2.4G',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                prefixIcon: const Icon(Icons.wifi_outlined, color: Color(0xFF38BDF8)),
              ),
            ),
          ] else if (_scannedNetworks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: effectiveDropdownValue,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  items: _scannedNetworks.map((net) {
                    return DropdownMenuItem<String>(
                      value: net.ssid,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              net.ssid,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${net.rssi} dBm', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedSsid = val;
                    });
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Wi-Fi Password:',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter Wi-Fi Password',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF94A3B8)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isScanning ? null : _saveAndProvision,
              child: const Text(
                'Connect & Save Credentials',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_statusMsg.isNotEmpty)
            Center(
              child: Text(
                _statusMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
