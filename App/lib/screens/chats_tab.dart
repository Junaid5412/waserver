import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'chat_screen.dart';
import 'connect_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  List<ChatModel> _chats = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    // 1. Instant cache load
    final cached = await CacheService.getCachedChats(inst.id);
    if (cached.isNotEmpty && mounted) {
      setState(() => _chats = cached);
    }

    // 2. Fresh network sync
    setState(() => _isLoading = true);
    try {
      final fresh = await auth.api.getChats(inst.id, search: _searchQuery.isNotEmpty ? _searchQuery : null);
      if (mounted) {
        setState(() {
          _chats = fresh;
          _isLoading = false;
        });
        await CacheService.saveChats(inst.id, fresh);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return DateFormat('HH:mm').format(local);
    }
    if (now.difference(local).inDays == 1) return 'Yesterday';
    return DateFormat('dd/MM/yy').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filtered = _searchQuery.isEmpty
        ? _chats
        : _chats.where((c) =>
            c.displayTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            c.lastPreview.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadChats,
        color: WhatsAppTheme.primaryGreen,
        child: Column(
          children: [
            // WhatsApp Connection Status Warning if not connected
            if (inst != null && !inst.isConnected) ...[
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ConnectScreen()),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.amber.shade700,
                  child: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'WhatsApp not connected. Tap here to scan QR or pair.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search or start new chat',
                    prefixIcon: Icon(Icons.search, size: 20, color: WhatsAppTheme.grayTick),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim());
                  },
                ),
              ),
            ),

            // Chats List
            Expanded(
              child: _isLoading && _chats.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                inst == null ? 'No instance selected' : 'No chats found',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                              ),
                              if (inst != null && !inst.isConnected) ...[
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const ConnectScreen()),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: WhatsAppTheme.primaryGreen,
                                  ),
                                  icon: const Icon(Icons.qr_code, color: Colors.white),
                                  label: const Text('Connect WhatsApp', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 76,
                            color: isDark ? Colors.white12 : Colors.grey.shade200,
                          ),
                          itemBuilder: (context, index) {
                            final chat = filtered[index];
                            final timeStr = _formatTime(chat.createdAt);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 25,
                                backgroundColor: WhatsAppTheme.tealGreen.withOpacity(0.18),
                                child: Text(
                                  chat.displayTitle.isNotEmpty ? chat.displayTitle[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: WhatsAppTheme.primaryGreen,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: chat.unread > 0 ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: chat.unread > 0 ? WhatsAppTheme.unreadBadge : WhatsAppTheme.grayTick,
                                      fontWeight: chat.unread > 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat.lastPreview.isNotEmpty ? chat.lastPreview : 'No messages yet',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  if (chat.unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: WhatsAppTheme.unreadBadge,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${chat.unread}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(chat: chat),
                                  ),
                                ).then((_) => _loadChats());
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppTheme.fabGreen,
        onPressed: () {
          // Quick connect or new message
          if (inst != null && !inst.isConnected) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectScreen()),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Select a chat to send messages or use the search bar above.')),
            );
          }
        },
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }
}
