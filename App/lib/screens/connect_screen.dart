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
  bool _showLinkFlow = false;
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
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _tabController.dispose();
    _phoneController.dispose();
    _newInstanceController.dispose();
    super.dispose();
  }

  void _startLinkingFlow([InstanceModel? targetInstance]) {
    if (targetInstance == null) {
      _showCreateInstanceDialog();
      return;
    }
    _proceedToLinkFlow(targetInstance);
  }

  void _proceedToLinkFlow(InstanceModel targetInstance) {
    final auth = Provider.of<AuthService>(context, listen: false);
    auth.selectInstance(targetInstance);
    setState(() {
      _showLinkFlow = true;
      _pairingCode = '';
    });
    _startQrFlow();
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
        final current = auth.selectedInstance;
        if (current?.isConnected == true && mounted) {
          _qrPollTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device linked successfully!'),
              backgroundColor: WhatsAppTheme.primaryGreen,
            ),
          );
          setState(() => _showLinkFlow = false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingQr = false);
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
      _qrPollTimer?.cancel();
      _qrPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        await auth.refreshInstances();
        final current = auth.selectedInstance;
        if (current?.isConnected == true && mounted) {
          _qrPollTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp linked successfully!'),
              backgroundColor: WhatsAppTheme.primaryGreen,
            ),
          );
          setState(() => _showLinkFlow = false);
        }
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
    final auth = Provider.of<AuthService>(context, listen: false);
    if (_newInstanceController.text.trim().isEmpty) {
      _newInstanceController.text = 'WhatsApp ${auth.instances.length + 1}';
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name Your WhatsApp Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give this WhatsApp connection a name to easily identify it:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newInstanceController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                hintText: 'e.g. Personal WhatsApp',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
                  _startLinkingFlow(newInst);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            child: const Text('Create & Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final instances = auth.instances;
    final activeInst = auth.selectedInstance;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1F2C34), const Color(0xFF121B22)]
                    : [WhatsAppTheme.primaryGreen, WhatsAppTheme.tealGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.devices_other_rounded, color: Colors.white, size: 52),
                const SizedBox(height: 12),
                const Text(
                  'Connected WhatsApp Accounts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use your WhatsApp accounts seamlessly inside Zelon Messenger with instant multi-device sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _startLinkingFlow(),
                  icon: const Icon(Icons.qr_code_scanner_rounded, color: WhatsAppTheme.primaryGreen),
                  label: const Text(
                    'Link a Device',
                    style: TextStyle(
                      color: WhatsAppTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                'Device Status',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _showCreateInstanceDialog,
                icon: const Icon(Icons.add, size: 18, color: WhatsAppTheme.primaryGreen),
                label: const Text('Add Account', style: TextStyle(color: WhatsAppTheme.primaryGreen)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (instances.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No WhatsApp accounts added yet. Tap "Link a Device" above.'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: instances.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final inst = instances[i];
                final isSelected = inst.id == activeInst?.id;
                final isOnline = inst.isConnected;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? WhatsAppTheme.primaryGreen
                          : (isDark ? Colors.white10 : Colors.black12),
                      width: isSelected ? 1.8 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isOnline
                                ? WhatsAppTheme.accentGreen.withOpacity(0.15)
                                : Colors.grey.shade200,
                            child: Icon(
                              Icons.phone_android_rounded,
                              color: isOnline ? WhatsAppTheme.accentGreen : Colors.grey.shade600,
                              size: 26,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isOnline ? const Color(0xFF25D366) : const Color(0xFFFF5252),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  inst.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: WhatsAppTheme.primaryGreen.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Active',
                                      style: TextStyle(
                                        color: WhatsAppTheme.primaryGreen,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isOnline
                                  ? (inst.phone != null && inst.phone!.isNotEmpty ? '+${inst.phone}' : 'Connected & Synced')
                                  : 'Disconnected / Tap to Link',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isOnline ? Colors.green : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isOnline)
                        ElevatedButton(
                          onPressed: () => _startLinkingFlow(inst),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WhatsAppTheme.primaryGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Link', style: TextStyle(color: Colors.white, fontSize: 12)),
                        )
                      else if (!isSelected)
                        TextButton(
                          onPressed: () => auth.selectInstance(inst),
                          child: const Text('Switch', style: TextStyle(color: WhatsAppTheme.primaryGreen)),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLinkFlowView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;

    return Column(
      children: [
        Container(
          color: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan QR Code'),
              Tab(icon: Icon(Icons.phone_android_rounded), text: 'Pair Phone Code'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 1. QR Flow
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Linking: ${inst?.name ?? "WhatsApp"}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          if (_qrCode.isNotEmpty)
                            Center(
                              child: QrWidget(
                                qrData: _qrCode,
                                onRefresh: _startQrFlow,
                                isLoading: _isLoadingQr,
                              ),
                            )
                          else if (_isLoadingQr)
                            const SizedBox(
                              height: 220,
                              child: Center(
                                child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
                              ),
                            )
                          else
                            const SizedBox(
                              height: 220,
                              child: Center(child: Text('Generating QR code...')),
                            ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _startQrFlow,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Refresh QR'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Instructions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 8),
                          Text('1. Open WhatsApp on your mobile phone'),
                          Text('2. Tap Menu (⋮) on Android or Settings on iPhone'),
                          Text('3. Select "Linked Devices" > "Link a Device"'),
                          Text('4. Point your camera at this QR code to sign in'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Pairing Flow
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enter Phone Number with Country Code',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Example: +1234567890 or 447123456789',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.phone),
                              hintText: '+1 234 567 8900',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoadingPair ? null : _requestPairingCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WhatsAppTheme.primaryGreen,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _isLoadingPair
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Get 8-Digit Pairing Code', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_pairingCode.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: WhatsAppTheme.accentGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: WhatsAppTheme.accentGreen),
                        ),
                        child: Column(
                          children: [
                            const Text('Your WhatsApp Pairing Code:', style: TextStyle(fontSize: 13)),
                            const SizedBox(height: 8),
                            SelectableText(
                              _pairingCode,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: WhatsAppTheme.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _pairingCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        Text('Pairing code copied: $_pairingCode'),
                                      ],
                                    ),
                                    backgroundColor: WhatsAppTheme.primaryGreen,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white),
                              label: const Text('Copy Pairing Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WhatsAppTheme.primaryGreen,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Open WhatsApp > Linked Devices > Link with phone number and enter this code.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showLinkFlow ? 'Link New Device' : 'Linked Devices'),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        leading: _showLinkFlow
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _qrPollTimer?.cancel();
                  setState(() => _showLinkFlow = false);
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (!_showLinkFlow)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Account',
              onPressed: _showCreateInstanceDialog,
            ),
        ],
      ),
      body: _showLinkFlow ? _buildLinkFlowView(context) : _buildDevicesList(context),
    );
  }
}
