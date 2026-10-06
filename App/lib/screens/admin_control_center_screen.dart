import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AdminControlCenterScreen extends StatefulWidget {
  const AdminControlCenterScreen({super.key});

  @override
  State<AdminControlCenterScreen> createState() => _AdminControlCenterScreenState();
}

class _AdminControlCenterScreenState extends State<AdminControlCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Users Tab
  List<UserModel> _users = [];
  bool _isLoadingUsers = false;
  String _userSearch = '';
  String _userFilter = 'all'; // 'all', 'admin', 'user', 'disabled'

  // Server Health Tab
  Map<String, dynamic>? _health;
  bool _isLoadingHealth = false;
  Timer? _healthTimer;

  // Account Tab
  Map<String, dynamic>? _accountProfile;
  bool _isLoadingAccount = false;
  final _adminNameCtrl = TextEditingController();
  final _currPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // Gemini AI Tab
  List<String> _geminiKeys = [];
  String _selectedGeminiModel = 'gemini-2.5-flash';
  List<String> _supportedGeminiModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.1-pro',
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
  ];
  bool _isLoadingGemini = false;
  final _geminiKeyCtrl = TextEditingController();
  final Map<String, bool?> _keyTestResults = {};
  final Map<String, bool> _keyTestingState = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUsers();
    _loadHealth();
    _loadAccount();
    _loadGeminiKeys();

    _tabController.addListener(() {
      if (_tabController.index == 1 && _health == null) {
        _loadHealth();
      } else if (_tabController.index == 2 && _accountProfile == null) {
        _loadAccount();
      } else if (_tabController.index == 3 && _geminiKeys.isEmpty) {
        _loadGeminiKeys();
      }
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _tabController.dispose();
    _adminNameCtrl.dispose();
    _currPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGeminiKeys() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoadingGemini = true);
    try {
      final data = await auth.api.getAdminGeminiData();
      if (mounted) {
        setState(() {
          _geminiKeys = List<String>.from(data['keys'] ?? []);
          _selectedGeminiModel = data['model']?.toString() ?? _selectedGeminiModel;
          _supportedGeminiModels = List<String>.from(data['supportedModels'] ?? _supportedGeminiModels);
          _isLoadingGemini = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGemini = false);
    }
  }

  Future<void> _testKey(String key) async {
    setState(() => _keyTestingState[key] = true);
    final auth = Provider.of<AuthService>(context, listen: false);
    final isOk = await auth.api.testGeminiKey(key, model: _selectedGeminiModel);
    if (mounted) {
      setState(() {
        _keyTestingState[key] = false;
        _keyTestResults[key] = isOk;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOk ? 'API Key is active and verified with Google!' : 'API Key check failed. Check key validity/quota.'),
          backgroundColor: isOk ? Colors.green.shade700 : Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // --- Users Management ---
  Future<void> _loadUsers() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoadingUsers = true);
    try {
      final list = await auth.api.getAdminUsers();
      if (mounted) {
        setState(() {
          _users = list;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e')),
        );
      }
    }
  }

  void _showAddUserDialog() {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String role = 'user';
    bool canDeleted = false;
    bool canEdits = false;
    bool canStatus = false;
    bool canReceipts = false;
    bool canChats = true;
    bool canGroups = true;
    bool canStatusSec = true;
    bool canCommunities = true;
    bool canMedia = true;
    bool canAi = true;
    bool canDelMsg = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.person_add_rounded, color: WhatsAppTheme.primaryGreen),
                  SizedBox(width: 8),
                  Text('Add New User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        hintText: 'user@example.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'e.g. Sarah Connor',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('User Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('User', style: TextStyle(fontSize: 14)),
                            value: 'user',
                            groupValue: role,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setDlgState(() => role = v!),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Admin', style: TextStyle(fontSize: 14)),
                            value: 'admin',
                            groupValue: role,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setDlgState(() => role = v!),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const Text('Feature Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: WhatsAppTheme.primaryGreen)),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Access Chats', style: TextStyle(fontSize: 13)),
                      value: canChats,
                      onChanged: (v) => setDlgState(() => canChats = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Access Groups', style: TextStyle(fontSize: 13)),
                      value: canGroups,
                      onChanged: (v) => setDlgState(() => canGroups = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Access Status Updates', style: TextStyle(fontSize: 13)),
                      value: canStatusSec,
                      onChanged: (v) => setDlgState(() => canStatusSec = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Access Communities', style: TextStyle(fontSize: 13)),
                      value: canCommunities,
                      onChanged: (v) => setDlgState(() => canCommunities = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send Media & Attachments', style: TextStyle(fontSize: 13)),
                      value: canMedia,
                      onChanged: (v) => setDlgState(() => canMedia = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use Gemini AI Assistant', style: TextStyle(fontSize: 13)),
                      value: canAi,
                      onChanged: (v) => setDlgState(() => canAi = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delete Messages', style: TextStyle(fontSize: 13)),
                      value: canDelMsg,
                      onChanged: (v) => setDlgState(() => canDelMsg = v),
                    ),
                    const Divider(),
                    const Text('Audit & Visibility Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: WhatsAppTheme.primaryGreen)),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('View Deleted Messages', style: TextStyle(fontSize: 13)),
                      value: canDeleted,
                      onChanged: (v) => setDlgState(() => canDeleted = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('View Edit History', style: TextStyle(fontSize: 13)),
                      value: canEdits,
                      onChanged: (v) => setDlgState(() => canEdits = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('View Status Seen List', style: TextStyle(fontSize: 13)),
                      value: canStatus,
                      onChanged: (v) => setDlgState(() => canStatus = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                  onPressed: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid email')),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    final auth = Provider.of<AuthService>(context, listen: false);
                    try {
                      final created = await auth.api.createAdminUser(
                        email: email,
                        name: nameCtrl.text.trim(),
                        role: role,
                        permissions: {
                          'canViewDeletedMessages': canDeleted,
                          'canViewEditedHistory': canEdits,
                          'canViewStatusSeen': canStatus,
                          'canViewMessageSeen': canReceipts,
                          'canAccessChats': canChats,
                          'canAccessGroups': canGroups,
                          'canAccessStatus': canStatusSec,
                          'canAccessCommunities': canCommunities,
                          'canSendMedia': canMedia,
                          'canUseAi': canAi,
                          'canDeleteMessages': canDelMsg,
                          // backwards compatibility keys:
                          'view_deleted': canDeleted,
                          'view_edited': canEdits,
                          'view_status_seen': canStatus,
                          'view_receipts': canReceipts,
                        },
                      );
                      _loadUsers();
                      _showCreatedPasswordDialog(created['email'] ?? email, created['password'] ?? '');
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  },
                  child: const Text('Create User', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreatedPasswordDialog(String email, String password) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: WhatsAppTheme.primaryGreen),
            SizedBox(width: 8),
            Text('Account Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User email: $email', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Generated Temporary Password:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: WhatsAppTheme.primaryGreen),
                    tooltip: 'Copy Password',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password copied to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Save or share this password with the user. They will use this password to sign into Zelon Messenger.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editUser(UserModel user) {
    final nameCtrl = TextEditingController(text: user.name);
    String role = user.role;
    bool canDeleted = user.permissions.canViewDeletedMessages;
    bool canEdits = user.permissions.canViewEditedHistory;
    bool canStatus = user.permissions.canViewStatusSeen;
    bool canReceipts = user.permissions.canViewMessageSeen;
    bool canChats = user.permissions.canAccessChats;
    bool canGroups = user.permissions.canAccessGroups;
    bool canStatusSec = user.permissions.canAccessStatus;
    bool canCommunities = user.permissions.canAccessCommunities;
    bool canMedia = user.permissions.canSendMedia;
    bool canAi = user.permissions.canUseAi;
    bool canDelMsg = user.permissions.canDeleteMessages;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Edit User: ${user.email}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('User'),
                              value: 'user',
                              groupValue: role,
                              onChanged: (v) => setModalState(() => role = v!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text('Admin'),
                              value: 'admin',
                              groupValue: role,
                              onChanged: (v) => setModalState(() => role = v!),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      const Text('Feature Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: WhatsAppTheme.primaryGreen)),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Access Chats', style: TextStyle(fontSize: 13)),
                        value: canChats,
                        onChanged: (v) => setModalState(() => canChats = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Access Groups', style: TextStyle(fontSize: 13)),
                        value: canGroups,
                        onChanged: (v) => setModalState(() => canGroups = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Access Status Updates', style: TextStyle(fontSize: 13)),
                        value: canStatusSec,
                        onChanged: (v) => setModalState(() => canStatusSec = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Access Communities', style: TextStyle(fontSize: 13)),
                        value: canCommunities,
                        onChanged: (v) => setModalState(() => canCommunities = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Send Media & Attachments', style: TextStyle(fontSize: 13)),
                        value: canMedia,
                        onChanged: (v) => setModalState(() => canMedia = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use Gemini AI Assistant', style: TextStyle(fontSize: 13)),
                        value: canAi,
                        onChanged: (v) => setModalState(() => canAi = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Delete Messages', style: TextStyle(fontSize: 13)),
                        value: canDelMsg,
                        onChanged: (v) => setModalState(() => canDelMsg = v),
                      ),
                      const Divider(),
                      const Text('Audit & Visibility Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: WhatsAppTheme.primaryGreen)),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('View Deleted Messages', style: TextStyle(fontSize: 13)),
                        value: canDeleted,
                        onChanged: (v) => setModalState(() => canDeleted = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('View Edit History', style: TextStyle(fontSize: 13)),
                        value: canEdits,
                        onChanged: (v) => setModalState(() => canEdits = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('View Status Seen List', style: TextStyle(fontSize: 13)),
                        value: canStatus,
                        onChanged: (v) => setModalState(() => canStatus = v),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WhatsAppTheme.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final auth = Provider.of<AuthService>(context, listen: false);
                            try {
                              await auth.api.updateAdminUser(
                                user.id,
                                name: nameCtrl.text.trim(),
                                role: role,
                                permissions: {
                                  'canViewDeletedMessages': canDeleted,
                                  'canViewEditedHistory': canEdits,
                                  'canViewStatusSeen': canStatus,
                                  'canViewMessageSeen': canReceipts,
                                  'canAccessChats': canChats,
                                  'canAccessGroups': canGroups,
                                  'canAccessStatus': canStatusSec,
                                  'canAccessCommunities': canCommunities,
                                  'canSendMedia': canMedia,
                                  'canUseAi': canAi,
                                  'canDeleteMessages': canDelMsg,
                                  // backwards compatibility keys:
                                  'view_deleted': canDeleted,
                                  'view_edited': canEdits,
                                  'view_status_seen': canStatus,
                                  'view_receipts': canReceipts,
                                },
                              );
                              _loadUsers();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('User updated successfully!')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          },
                          child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _resetUserPassword(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password?'),
        content: Text('Generate a new random password for ${user.email}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Password', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final auth = Provider.of<AuthService>(context, listen: false);
      try {
        final newPass = await auth.api.resetAdminUserPassword(user.id);
        _showCreatedPasswordDialog(user.email, newPass);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _deleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Are you sure you want to delete ${user.email}? All associated sessions and WhatsApp links will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final auth = Provider.of<AuthService>(context, listen: false);
      try {
        await auth.api.deleteAdminUser(user.id);
        _loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // --- Server Health Tab ---
  Future<void> _loadHealth() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoadingHealth = true);
    try {
      final h = await auth.api.getAdminSystemHealth();
      if (mounted) {
        setState(() {
          _health = h;
          _isLoadingHealth = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHealth = false);
      }
    }
  }

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days days, $hours hrs';
    if (hours > 0) return '$hours hrs, $mins mins';
    return '$mins mins';
  }

  // --- Account Profile Tab ---
  Future<void> _loadAccount() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoadingAccount = true);
    try {
      final acc = await auth.api.getAccountProfile();
      if (mounted) {
        setState(() {
          _accountProfile = acc;
          _adminNameCtrl.text = acc['name']?.toString() ?? '';
          _isLoadingAccount = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Center', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.people_alt_rounded), text: 'Users'),
            Tab(icon: Icon(Icons.monitor_heart_rounded), text: 'Health'),
            Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'Profile'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Gemini AI'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabController.index == 0) _loadUsers();
              if (_tabController.index == 1) _loadHealth();
              if (_tabController.index == 2) _loadAccount();
              if (_tabController.index == 3) _loadGeminiKeys();
            },
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              heroTag: 'admin_add_user',
              backgroundColor: WhatsAppTheme.primaryGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add),
              label: const Text('Add User'),
              onPressed: _showAddUserDialog,
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(isDark),
          _buildHealthTab(isDark),
          _buildAccountTab(isDark),
          _buildGeminiTab(isDark),
        ],
      ),
    );
  }

  Widget _buildUsersTab(bool isDark) {
    if (_isLoadingUsers && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen));
    }

    final filtered = _users.where((u) {
      if (_userSearch.isNotEmpty) {
        final q = _userSearch.toLowerCase();
        if (!u.email.toLowerCase().contains(q) && !u.name.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_userFilter == 'admin') return u.isAdmin;
      if (_userFilter == 'user') return !u.isAdmin;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: Column(
        children: [
          // Search & Filter header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _userSearch = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.black12 : const Color(0xFFF0F2F5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _filterChip('all', 'All (${_users.length})'),
                    const SizedBox(width: 8),
                    _filterChip('admin', 'Admins (${_users.where((u) => u.isAdmin).length})'),
                    const SizedBox(width: 8),
                    _filterChip('user', 'Users (${_users.where((u) => !u.isAdmin).length})'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _userSearch.isNotEmpty ? 'No users matching "$_userSearch"' : 'No users found',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final u = filtered[i];
                      return _buildUserCard(u, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final isSelected = _userFilter == key;
    return InkWell(
      onTap: () => setState(() => _userFilter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? WhatsAppTheme.primaryGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(UserModel u, bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: u.isAdmin
                  ? WhatsAppTheme.primaryGreen.withOpacity(0.15)
                  : Colors.blueGrey.withOpacity(0.15),
              child: Text(
                u.name.isNotEmpty
                    ? u.name[0].toUpperCase()
                    : (u.email.isNotEmpty ? u.email[0].toUpperCase() : '?'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: u.isAdmin ? WhatsAppTheme.primaryGreen : Colors.blueGrey,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          u.name.isNotEmpty ? u.name : u.email.split('@').first,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: u.isAdmin
                              ? WhatsAppTheme.primaryGreen.withOpacity(0.15)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          u.isAdmin ? 'Admin' : 'User',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: u.isAdmin ? WhatsAppTheme.primaryGreen : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    u.email,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone_android_rounded, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        '${u.instancesCount} linked WA account${u.instancesCount != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (val) {
                if (val == 'edit') _editUser(u);
                if (val == 'reset') _resetUserPassword(u);
                if (val == 'delete') _deleteUser(u);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Details & Roles'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Reset Password'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete User', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Health Tab Widget ---
  Widget _buildHealthTab(bool isDark) {
    if (_isLoadingHealth && _health == null) {
      return const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen));
    }
    if (_health == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            const Text('Unable to reach server metrics'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadHealth,
              style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final h = _health!;
    final dbMs = h['databaseMs'] ?? 0;
    final uptimeSec = h['uptimeSeconds'] ?? 0;
    final mem = h['memory'] as Map<String, dynamic>? ?? {};
    final rssMb = ((mem['rss'] ?? 0) / (1024 * 1024)).toStringAsFixed(1);
    final heapUsedMb = ((mem['heapUsed'] ?? 0) / (1024 * 1024)).toStringAsFixed(1);
    final instances = h['instances'] as Map<String, dynamic>? ?? {};
    final totalInst = instances['total'] ?? 0;
    final sockets = instances['sockets'] ?? 0;
    final counts = h['counts'] as Map<String, dynamic>? ?? {};
    final totalMessages = counts['messages'] ?? 0;
    final totalUsers = counts['users'] ?? 0;

    return RefreshIndicator(
      onRefresh: _loadHealth,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  WhatsAppTheme.primaryGreen,
                  const Color(0xFF075E54),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zelon Core Server Healthy',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'DB Ping: ${dbMs}ms • Engine: Baileys Multi-Device',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Stats Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _metricTile('Active Sockets', '$sockets / $totalInst', Icons.hub_rounded, Colors.teal),
              _metricTile('Server Uptime', _formatUptime(uptimeSec), Icons.timer_outlined, Colors.indigo),
              _metricTile('RAM RSS', '$rssMb MB', Icons.memory_rounded, Colors.purple),
              _metricTile('Heap Used', '$heapUsedMb MB', Icons.storage_rounded, Colors.deepOrange),
              _metricTile('Total Messages', '$totalMessages', Icons.chat_rounded, Colors.green),
              _metricTile('Total Users', '$totalUsers', Icons.people_outline, Colors.blue),
            ],
          ),
          const SizedBox(height: 16),

          // Server details list
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('Node Version'),
                  trailing: Text(h['nodeVersion'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.computer_rounded),
                  title: const Text('Platform'),
                  trailing: Text(h['platform'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.send_rounded),
                  title: const Text('Trigger KeepAlive Ping'),
                  subtitle: const Text('Pings active sockets to keep connection alive'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                    onPressed: () async {
                      final auth = Provider.of<AuthService>(context, listen: false);
                      try {
                        await auth.api.triggerKeepAlive();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Keepalive ping completed successfully!')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    },
                    child: const Text('Run Ping', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  // --- Account Tab Widget ---
  Widget _buildAccountTab(bool isDark) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Details Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Admin Server Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      child: Icon(Icons.shield_rounded, color: Colors.white),
                    ),
                    title: Text(user?.email ?? 'admin', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Super Administrator'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adminNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
                      onPressed: () async {
                        final name = _adminNameCtrl.text.trim();
                        try {
                          await auth.api.updateAccountProfile(name: name);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile updated successfully!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      child: const Text('Update Profile Name', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Change Password Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Change Admin Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                      onPressed: () async {
                        final curr = _currPassCtrl.text.trim();
                        final n1 = _newPassCtrl.text.trim();
                        final n2 = _confirmPassCtrl.text.trim();
                        if (curr.isEmpty || n1.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all password fields')),
                          );
                          return;
                        }
                        if (n1 != n2) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('New passwords do not match')),
                          );
                          return;
                        }
                        try {
                          await auth.api.updateAccountPassword(
                            currentPassword: curr,
                            newPassword: n1,
                          );
                          _currPassCtrl.clear();
                          _newPassCtrl.clear();
                          _confirmPassCtrl.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password updated successfully!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      },
                      child: const Text('Update Password', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Gemini AI Tab Widget ---
  Widget _buildGeminiTab(bool isDark) {
    if (_isLoadingGemini && _geminiKeys.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen));
    }

    return RefreshIndicator(
      onRefresh: _loadGeminiKeys,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gemini Model Selector Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.psychology_rounded, color: WhatsAppTheme.primaryGreen),
                        SizedBox(width: 8),
                        Text('Gemini AI Model Selection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose primary Gemini model (2.5, 3.1, 3.6, 3.8). Automatic model failover will gracefully rotate if a model or tier is unavailable.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _supportedGeminiModels.contains(_selectedGeminiModel) ? _selectedGeminiModel : 'gemini-2.5-flash',
                      decoration: const InputDecoration(
                        labelText: 'Active Model',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      isExpanded: true,
                      items: _supportedGeminiModels.map((m) {
                        String label = m;
                        if (m == 'gemini-3.8-flash') label = 'Gemini 3.8 Flash (Latest Ultra Fast)';
                        else if (m == 'gemini-3.6-flash') label = 'Gemini 3.6 Flash (Fast & Intelligent)';
                        else if (m == 'gemini-3.1-pro') label = 'Gemini 3.1 Pro (Deep Reasoning)';
                        else if (m == 'gemini-2.5-pro') label = 'Gemini 2.5 Pro (Advanced Logic)';
                        else if (m == 'gemini-2.5-flash') label = 'Gemini 2.5 Flash (Next-Gen Balanced)';
                        else if (m == 'gemini-2.5-flash-lite') label = 'Gemini 2.5 Flash-Lite (Lightweight)';
                        else if (m == 'gemini-2.0-flash') label = 'Gemini 2.0 Flash (Real-Time)';
                        else if (m == 'gemini-2.0-flash-lite') label = 'Gemini 2.0 Flash-Lite (Optimized)';
                        else if (m == 'gemini-1.5-pro') label = 'Gemini 1.5 Pro (High Context)';
                        else if (m == 'gemini-1.5-flash') label = 'Gemini 1.5 Flash (Legacy Production)';
                        return DropdownMenuItem<String>(
                          value: m,
                          child: Text(label, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (newModel) async {
                        if (newModel == null) return;
                        setState(() => _selectedGeminiModel = newModel);
                        final auth = Provider.of<AuthService>(context, listen: false);
                        await auth.api.setAdminGeminiModel(newModel);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Active Gemini model set to $newModel'),
                              backgroundColor: WhatsAppTheme.primaryGreen,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // API Keys Management Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome, color: WhatsAppTheme.primaryGreen),
                        SizedBox(width: 8),
                        Text('Gemini API Keys & Failover', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Multi-key failover is active. If any key hits quota/rate limits, the next available key will automatically be used.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _geminiKeyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'New Gemini API Key',
                              hintText: 'AIzaSy...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final key = _geminiKeyCtrl.text.trim();
                            if (key.isEmpty) return;
                            final auth = Provider.of<AuthService>(context, listen: false);
                            try {
                              await auth.api.addAdminGeminiKey(key);
                              _geminiKeyCtrl.clear();
                              _loadGeminiKeys();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Gemini API key added successfully!'),
                                    backgroundColor: WhatsAppTheme.primaryGreen,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WhatsAppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Key'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_geminiKeys.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No Gemini API keys added yet. Add a key above to enable AI Smart Replies.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _geminiKeys.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final key = _geminiKeys[i];
                    final maskedKey = key.length > 8
                        ? '${key.substring(0, 6)}••••••••${key.substring(key.length - 4)}'
                        : '••••••••';
                    final isWorking = _keyTestResults[key];
                    final isTesting = _keyTestingState[key] == true;

                    return ListTile(
                      leading: Icon(
                        isWorking == true
                            ? Icons.check_circle_rounded
                            : (isWorking == false ? Icons.error_outline_rounded : Icons.key_rounded),
                        color: isWorking == true
                            ? Colors.green
                            : (isWorking == false ? Colors.red : Colors.blueGrey),
                      ),
                      title: Text(maskedKey, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                      subtitle: isWorking == true
                          ? const Text('Verified & Active with Google', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold))
                          : (isWorking == false
                              ? const Text('Verification failed (check key/quota)', style: TextStyle(color: Colors.red, fontSize: 11))
                              : const Text('Tap Test to verify with Google', style: TextStyle(fontSize: 11, color: Colors.grey))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isTesting)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline_rounded, color: WhatsAppTheme.primaryGreen),
                              tooltip: 'Test Key',
                              onPressed: () => _testKey(key),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Remove Key',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Remove Key?'),
                                  content: const Text('Are you sure you want to remove this Gemini API key?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                final auth = Provider.of<AuthService>(context, listen: false);
                                try {
                                  await auth.api.removeAdminGeminiKey(key);
                                  _loadGeminiKeys();
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
