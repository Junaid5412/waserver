import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../widgets/instance_switcher_header.dart';
import 'chats_tab.dart';
import 'groups_tab.dart';
import 'status_tab.dart';
import 'tools_screen.dart';
import 'connect_screen.dart';
import 'admin_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    ChatsTab(),
    GroupsTab(),
    StatusTab(),
    ToolsScreen(),
    SettingsScreen(),
  ];

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
              const Text('Switch Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              ...instances.map((i) => ListTile(
                leading: Icon(
                  i.isConnected ? Icons.check_circle : Icons.circle_outlined,
                  color: i.isConnected ? WhatsAppTheme.accentGreen : Colors.grey,
                ),
                title: Text(
                  i.name,
                  style: TextStyle(fontWeight: i.id == current?.id ? FontWeight.bold : FontWeight.normal),
                ),
                subtitle: Text(i.isConnected ? 'Connected' : 'Offline'),
                selected: i.id == current?.id,
                onTap: () {
                  auth.selectInstance(i);
                  Navigator.pop(ctx);
                },
              )),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: WhatsAppTheme.primaryGreen),
                title: const Text('Link Another Device', style: TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold)),
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
            onSelected: (value) {
              if (value == 'connect') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectScreen()),
                );
              } else if (value == 'admin') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                );
              } else if (value == 'settings') {
                setState(() => _currentIndex = 4);
              }
            },
            itemBuilder: (ctx) => [
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
        children: _pages,
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
