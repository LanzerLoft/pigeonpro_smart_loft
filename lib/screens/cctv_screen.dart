import 'package:flutter/material.dart';
import '../models/cctv_camera.dart';
import '../services/cctv_service.dart';
import '../widgets/cctv_player_widget.dart';

class CctvScreen extends StatefulWidget {
  final bool showAppBar;

  const CctvScreen({
    Key? key,
    this.showAppBar = false,
  }) : super(key: key);

  @override
  State<CctvScreen> createState() => _CctvScreenState();
}

class _CctvScreenState extends State<CctvScreen> {
  final CctvService _cctvService = CctvService();
  List<CctvCamera> _cameras = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    final list = await _cctvService.loadCameras();
    if (!mounted) return;
    setState(() {
      _cameras = list;
      _isLoading = false;
    });
  }

  Future<void> _saveAndRefresh(List<CctvCamera> updatedList) async {
    setState(() {
      _cameras = updatedList;
    });
    await _cctvService.saveCameras(updatedList);
  }

  void _showAddCameraDialog() {
    final nameCtrl = TextEditingController(text: 'Yoosee Camera');
    final ipCtrl = TextEditingController(text: '192.168.1.100');
    final userCtrl = TextEditingController(text: 'admin');
    final passCtrl = TextEditingController(text: '');
    final pathCtrl = TextEditingController(text: '/onvif1');
    String selectedBrand = 'YOOSEE';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(Icons.videocam, color: Color(0xFF38BDF8)),
                  SizedBox(width: 8),
                  Text('Add CCTV IP Camera', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Camera Brand Preset:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedBrand,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          items: ['YOOSEE', 'TAPO', 'HIKVISION', 'DAHUA', 'REOLINK', 'GENERIC'].map((b) {
                            return DropdownMenuItem<String>(value: b, child: Text(b));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedBrand = val;
                                pathCtrl.text = CctvService.getPresetRtspPath(val);
                                if (val == 'YOOSEE') {
                                  nameCtrl.text = 'Yoosee Camera';
                                  userCtrl.text = 'admin';
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Helpful Yoosee Tip Container
                    if (selectedBrand == 'YOOSEE')
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Color(0xFFFCD34D), size: 14),
                                SizedBox(width: 4),
                                Text('Yoosee Connection Setup:', style: TextStyle(color: Color(0xFFFCD34D), fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              '• Username is always: admin\n'
                              '• Set RTSP password in official Yoosee App ➔ Settings ➔ Security Settings ➔ RTSP / NVR Password.',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),

                    _buildInput('Camera Name', nameCtrl, 'Yoosee Camera'),
                    const SizedBox(height: 10),
                    _buildInput('IP Address', ipCtrl, '192.168.1.100'),
                    const SizedBox(height: 10),
                    _buildInput('Username (Default: admin)', userCtrl, 'admin'),
                    const SizedBox(height: 10),
                    _buildInput('RTSP Password (Set in Yoosee App)', passCtrl, 'Enter RTSP Password', isObscure: true),
                    const SizedBox(height: 10),
                    _buildInput('RTSP Path (/onvif1 = HD, /onvif2 = SD)', pathCtrl, '/onvif1'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                  onPressed: () {
                    if (ipCtrl.text.isEmpty) return;

                    final newCam = CctvCamera(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text.trim().isEmpty ? 'Yoosee Camera' : nameCtrl.text.trim(),
                      ipAddress: ipCtrl.text.trim(),
                      username: userCtrl.text.trim().isEmpty ? 'admin' : userCtrl.text.trim(),
                      password: passCtrl.text,
                      rtspPath: pathCtrl.text.trim(),
                      brand: selectedBrand,
                      isPtzSupported: true,
                    );

                    final newList = List<CctvCamera>.from(_cameras)..add(newCam);
                    _saveAndRefresh(newList);
                    Navigator.pop(context);
                  },
                  child: const Text('Add Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, String hint, {bool isObscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          obscureText: isObscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: const Color(0xFF1E293B),
              elevation: 0,
              title: const Row(
                children: [
                  Icon(Icons.videocam, color: Color(0xFF38BDF8)),
                  SizedBox(width: 8),
                  Text('CCTV IP Cameras', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF10B981)),
                  tooltip: 'Add Camera',
                  onPressed: _showAddCameraDialog,
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF38BDF8),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _showAddCameraDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : _cameras.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.videocam_outlined, color: Color(0xFF38BDF8), size: 64),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'No CCTV Cameras Added Yet',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Connect Hikvision, Dahua, Tapo, Reolink or Yoosee ONVIF IP Cameras to stream live video.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('Add CCTV Camera Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: _showAddCameraDialog,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cameras.length,
                  itemBuilder: (context, index) {
                    final cam = _cameras[index];
                    return CctvPlayerWidget(
                      camera: cam,
                      onDelete: () {
                        final newList = List<CctvCamera>.from(_cameras)..removeAt(index);
                        _saveAndRefresh(newList);
                      },
                    );
                  },
                ),
    );
  }
}
