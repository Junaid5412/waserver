import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/realtime_service.dart';
import '../widgets/chat_avatar.dart';
import 'chat_screen.dart';
import 'connect_screen.dart';

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  List<ChatModel> _groups = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _lastInstanceId;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthService>(context);
    final currentId = auth.selectedInstance?.id;
    if (currentId != _lastInstanceId) {
      _lastInstanceId = currentId;
      _loadGroups();
      _subscribeRealtime();
    }
  }

  void _subscribeRealtime() {
    _sub?.cancel();
    final auth = Provider.of<AuthService>(context, listen: false);
    _sub = auth.realtime.events.listen((event) {
      if (event.type == 'message' || event.type == 'update' || event.type == 'poll_tick') {
        _syncInBackground();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) {
      if (mounted) setState(() => _groups = []);
      return;
    }

    // 1. Instant load from local cache
    final cached = await CacheService.getCachedChats(inst.id);
    final cachedGroups = cached.where((c) => c.isGroup).toList();
    if (cachedGroups.isNotEmpty && mounted) {
      setState(() => _groups = cachedGroups);
    }

    // 2. Fresh network sync
    _syncInBackground();
  }

  Future<void> _syncInBackground() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    try {
      final fresh = await auth.api.getChats(inst.id);
      final freshGroups = fresh.where((c) => c.isGroup).toList();
      if (mounted) {
        setState(() {
          _groups = freshGroups;
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
      final m = local.minute.toString().padLeft(2, '0');
      return '${local.hour}:$m';
    }
    return '${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;

    final filtered = _groups.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.displayTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.lastPreview.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _syncInBackground,
        color: WhatsAppTheme.primaryGreen,
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search groups...',
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

            // Groups List
            Expanded(
              child: _isLoading && _groups.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                inst == null ? 'No account selected' : 'No group chats found',
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
                                  label: const Text('Connect Account', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 76,
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                          itemBuilder: (context, idx) {
                            final chat = filtered[idx];
                            final timeStr = _formatTime(chat.createdAt);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              leading: ChatAvatar(
                                chatId: chat.chatId,
                                title: chat.displayTitle,
                                isGroup: true,
                                radius: 25,
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
                                      chat.lastPreview.isNotEmpty ? chat.lastPreview : 'No group messages yet',
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
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(chat: chat),
                                  ),
                                );
                                _syncInBackground();
                              },
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
