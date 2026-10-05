import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../models/instance.dart';
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
  List<ChatModel> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = 'all'; // 'all', 'groups', 'communities', 'channels'
  String? _lastInstanceId;
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounceTimer;

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
      if (event.type == 'message' || event.type == 'update' || event.type == 'poll_tick' || event.type == 'ready') {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _syncInBackground();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) {
      if (mounted) setState(() => _items = []);
      return;
    }

    // 1. Instant load from local cache
    final cached = await CacheService.getCachedChats(inst.id);
    final cachedNonDirect = cached.where((c) => !c.isDirect && !c.isStatus).toList();
    if (cachedNonDirect.isNotEmpty && mounted) {
      setState(() => _items = cachedNonDirect);
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
      final freshNonDirect = fresh.where((c) => !c.isDirect && !c.isStatus).toList();
      if (mounted) {
        setState(() {
          _items = freshNonDirect;
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

  Widget _buildCategoryChip({
    required String key,
    required String label,
    required int count,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedCategory == key;
    final primaryColor = WhatsAppTheme.primaryGreen;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              _selectedCategory = key;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200),
              borderRadius: BorderRadius.circular(20),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.25)
                          : (isDark ? Colors.white12 : Colors.black12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(InstanceModel? inst, bool isDark) {
    if (inst == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_circle_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No account selected',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (!inst.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'WhatsApp not connected',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
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
        ),
      );
    }

    IconData emptyIcon;
    String emptyTitle;
    String emptySubtitle;

    switch (_selectedCategory) {
      case 'channels':
        emptyIcon = Icons.campaign_outlined;
        emptyTitle = 'No Channels Yet';
        emptySubtitle = 'Follow WhatsApp channels to get updates and announcements here.';
        break;
      case 'communities':
        emptyIcon = Icons.diversity_3_outlined;
        emptyTitle = 'No Communities Yet';
        emptySubtitle = 'Join or create communities to organize related groups in one place.';
        break;
      case 'groups':
        emptyIcon = Icons.groups_outlined;
        emptyTitle = 'No Group Chats';
        emptySubtitle = 'Group conversations you participate in will show up here.';
        break;
      default:
        emptyIcon = Icons.forum_outlined;
        emptyTitle = 'No Groups, Communities or Channels';
        emptySubtitle = 'All shared groups, community announcements, and followed channels appear here.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 64, color: isDark ? Colors.white38 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              emptyTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white87 : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ChatModel chat, bool isDark) {
    if (chat.isChannel) {
      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF11CDEF).withOpacity(0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_rounded, size: 11, color: Color(0xFF0097A7)),
            SizedBox(width: 3),
            Text(
              'Channel',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0097A7),
              ),
            ),
          ],
        ),
      );
    }
    if (chat.isCommunity) {
      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.indigo.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.diversity_3_rounded, size: 11, color: Colors.indigo),
            SizedBox(width: 3),
            Text(
              'Community',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.indigo,
              ),
            ),
          ],
        ),
      );
    }
    if (chat.isGroup && _selectedCategory == 'all') {
      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Group',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: WhatsAppTheme.primaryGreen,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;

    // Counts
    final allCount = _items.length;
    final groupsCount = _items.where((c) => c.isGroup).length;
    final communitiesCount = _items.where((c) => c.isCommunity).length;
    final channelsCount = _items.where((c) => c.isChannel).length;

    // 1. Filter by category
    final categoryFiltered = _items.where((c) {
      if (_selectedCategory == 'groups') return c.isGroup;
      if (_selectedCategory == 'communities') return c.isCommunity;
      if (_selectedCategory == 'channels') return c.isChannel;
      return true;
    }).toList();

    // 2. Filter by search query
    final filtered = categoryFiltered.where((c) {
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
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: _selectedCategory == 'channels'
                        ? 'Search channels...'
                        : _selectedCategory == 'communities'
                            ? 'Search communities...'
                            : _selectedCategory == 'groups'
                                ? 'Search groups...'
                                : 'Search groups, communities & channels...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20, color: WhatsAppTheme.grayTick),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val.trim());
                  },
                ),
              ),
            ),

            // Segmented Category Tabs Row
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildCategoryChip(
                    key: 'all',
                    label: 'All',
                    count: allCount,
                    icon: Icons.forum_outlined,
                    isDark: isDark,
                  ),
                  _buildCategoryChip(
                    key: 'groups',
                    label: 'Groups',
                    count: groupsCount,
                    icon: Icons.groups_outlined,
                    isDark: isDark,
                  ),
                  _buildCategoryChip(
                    key: 'communities',
                    label: 'Communities',
                    count: communitiesCount,
                    icon: Icons.diversity_3_outlined,
                    isDark: isDark,
                  ),
                  _buildCategoryChip(
                    key: 'channels',
                    label: 'Channels',
                    count: channelsCount,
                    icon: Icons.campaign_outlined,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Groups / Communities / Channels List
            Expanded(
              child: _isLoading && _items.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
                  : filtered.isEmpty
                      ? _buildEmptyState(inst, isDark)
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
                                isGroup: chat.isGroup,
                                isCommunity: chat.isCommunity,
                                isChannel: chat.isChannel,
                                radius: 25,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
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
                                        _buildTypeBadge(chat, isDark),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                                      chat.lastPreview.isNotEmpty
                                          ? chat.lastPreview
                                          : (chat.isChannel
                                              ? 'No channel updates yet'
                                              : chat.isCommunity
                                                  ? 'No community messages yet'
                                                  : 'No group messages yet'),
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
