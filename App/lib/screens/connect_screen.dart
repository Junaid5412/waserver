import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/instance.dart';
import '../services/auth_service.dart';
import '../widgets/qr_widget.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _phoneController = TextEditingController();
  final _newInstanceController = TextEditingController();

  String _qrCode = '';
  String _pairingCode = '';
  bool _isLoadingQr = false;
  bool _isLoadingPair = false;
  Timer? _qrPollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startQrFlow();
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _tabController.dispose();
    _phoneController.dispose();
    _newInstanceController.dispose();
    super.dispose();
  }

  Future<void> _startQrFlow() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    setState(() => _isLoadingQr = true);
    try {
      await auth.api.connectInstance(inst.id);
      await _fetchQr();
      _qrPollTimer?.cancel();
      _qrPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
        await _fetchQr();
        await auth.refreshInstances();
      });
    } catch (_) {
      setState(() => _isLoadingQr = false);
    }
  }

  Future<void> _fetchQr() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    try {
      final qr = await auth.api.getQrCode(inst.id);
      if (mounted) {
        setState(() {
          if (qr != null && qr.isNotEmpty) {
            _qrCode = qr;
          }
          _isLoadingQr = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestPairingCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter phone number with country code')),
      );
      return;
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    setState(() => _isLoadingPair = true);
    try {
      final code = await auth.api.requestPairingCode(inst.id, phone);
      setState(() {
        _pairingCode = code;
        _isLoadingPair = false;
      });
    } catch (e) {
      setState(() => _isLoadingPair = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showCreateInstanceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Account'),
        content: TextField(
          controller: _newInstanceController,
          decoration: const InputDecoration(
            labelText: 'Instance Name',
            hintText: 'e.g. Support Phone 1',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = _newInstanceController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                final auth = Provider.of<AuthService>(context, listen: false);
                try {
                  final newInst = await auth.api.createInstance(name);
                  await auth.refreshInstances();
                  auth.selectInstance(newInst);
                  _startQrFlow();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Account Device'),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        actions: [
          PopupMenuButton<InstanceModel>(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Switch Instance',
            onSelected: (i) {
              auth.selectInstance(i);
              _startQrFlow();
            },
            itemBuilder: (_) => auth.instances.map((i) {
              return PopupMenuItem<InstanceModel>(
                value: i,
                child: Row(
                  children: [
                    Icon(
                      i.isConnected ? Icons.check_circle : Icons.circle_outlined,
                      color: i.isConnected ? WhatsAppTheme.accentGreen : Colors.grey,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.name)),
                  ],
                ),
              );
            }).toList(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Instance',
            onPressed: _showCreateInstanceDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR Code'),
            Tab(icon: Icon(Icons.vpn_key), text: 'Pairing Code'),
          ],
        ),
      ),
      body: inst == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No account found'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _showCreateInstanceDialog,
                    style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                    child: const Text('Create Account', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. QR Code Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Status card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: inst.isConnected
                              ? WhatsAppTheme.accentGreen.withOpacity(0.12)
                              : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: inst.isConnected ? WhatsAppTheme.accentGreen : Colors.amber,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              inst.isConnected ? Icons.check_circle : Icons.sync,
                              color: inst.isConnected ? WhatsAppTheme.accentGreen : Colors.amber.shade800,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inst.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    inst.isConnected
                                        ? 'Connected: +${inst.phone ?? ""}'
                                        : 'Status: ${inst.status.replaceAll("_", " ")}',
                                    style: TextStyle(
                                      color: inst.isConnected ? Colors.green.shade800 : Colors.amber.shade900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Instructions
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'To link WhatsApp to this app:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Open WhatsApp on your phone\n'
                        '2. Tap Menu ⋮ or Settings and select Linked Devices\n'
                        '3. Tap Link a Device and point your camera at this QR code',
                        style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),

                      // QR Widget
                      QrWidget(
                        qrData: _qrCode,
                        isLoading: _isLoadingQr,
                        onRefresh: _startQrFlow,
                      ),
                    ],
                  ),
                ),

                // 2. Pairing Code Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Link with Phone Number',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your WhatsApp number with international country code (e.g. +923001234567 or +97450000000).',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+923001234567',
                          prefixIcon: const Icon(Icons.phone, color: WhatsAppTheme.primaryGreen),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoadingPair ? null : _requestPairingCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WhatsAppTheme.primaryGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoadingPair
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Get Pairing Code', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_pairingCode.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: WhatsAppTheme.primaryGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: WhatsAppTheme.primaryGreen.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              const Text('YOUR 8-DIGIT PAIRING CODE:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              const SizedBox(height: 10),
                              Text(
                                _pairingCode,
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4.0, color: WhatsAppTheme.primaryGreen),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pairingCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Pairing code copied to clipboard!')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                                label: const Text('Copy Code', style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
