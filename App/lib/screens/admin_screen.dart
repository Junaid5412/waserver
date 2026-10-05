import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<UserModel> _users = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      final list = await auth.api.getAdminUsers();
      if (mounted) {
        setState(() {
          _users = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    }
  }

  void _editUserPermissions(UserModel user) {
    bool canDeleted = user.permissions.canViewDeletedMessages;
    bool canEdits = user.permissions.canViewEditedHistory;
    bool canStatus = user.permissions.canViewStatusSeen;
    bool canReceipts = user.permissions.canViewMessageSeen;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: WhatsAppTheme.primaryGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Permissions for ${user.email}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.isAdmin
                        ? 'Administrator (Has full access to all features)'
                        : 'Regular User (Super Admin controls extra feature visibility)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(),

                  SwitchListTile(
                    activeColor: WhatsAppTheme.primaryGreen,
                    title: const Text('View Deleted Messages'),
                    subtitle: const Text('Show deleted text and recovered content badge'),
                    value: canDeleted,
                    onChanged: user.isAdmin ? null : (v) => setModalState(() => canDeleted = v),
                  ),

                  SwitchListTile(
                    activeColor: WhatsAppTheme.primaryGreen,
                    title: const Text('View Edited Message History'),
                    subtitle: const Text('Show "Old was this and Was This" diff drawer'),
                    value: canEdits,
                    onChanged: user.isAdmin ? null : (v) => setModalState(() => canEdits = v),
                  ),

                  SwitchListTile(
                    activeColor: WhatsAppTheme.primaryGreen,
                    title: const Text('View Status Seen & Stealth Mode'),
                    subtitle: const Text('Show who viewed status stories and stealth options'),
                    value: canStatus,
                    onChanged: user.isAdmin ? null : (v) => setModalState(() => canStatus = v),
                  ),

                  SwitchListTile(
                    activeColor: WhatsAppTheme.primaryGreen,
                    title: const Text('View Message Read Receipts'),
                    subtitle: const Text('Show detailed delivery & read receipts analysis'),
                    value: canReceipts,
                    onChanged: user.isAdmin ? null : (v) => setModalState(() => canReceipts = v),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final auth = Provider.of<AuthService>(context, listen: false);
                        try {
                          await auth.api.updateAdminUser(
                            user.id,
                            permissions: {
                              'canViewDeletedMessages': canDeleted,
                              'canViewEditedHistory': canEdits,
                              'canViewStatusSeen': canStatus,
                              'canViewMessageSeen': canReceipts,
                            },
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Permissions updated successfully!')),
                          );
                          _loadUsers();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WhatsAppTheme.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Save Permissions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Permissions Manager'),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
          : RefreshIndicator(
              onRefresh: _loadUsers,
              color: WhatsAppTheme.primaryGreen,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final u = _users[index];
                  final hasAnyPerm = u.isAdmin ||
                      u.permissions.canViewDeletedMessages ||
                      u.permissions.canViewEditedHistory ||
                      u.permissions.canViewStatusSeen ||
                      u.permissions.canViewMessageSeen;

                  return Card(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: u.isAdmin ? Colors.amber.shade700 : WhatsAppTheme.primaryGreen,
                        child: Icon(u.isAdmin ? Icons.admin_panel_settings : Icons.person, color: Colors.white),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(u.email, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: u.isAdmin ? Colors.amber.withOpacity(0.15) : Colors.blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              u.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: u.isAdmin ? Colors.amber.shade900 : Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          u.isAdmin
                              ? 'Full Super Admin Access'
                              : (hasAnyPerm ? 'Custom Permissions Enabled' : 'Standard User (Extra features locked)'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasAnyPerm ? WhatsAppTheme.accentGreen : Colors.grey,
                            fontWeight: hasAnyPerm ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.settings, color: WhatsAppTheme.primaryGreen),
                      onTap: () => _editUserPermissions(u),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
