import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/campaign.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'connect_screen.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  List<CampaignModel> _campaigns = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    setState(() => _isLoading = true);
    try {
      final list = await auth.api.getCampaigns(inst.id);
      if (mounted) {
        setState(() {
          _campaigns = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section: Engine
          _sectionHeader('COMMUNICATION ENGINE'),
          _toolTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Link Account Device',
            subtitle: auth.selectedInstance?.isConnected == true
                ? 'Connected (+${auth.selectedInstance?.phone ?? ""})'
                : 'Disconnected · Scan QR or Pair',
            color: WhatsAppTheme.primaryGreen,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectScreen()),
              );
            },
          ),
          _toolTile(
            icon: Icons.sync_rounded,
            title: 'Restart Engine Connection',
            subtitle: 'Restart socket connection safely without losing session',
            color: Colors.teal,
            onTap: () async {
              if (auth.selectedInstance != null) {
                try {
                  await auth.api.restartInstance(auth.selectedInstance!.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Restarting connection...')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 20),

          // Section: Marketing & Automation (Website parity)
          _sectionHeader('BROADCAST & AUTOMATION'),
          _toolTile(
            icon: Icons.campaign_rounded,
            title: 'Broadcast Campaigns',
            subtitle: '${_campaigns.length} campaigns recorded',
            color: Colors.deepPurple,
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Campaigns', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 12),
                      if (_campaigns.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text('No active campaigns. Create from website or API.')),
                        )
                      else
                        ..._campaigns.map((c) => ListTile(
                          title: Text(c.name),
                          subtitle: Text('Status: ${c.status} · Sent: ${c.sent}/${c.total}'),
                          leading: const Icon(Icons.send_rounded, color: WhatsAppTheme.primaryGreen),
                        )),
                    ],
                  ),
                ),
              );
            },
          ),
          _toolTile(
            icon: Icons.reply_all_rounded,
            title: 'Auto-Reply Rules',
            subtitle: 'Automatic replies with keyword matching and cooldown',
            color: Colors.blue,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Auto-reply rules are active on server.')),
              );
            },
          ),

          const SizedBox(height: 20),

          // Section: Super Admin Tools (Only for admin)
          if (user != null && user.isAdmin) ...[
            _sectionHeader('SUPER ADMIN CONTROLS'),
            _toolTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'User Permissions Manager',
              subtitle: 'Allow/deny Deleted Messages, Edited History & Status Seen per user',
              color: Colors.amber.shade800,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: WhatsAppTheme.grayTick,
        ),
      ),
    );
  }

  Widget _toolTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
