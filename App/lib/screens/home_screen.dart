import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/realtime_service.dart';
import '../widgets/instance_switcher_header.dart';
import '../widgets/header_notification.dart';
import '../models/chat.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';
import 'groups_tab.dart';
import 'status_tab.dart';
import 'tools_screen.dart';
import 'connect_screen.dart';
import 'admin_control_center_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import 'email_main_screen.dart';
import '../config/permissions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  int _unreadBroadcastsCount = 0;

  @override
  void initState() {
    super.initState();
    _checkUnreadBroadcasts();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    _realtimeSub?.cancel();
    final auth = Provider.of<AuthService>(context, listen: false);
    _realtimeSub = auth.realtime.events.listen((event) {
      if (event.type == 'admin_broadcast') {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        _checkUnreadBroadcasts();

        final data = event.raw['data'] as Map<String, dynamic>? ?? {};
        final title = data['title']?.toString() ?? 'Zelon Admin';
        final body = data['body']?.toString() ?? 'You got a new announcement from Admin';

        // Header notification at top of screen
        HeaderNotification.show(
          context,
          title: title,
          message: body,
          type: HeaderNotificationType.info,
          onTap: () => _showBroadcastPopup(data),
        );
        // System tray notification when closed/backgrounded
        HeaderNotification.showSystemNotification(
          title: title,
          body: body,
          isBroadcast: true,
        );

        _showBroadcastPopup(data);
      } else if (event.type == 'message' && event.fromMe != true) {
        final incomingChatId = RealtimeEvent.normalizeJid(event.chatId);

        // Same-Chat Suppression: If user is currently looking at this exact chat, DO NOT show notification!
        if (incomingChatId.isNotEmpty && auth.currentOpenChatId == incomingChatId) {
          return;
        }

        final raw = event.raw['data'] as Map<String, dynamic>? ?? {};
        final sender = raw['pushName']?.toString() ?? 'WhatsApp Contact';
        final text = raw['message']?['conversation']?.toString() ??
            raw['message']?['extendedTextMessage']?['text']?.toString() ??
            (raw['message']?['audioMessage'] != null ? '🎤 Voice message' :
             raw['message']?['imageMessage'] != null ? '📷 Photo' :
             raw['message']?['videoMessage'] != null ? '🎥 Video' :
             raw['message']?['documentMessage'] != null ? '📄 Document' : 'New message received');

        // Top Header Notification Banner
        HeaderNotification.showMessage(
          context,
          sender: sender,
          text: text,
          onTap: () {
            if (incomingChatId.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chat: ChatModel(
                      chatId: incomingChatId,
                      name: sender,
                      lastMessage: text,
                    ),
                  ),
                ),
              );
            }
          },
        );

        // System notification in Android status bar for when app is minimized/closed
        HeaderNotification.showSystemNotification(
          title: sender,
          body: text,
          chatId: incomingChatId,
        );
      }
    });
  }

  Future<void> _checkUnreadBroadcasts() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      final list = await auth.api.getUserBroadcasts();
      final unread = list.where((b) => b['seen'] != true || (b['requireAck'] == true && b['acknowledged'] != true)).length;
      if (mounted) setState(() => _unreadBroadcastsCount = unread);
    } catch (_) {}
  }

  void _showNotificationBanner(String title, String body) {
    if (!mounted) return;
    HeaderNotification.show(
      context,
      title: title,
      message: body,
      type: HeaderNotificationType.info,
    );
  }

  void _showBroadcastPopup(Map<String, dynamic> b) {
    if (!mounted) return;
    final id = b['id']?.toString() ?? '';
    final title = b['title']?.toString() ?? 'Admin Announcement';
    final body = b['body']?.toString() ?? '';
    final requireAck = b['requireAck'] == true;
    final isUrgent = b['urgency'] == 'urgent';

    showDialog(
      context: context,
      barrierDismissible: !requireAck,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isUrgent ? Colors.red.shade100 : WhatsAppTheme.primaryGreen.withOpacity(0.15),
              child: Icon(
                isUrgent ? Icons.warning_amber_rounded : Icons.campaign_rounded,
                color: isUrgent ? Colors.red : WhatsAppTheme.primaryGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUrgent)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                child: const Text('URGENT NOTICE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            Text(
              body,
              style: const TextStyle(fontSize: 14.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          if (!requireAck)
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Dismiss'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              if (requireAck && id.isNotEmpty) {
                final auth = Provider.of<AuthService>(context, listen: false);
                await auth.api.acknowledgeBroadcast(id);
                _checkUnreadBroadcasts();
              }
              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
              }
            },
            child: Text(requireAck ? 'Acknowledge' : 'View Notices', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabWithPermission({
    required Widget child,
    required bool hasAccess,
    required String sectionName,
  }) {
    if (hasAccess) return child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_person_rounded, size: 48, color: Colors.red.shade400),
            ),
            const SizedBox(height: 16),
            const Text(
              'Access Restricted',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your administrator has restricted access to $sectionName for this account.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showInstanceQuickPicker(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instances = auth.instances;
    final current = auth.selectedInstance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Switch Account',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF111B21),
                ),
              ),
              Divider(color: isDark ? Colors.white24 : Colors.black12),
              ...instances.map((i) {
                final isSelected = i.id == current?.id;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? WhatsAppTheme.primaryGreen.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: Icon(
                      i.isConnected ? Icons.check_circle : Icons.circle_outlined,
                      color: i.isConnected ? WhatsAppTheme.accentGreen : Colors.grey,
                    ),
                    title: Text(
                      i.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? WhatsAppTheme.primaryGreen
                            : (isDark ? Colors.white : const Color(0xFF111B21)),
                      ),
                    ),
                    subtitle: Text(
                      i.isConnected ? 'Connected & Ready' : 'Offline',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: WhatsAppTheme.primaryGreen)
                        : null,
                    onTap: () {
                      auth.selectInstance(i);
                      Navigator.pop(ctx);
                    },
                  ),
                );
              }),
              Divider(color: isDark ? Colors.white24 : Colors.black12),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: WhatsAppTheme.primaryGreen),
                title: const Text(
                  'Link Another Device',
                  style: TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final inst = auth.selectedInstance;
    final headerTitle = (inst != null && inst.name.isNotEmpty) ? inst.name : 'Zelon';

    final canChats = UserPermissions.canAccessChatsSection(user);
    final canGroups = UserPermissions.canAccessGroupsSection(user);
    final canStatus = UserPermissions.canAccessStatusSection(user);

    final pages = [
      _buildTabWithPermission(
        child: const ChatsTab(),
        hasAccess: canChats,
        sectionName: 'Chats',
      ),
      _buildTabWithPermission(
        child: const GroupsTab(),
        hasAccess: canGroups,
        sectionName: 'Groups',
      ),
      _buildTabWithPermission(
        child: const StatusTab(),
        hasAccess: canStatus,
        sectionName: 'Status Updates',
      ),
      const ToolsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        elevation: 1,
        titleSpacing: 16,
        title: InkWell(
          onTap: () => _showInstanceQuickPicker(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headerTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
                if (inst != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: inst.isConnected ? const Color(0xFF25D366) : const Color(0xFFFF5252),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // Notification Bell with Badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                tooltip: 'Admin Notices',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  );
                  _checkUnreadBroadcasts();
                },
              ),
              if (_unreadBroadcastsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Center(
                      child: Text(
                        '$_unreadBroadcastsCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Business Email Quick Button
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 23),
            tooltip: 'Business Email',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmailMainScreen()),
              );
            },
          ),

          // Link Device Quick Button
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
            tooltip: 'Link Device',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectScreen()),
              );
            },
          ),

          // 3-Dots Popup Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'notices') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
                _checkUnreadBroadcasts();
              } else if (value == 'email') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EmailMainScreen()),
                );
              } else if (value == 'connect') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectScreen()),
                );
              } else if (value == 'admin') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminControlCenterScreen()),
                );
              } else if (value == 'settings') {
                setState(() => _currentIndex = 4);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'notices',
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded, size: 20, color: WhatsAppTheme.primaryGreen),
                    const SizedBox(width: 12),
                    const Text('Admin Notices'),
                    if (_unreadBroadcastsCount > 0) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '$_unreadBroadcastsCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'email',
                child: Row(
                  children: const [
                    Icon(Icons.mail_outline, size: 20, color: WhatsAppTheme.primaryGreen),
                    SizedBox(width: 12),
                    Text('Business Email'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'connect',
                child: Row(
                  children: const [
                    Icon(Icons.devices, size: 20, color: WhatsAppTheme.primaryGreen),
                    SizedBox(width: 12),
                    Text('Linked Devices'),
                  ],
                ),
              ),
              if (user?.role == 'admin')
                PopupMenuItem(
                  value: 'admin',
                  child: Row(
                    children: const [
                      Icon(Icons.admin_panel_settings, size: 20, color: WhatsAppTheme.primaryGreen),
                      SizedBox(width: 12),
                      Text('Admin Permission Controls'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: const [
                    Icon(Icons.settings, size: 20, color: WhatsAppTheme.primaryGreen),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
        indicatorColor: WhatsAppTheme.primaryGreen.withOpacity(0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: WhatsAppTheme.primaryGreen),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded, color: WhatsAppTheme.primaryGreen),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_large_outlined),
            selectedIcon: Icon(Icons.donut_large_rounded, color: WhatsAppTheme.primaryGreen),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets_rounded, color: WhatsAppTheme.primaryGreen),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: WhatsAppTheme.primaryGreen),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
