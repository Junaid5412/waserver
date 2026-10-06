import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/instance.dart';
import '../services/auth_service.dart';
import '../services/lock_service.dart';
import '../services/chat_design_service.dart';
import 'admin_control_center_screen.dart';
import 'lock_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

class SettingsScreen extends StatelessWidget {
  final bool showAppBar;
  const SettingsScreen({super.key, this.showAppBar = false});

  void _showPinSetupDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LockScreen(
          isSetup: true,
          onPinCreated: (pin) async {
            final lock = Provider.of<LockService>(context, listen: false);
            await lock.setPin(pin);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('App Lock PIN successfully set!'),
                backgroundColor: WhatsAppTheme.primaryGreen,
              ),
            );
          },
          onUnlocked: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showChatDesignDialog(BuildContext context) {
    final design = Provider.of<ChatDesignService>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Chat Appearance & Customization',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),

                // Wallpaper selection
                const Text('Chat Wallpaper', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    _wallpaperChip('default', 'Default', Colors.grey.shade300, design, setSheetState),
                    _wallpaperChip('dark_slate', 'Slate', const Color(0xFF1E272C), design, setSheetState),
                    _wallpaperChip('mint_emerald', 'Emerald', const Color(0xFF0F382C), design, setSheetState),
                    _wallpaperChip('midnight_navy', 'Navy', const Color(0xFF0D1B2A), design, setSheetState),
                    _wallpaperChip('clean_charcoal', 'Charcoal', const Color(0xFF18191A), design, setSheetState),
                  ],
                ),
                const SizedBox(height: 20),

                // Bubble style
                const Text('Bubble Corner Radius', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _choiceChip('modern_rounded', 'Modern Curved', design.bubbleStyle, (v) {
                      design.setBubbleStyle(v);
                      setSheetState(() {});
                    }),
                    const SizedBox(width: 8),
                    _choiceChip('classic_whatsapp', 'Classic WA', design.bubbleStyle, (v) {
                      design.setBubbleStyle(v);
                      setSheetState(() {});
                    }),
                    const SizedBox(width: 8),
                    _choiceChip('minimalist', 'Flat Minimal', design.bubbleStyle, (v) {
                      design.setBubbleStyle(v);
                      setSheetState(() {});
                    }),
                  ],
                ),
                const SizedBox(height: 20),

                // Font size
                const Text('Chat Font Size', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _choiceChip('compact', 'Small (13.5px)', design.fontSize, (v) {
                      design.setFontSize(v);
                      setSheetState(() {});
                    }),
                    const SizedBox(width: 8),
                    _choiceChip('normal', 'Medium (15px)', design.fontSize, (v) {
                      design.setFontSize(v);
                      setSheetState(() {});
                    }),
                    const SizedBox(width: 8),
                    _choiceChip('comfortable', 'Large (16.5px)', design.fontSize, (v) {
                      design.setFontSize(v);
                      setSheetState(() {});
                    }),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _wallpaperChip(String id, String label, Color color, ChatDesignService design, StateSetter setSheetState) {
    final isSelected = design.wallpaper == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: WhatsAppTheme.primaryGreen,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      avatar: CircleAvatar(backgroundColor: color, radius: 8),
      onSelected: (_) {
        design.setWallpaper(id);
        setSheetState(() {});
      },
    );
  }

  Widget _choiceChip(String id, String label, String currentVal, Function(String) onSelect) {
    final isSelected = currentVal == id;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      selectedColor: WhatsAppTheme.primaryGreen,
      onSelected: (_) => onSelect(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final inst = auth.selectedInstance;
    final lock = Provider.of<LockService>(context);

    // Permission check for Chat Customization: Admin only or granted permission
    final canCustomizeDesign = user != null && (user.isAdmin || user.permissions.canViewDeletedMessages);

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

          // Super Admin Control Center (Admins only)
          if (user != null && user.isAdmin) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [WhatsAppTheme.primaryGreen, Color(0xFF075E54)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: WhatsAppTheme.primaryGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: const CircleAvatar(
                  backgroundColor: Colors.white24,
                  radius: 22,
                  child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 26),
                ),
                title: const Text(
                  'Super Admin Control Center',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.5),
                ),
                subtitle: const Text(
                  'All Users, Health, Broadcasts, AI, Profile',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminControlCenterScreen()),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],

          // Active Instance Selector
          ListTile(
            leading: const Icon(Icons.phone_android, color: WhatsAppTheme.primaryGreen),
            title: const Text('Active Connected Account'),
            subtitle: Text(
              inst != null
                  ? '${inst.name} (${inst.status})${inst.id == auth.defaultInstanceId ? " • Default Account" : ""}'
                  : 'None selected',
            ),
            trailing: PopupMenuButton<InstanceModel>(
              icon: const Icon(Icons.arrow_drop_down),
              onSelected: (selected) => auth.selectInstance(selected),
              itemBuilder: (_) => auth.instances.map((i) {
                final isDef = i.id == auth.defaultInstanceId;
                return PopupMenuItem(
                  value: i,
                  child: Text('${i.name} (${i.status})${isDef ? " [Default]" : ""}'),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // Admin Notices & Announcements
          ListTile(
            leading: const Icon(Icons.campaign_rounded, color: WhatsAppTheme.primaryGreen),
            title: const Text('Admin Notices & Announcements'),
            subtitle: const Text('View broadcast alerts, urgent messages & acknowledgments'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const Divider(height: 1),

          // Security: Fingerprint / PIN Lock
          ListTile(
            leading: const Icon(Icons.fingerprint_rounded, color: WhatsAppTheme.primaryGreen),
            title: const Text('App Lock (Fingerprint & PIN)'),
            subtitle: Text(
              lock.isLockEnabled
                  ? 'Enabled (${lock.timeoutMinutes == 0 ? "Immediately" : "${lock.timeoutMinutes} min"})'
                  : 'Disabled · Tap to set up security PIN',
            ),
            trailing: Switch(
              value: lock.isLockEnabled,
              activeColor: WhatsAppTheme.primaryGreen,
              onChanged: (enabled) {
                if (enabled) {
                  _showPinSetupDialog(context);
                } else {
                  lock.disableLock();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('App Lock disabled')),
                  );
                }
              },
            ),
          ),
          if (lock.isLockEnabled) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Unlock with Fingerprint', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Use biometric sensor to unlock immediately', style: TextStyle(fontSize: 12, color: Colors.grey)),
              value: lock.isBiometricsEnabled,
              activeColor: WhatsAppTheme.primaryGreen,
              onChanged: (val) {
                lock.setBiometricsEnabled(val);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Auto-lock duration', style: TextStyle(fontSize: 14)),
              trailing: DropdownButton<int>(
                value: lock.timeoutMinutes,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Immediately')),
                  DropdownMenuItem(value: 1, child: Text('After 1 min')),
                  DropdownMenuItem(value: 15, child: Text('After 15 min')),
                  DropdownMenuItem(value: 60, child: Text('After 1 hour')),
                ],
                onChanged: (val) {
                  if (val != null) lock.setTimeout(val);
                },
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Change Security PIN', style: TextStyle(fontSize: 14, color: WhatsAppTheme.primaryGreen)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showPinSetupDialog(context),
            ),
          ],
          const Divider(height: 1),

          // Chat Design & Customization (Admin controlled)
          ListTile(
            leading: Icon(
              Icons.palette_outlined,
              color: canCustomizeDesign ? WhatsAppTheme.primaryGreen : Colors.grey,
            ),
            title: const Text('Chat Design & Wallpaper'),
            subtitle: Text(
              canCustomizeDesign
                  ? 'Wallpapers, bubble shapes, and font size'
                  : 'Locked · Admin permission required',
              style: TextStyle(
                fontSize: 12,
                color: canCustomizeDesign ? null : Colors.grey,
              ),
            ),
            trailing: canCustomizeDesign
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.lock, size: 18, color: Colors.grey),
            onTap: canCustomizeDesign
                ? () => _showChatDesignDialog(context)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat customization is restricted by your system administrator.'),
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
