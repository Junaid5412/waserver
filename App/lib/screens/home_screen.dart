import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'chats_tab.dart';
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 4 Tabs: Camera/QR, Chats, Updates, Tools
    _tabController = TabController(length: 4, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final inst = auth.selectedInstance;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'WhatsApp',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),
            // Instance connection indicator dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: inst?.isConnected == true ? WhatsAppTheme.accentGreen : Colors.amber,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Link WhatsApp Device',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConnectScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _tabController.animateTo(1);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              switch (val) {
                case 'link':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen()));
                  break;
                case 'admin':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen()));
                  break;
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'link',
                child: Row(
                  children: const [
                    Icon(Icons.devices, size: 20, color: WhatsAppTheme.primaryGreen),
                    SizedBox(width: 10),
                    Text('Linked devices'),
                  ],
                ),
              ),
              if (user != null && user.isAdmin)
                PopupMenuItem(
                  value: 'admin',
                  child: Row(
                    children: const [
                      Icon(Icons.admin_panel_settings, size: 20, color: Colors.amber),
                      SizedBox(width: 10),
                      Text('Admin Permissions'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: const [
                    Icon(Icons.settings, size: 20, color: Colors.grey),
                    SizedBox(width: 10),
                    Text('Settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3.5,
          isScrollable: true,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt, size: 20)),
            Tab(text: 'CHATS'),
            Tab(text: 'STATUS'),
            Tab(text: 'TOOLS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 0. Camera / Quick QR Connect
          const ConnectScreen(),

          // 1. WhatsApp Chats
          const ChatsTab(),

          // 2. Status Updates
          const StatusTab(),

          // 3. Website parity tools
          const ToolsScreen(),
        ],
      ),
    );
  }
}
