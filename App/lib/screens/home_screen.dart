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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        elevation: 1,
        titleSpacing: 16,
        title: const Text(
          'Zelon Messenger',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: Colors.white,
          ),
        ),
        actions: [
          // Instant Header Instance Switcher Chip
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: InstanceSwitcherHeader(),
            ),
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
