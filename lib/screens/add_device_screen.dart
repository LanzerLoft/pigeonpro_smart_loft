import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/relay_status.dart';
import '../services/esp8266_service.dart';

class AddDeviceScreen extends StatefulWidget {
  final VoidCallback? onGoToDashboard;

  const AddDeviceScreen({Key? key, this.onGoToDashboard}) : super(key: key);

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final Esp8266Service _apiService = Esp8266Service();
  final TextEditingController _passCtrl = TextEditingController();

  List<WifiNetwork> _scannedNetworks = [];
  String? _selectedSsid;
  bool _isCheckingConnection = true;
  bool _isAlreadyConnected = false;
  EspStatus? _connectedStatus;

  bool _isScanning = false;
  bool _isSaving = false;
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
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
    setState(() {
      _isScanning = false;
      _scannedNetworks = networks;
      if (networks.isNotEmpty) {
        _selectedSsid = networks.first.ssid;
        _statusMsg = 'Found ${networks.length} Wi-Fi networks!';
      } else {
        _statusMsg = 'No networks found. Connect phone to "pigeonpro-portal" Wi-Fi and tap Scan Again.';
      }
    });
  }

  Future<void> _saveAndProvision() async {
    if (_selectedSsid == null || _selectedSsid!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a Wi-Fi network')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSaving = true;
      _statusMsg = 'Sending credentials to PigeonPro board...';
    });

    final success = await _apiService.saveWifi(
      Esp8266Service.defaultProvisioningUrl,
      _selectedSsid!,
      _passCtrl.text,
    );

    if (!mounted) return;

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_device_url', Esp8266Service.defaultLocalUrl);
      await prefs.setString('paired_wifi_ssid', _selectedSsid!);

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _statusMsg = '✅ Success! PigeonPro is connecting to $_selectedSsid';
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else if (widget.onGoToDashboard != null) {
          widget.onGoToDashboard!();
        } else {
          _checkExistingConnection();
        }
      }
    } else {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _statusMsg = '❌ Connection failed. Check password and try again.';
      });
    }
  }

  void _confirmResetWifi() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Reset Wi-Fi Connection?', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          content: const Text(
            'This will clear the saved Wi-Fi from the board.\n\n'
            'The board will reboot and broadcast its setup Wi-Fi: "pigeonpro-portal".\n\n'
            'You will need to connect your phone to "pigeonpro-portal" Wi-Fi to select your new network.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () async {
                Navigator.pop(context);
                final url = _connectedStatus != null ? 'http://${_connectedStatus!.ip}' : Esp8266Service.defaultLocalUrl;
                await _apiService.resetWifi(url);

                if (!mounted) return;
                setState(() {
                  _isAlreadyConnected = false;
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
          : _isAlreadyConnected
              ? _buildAlreadyConnectedView()
              : _buildProvisioningWizardView(),
    );
  }

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

          const SizedBox(height: 20),

          const Text(
            'PigeonPro is Already Connected!',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your device is online and actively communicating on your network.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),

          const SizedBox(height: 28),

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
                _buildDetailRow('Wi-Fi Network', _connectedStatus?.ssid ?? 'N/A'),
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

          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.dashboard_outlined, color: Colors.white),
              label: const Text('Go to Control Dashboard', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
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

  Widget _buildProvisioningWizardView() {
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
              const Text(
                'Step 2: Select Home Wi-Fi',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _isScanning ? null : _startWifiScan,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Scan Again'),
              ),
            ],
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
          else if (_scannedNetworks.isNotEmpty) ...[
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
                  value: _selectedSsid,
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

            const SizedBox(height: 20),

            const Text(
              'Wi-Fi Password:',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: true,
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
                onPressed: _isSaving ? null : _saveAndProvision,
                child: _isSaving
                    ? const SpinKitThreeBounce(color: Colors.white, size: 24)
                    : const Text(
                        'Connect & Save Credentials',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],

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
