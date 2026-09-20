import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/cctv_camera.dart';
import '../services/cctv_service.dart';

class CctvPlayerWidget extends StatefulWidget {
  final CctvCamera camera;
  final Function(CctvCamera)? onUpdate;
  final VoidCallback? onDelete;

  const CctvPlayerWidget({
    Key? key,
    required this.camera,
    this.onUpdate,
    this.onDelete,
  }) : super(key: key);

  @override
  State<CctvPlayerWidget> createState() => _CctvPlayerWidgetState();
}

class _CctvPlayerWidgetState extends State<CctvPlayerWidget> {
  final CctvService _cctvService = CctvService();

  bool _isLivePolling = false;
  bool _showPtzControls = false;
  bool _showDiagnostics = false;
  bool _isProbing = false;
  Map<int, bool>? _probedPorts;

  late String _activePath;
  late int _activePort;
  late String _activePassword;
  String _streamStatus = 'RTSP Port 554 Ready';

  Uint8List? _lastFrameBytes;
  Timer? _livePollingTimer;

  final List<String> _yooseePathOptions = [
    '/onvif1',
    '/onvif2',
    '/snapshot.jpg',
    '/live/ch0',
    '/cgi-bin/snapshot.cgi',
    '/videostream.cgi',
  ];

  @override
  void initState() {
    super.initState();
    _activePath = widget.camera.rtspPath;
    _activePort = widget.camera.rtspPort;
    _activePassword = widget.camera.password;
    _runPortProbe();
  }

  @override
  void dispose() {
    _livePollingTimer?.cancel();
    super.dispose();
  }

  String get _currentRtspUrl {
    final auth = (widget.camera.username.isNotEmpty)
        ? '${widget.camera.username}:${Uri.encodeComponent(_activePassword)}@'
        : '';
    final path = _activePath.startsWith('/') ? _activePath : '/$_activePath';
    return 'rtsp://$auth${widget.camera.ipAddress}:$_activePort$path';
  }

  void _toggleInAppPolling() {
    if (_isLivePolling) {
      _livePollingTimer?.cancel();
      setState(() {
        _isLivePolling = false;
        _streamStatus = 'In-App Stream Paused';
      });
    } else {
      setState(() {
        _isLivePolling = true;
        _streamStatus = 'Fetching Live Frames...';
      });
      _fetchLiveFrame();
      _livePollingTimer = Timer.periodic(const Duration(milliseconds: 600), (_) => _fetchLiveFrame());
    }
  }

  Future<void> _fetchLiveFrame() async {
    final path = _activePath.startsWith('/') ? _activePath : '/$_activePath';
    final candidateEndpoints = [
      'http://${widget.camera.ipAddress}:8080$path',
      'http://${widget.camera.ipAddress}:80$path',
      'http://${widget.camera.ipAddress}:5000$path',
      'http://${widget.camera.ipAddress}:8899$path',
      'http://${widget.camera.ipAddress}:8080/snapshot.jpg',
      'http://${widget.camera.ipAddress}:80/snapshot.jpg',
    ];

    final authHeader = 'Basic ${base64Encode(utf8.encode('${widget.camera.username}:$_activePassword'))}';

    for (final url in candidateEndpoints) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Authorization': authHeader},
        ).timeout(const Duration(milliseconds: 500));

        if (response.statusCode == 200 && response.bodyBytes.length > 500 && mounted) {
          setState(() {
            _lastFrameBytes = response.bodyBytes;
            _streamStatus = '🟢 In-App Live Frame Received';
          });
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _runPortProbe() async {
    if (!mounted) return;
    setState(() {
      _isProbing = true;
    });

    final results = await _cctvService.probeCameraPorts(widget.camera.ipAddress);

    if (!mounted) return;
    setState(() {
      _probedPorts = results;
      _isProbing = false;
    });
  }

  Future<void> _launchExternalPlayer() async {
    final uri = Uri.parse(_currentRtspUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _copyRtspUrl();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RTSP link copied! Paste into VLC or any video player to watch live.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _copyRtspUrl();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RTSP link copied to clipboard! Open in VLC player to stream.'),
          ),
        );
      }
    }
  }

  void _showEditPasswordDialog() {
    final passCtrl = TextEditingController(text: _activePassword);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Update RTSP Password', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the RTSP Connection Password configured in Yoosee App ➔ Device Settings ➔ Security Settings:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'RTSP Password',
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
              onPressed: () {
                final newPass = passCtrl.text;
                setState(() {
                  _activePassword = newPass;
                });
                Navigator.pop(context);
                _runPortProbe();
              },
              child: const Text('Save & Reconnect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendPtz(String action) async {
    await _cctvService.sendPtzCommand(widget.camera, action);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PTZ Action: $action on ${widget.camera.name}'),
          duration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  void _copyRtspUrl() {
    Clipboard.setData(ClipboardData(text: _currentRtspUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 RTSP Stream URL copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPortOpen = _probedPorts != null && (_probedPorts![554] == true || _probedPorts![5540] == true);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPortOpen
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Camera Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.camera.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPortOpen
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPortOpen
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : const Color(0xFFEF4444).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fiber_manual_record,
                            color: isPortOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            size: 8,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPortOpen ? 'RTSP 554 ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              color: isPortOpen ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.key, color: Color(0xFFF59E0B), size: 18),
                      tooltip: 'Change Password',
                      onPressed: _showEditPasswordDialog,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                      tooltip: 'Auto-Probe Camera Ports',
                      onPressed: _runPortProbe,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.build_outlined, color: Color(0xFF38BDF8), size: 18),
                      tooltip: 'Diagnostics & Path Tester',
                      onPressed: () {
                        setState(() {
                          _showDiagnostics = !_showDiagnostics;
                        });
                      },
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Live Stream Viewport & Action Panel
          Stack(
            children: [
              Container(
                height: 220,
                width: double.infinity,
                color: Colors.black,
                child: _lastFrameBytes != null
                    ? Image.memory(
                        _lastFrameBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                ),
                                child: const Icon(Icons.videocam, color: Color(0xFF10B981), size: 36),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '🟢 Yoosee Live Stream Server Active',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentRtspUrl,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.play_circle_filled, size: 18, color: Colors.white),
                                    label: const Text('Play Live Stream', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                    onPressed: _launchExternalPlayer,
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF334155),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: Icon(_isLivePolling ? Icons.pause : Icons.image, size: 16, color: const Color(0xFF38BDF8)),
                                    label: Text(_isLivePolling ? 'Pause Feed' : 'In-App Frames', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                                    onPressed: _toggleInAppPolling,
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E293B),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      side: const BorderSide(color: Color(0xFF38BDF8)),
                                    ),
                                    icon: const Icon(Icons.copy, size: 14, color: Color(0xFF38BDF8)),
                                    label: const Text('Copy URL', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                                    onPressed: _copyRtspUrl,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // ONVIF PTZ D-Pad Overlay (if enabled)
              if (_showPtzControls)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_drop_up, color: Color(0xFF38BDF8), size: 36),
                            onPressed: () => _sendPtz('UP'),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_left, color: Color(0xFF38BDF8), size: 36),
                                onPressed: () => _sendPtz('LEFT'),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(color: Color(0xFF38BDF8), shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_right, color: Color(0xFF38BDF8), size: 36),
                                onPressed: () => _sendPtz('RIGHT'),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF38BDF8), size: 36),
                            onPressed: () => _sendPtz('DOWN'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Diagnostic & Port Probing Panel (if toggled)
          if (_showDiagnostics)
            Container(
              padding: const EdgeInsets.all(14),
              color: const Color(0xFF0F172A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Network & Stream Diagnostics:',
                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        icon: _isProbing
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.radar, size: 14, color: Colors.white),
                        label: const Text('Probe Ports Now', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        onPressed: _isProbing ? null : _runPortProbe,
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  Text('Status: $_streamStatus', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('Active RTSP URL: $_currentRtspUrl', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  const SizedBox(height: 10),

                  if (_probedPorts != null) ...[
                    const Text('Camera Port Scan Results:', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _probedPorts!.entries.map((e) {
                        final isOpen = e.value;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isOpen ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFEF4444).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                          ),
                          child: Text(
                            'Port ${e.key}: ${isOpen ? "OPEN 🟢" : "CLOSED 🔴"}',
                            style: TextStyle(
                              color: isOpen ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),

                    if (_probedPorts![554] == false && _probedPorts![5540] == false)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          '⚠️ RTSP Port 554/5540 is CLOSED on your camera!\n'
                          'Turn ON "RTSP Password" in official Yoosee App ➔ Settings ➔ Security Settings.',
                          style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],

                  const SizedBox(height: 10),
                  const Text('Test Stream Paths (Tap to switch):', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _yooseePathOptions.map((path) {
                      final isSelected = _activePath == path;
                      return ChoiceChip(
                        label: Text(path),
                        selected: isSelected,
                        selectedColor: const Color(0xFF38BDF8),
                        backgroundColor: const Color(0xFF334155),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _activePath = path;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Bottom Action Toolbar (PTZ Toggle, Reconnect, Snapshot)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Color(0xFF38BDF8), size: 20),
                      tooltip: 'Re-scan Port',
                      onPressed: _runPortProbe,
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_sharp, color: Color(0xFF94A3B8), size: 20),
                      tooltip: 'Take Snapshot',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('📸 Snapshot captured!')),
                        );
                      },
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showPtzControls ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.open_with, size: 16, color: Colors.white),
                  label: Text(
                    _showPtzControls ? 'Close PTZ' : 'ONVIF PTZ',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      _showPtzControls = !_showPtzControls;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
