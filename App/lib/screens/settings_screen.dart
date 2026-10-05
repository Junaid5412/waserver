import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/instance.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool showAppBar;
  const SettingsScreen({super.key, this.showAppBar = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final inst = auth.selectedInstance;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: const Text('Settings'),
              backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
            )
          : null,
      body: ListView(
        children: [
          // User Profile Card
          if (user != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: WhatsAppTheme.primaryGreen,
                    child: Text(
                      user.email.isNotEmpty ? user.email[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isNotEmpty ? user.name : user.email.split('@')[0],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: user.isAdmin ? Colors.amber.withOpacity(0.15) : Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user.role.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: user.isAdmin ? Colors.amber.shade900 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // Active Instance Selector
          ListTile(
            leading: const Icon(Icons.phone_android, color: WhatsAppTheme.primaryGreen),
            title: const Text('Active Connected Account'),
            subtitle: Text(inst != null ? '${inst.name} (${inst.status})' : 'None selected'),
            trailing: PopupMenuButton<InstanceModel>(
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (selected) => auth.selectInstance(selected),
              itemBuilder: (_) => auth.instances.map((i) {
                return PopupMenuItem(
                  value: i,
                  child: Text('${i.name} (${i.status})'),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // Server Endpoint
          ListTile(
            leading: const Icon(Icons.dns, color: WhatsAppTheme.primaryGreen),
            title: const Text('Server API Endpoint'),
            subtitle: Text(ApiConfig.baseUrl),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final controller = TextEditingController(text: ApiConfig.baseUrl);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Change Server URL'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () async {
                        await ApiConfig.setBaseUrl(controller.text.trim());
                        Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),

          // Permissions Summary for Normal Users
          if (user != null && !user.isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.lock_clock, color: WhatsAppTheme.primaryGreen),
              title: const Text('Account Feature Permissions'),
              subtitle: Text(
                'Deleted Msgs: ${user.permissions.canViewDeletedMessages ? "Allowed" : "Locked"} · '
                'Edits Diff: ${user.permissions.canViewEditedHistory ? "Allowed" : "Locked"}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
          ],

          // Sign Out Button
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Log out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text('Are you sure you want to sign out of this device?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Sign out', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await auth.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
          const Divider(height: 1),

          const SizedBox(height: 40),
          const Center(
            child: Text(
              'Zelon WhatsApp App v1.0.0\nProfessional WhatsApp Engine',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
