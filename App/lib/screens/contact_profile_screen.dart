import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../services/auth_service.dart';
import '../widgets/chat_avatar.dart';
import 'call_screen.dart';

class ContactProfileScreen extends StatefulWidget {
  final ChatModel chat;

  const ContactProfileScreen({super.key, required this.chat});

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  Map<String, dynamic> _info = {};
  bool _isLoadingInfo = true;

  @override
  void initState() {
    super.initState();
    _loadChatInfo();
  }

  Future<void> _loadChatInfo() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) {
      if (mounted) setState(() => _isLoadingInfo = false);
      return;
    }

    try {
      final data = await auth.api.getChatInfo(instanceId, widget.chat.chatId);
      if (mounted) {
        setState(() {
          _info = data;
          _isLoadingInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingInfo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    final chat = widget.chat;
    final isGroup = chat.isGroup;
    final rawNumber = chat.chatId.split('@').first;
    final formattedPhone = rawNumber.isNotEmpty ? '+$rawNumber' : chat.chatId;

    // Real dynamic data extracted from Baileys
    final realAbout = _info['about']?.toString().isNotEmpty == true
        ? _info['about'].toString()
        : (_info['status']?.toString().isNotEmpty == true
            ? _info['status'].toString()
            : null);

    final realDesc = _info['description']?.toString().isNotEmpty == true
        ? _info['description'].toString()
        : null;

    final createdAtStr = _info['createdAt'] != null
        ? DateFormat('MMMM d, yyyy').format(DateTime.parse(_info['createdAt'].toString()).toLocal())
        : null;

    final ownerName = _info['owner']?.toString();
    final participants = (_info['participants'] as List?)?.map((p) => Map<String, dynamic>.from(p)).toList() ?? [];

    return Scaffold(
      backgroundColor: isDark ? WhatsAppTheme.bgDark : const Color(0xFFF0F2F5),
      body: CustomScrollView(
        slivers: [
          // App Bar with large Profile Avatar
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded, color: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Share ${chat.displayTitle}')),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                chat.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (instanceId != null && !isGroup && !chat.isChannel && !chat.isCommunity)
                    Image.network(
                      ApiConfig.chatPictureUrl(instanceId, chat.chatId),
                      headers: auth.api.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
                        child: Center(
                          child: ChatAvatar(
                            chatId: chat.chatId,
                            title: chat.displayTitle,
                            isGroup: isGroup,
                            isCommunity: chat.isCommunity,
                            isChannel: chat.isChannel,
                            radius: 64,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
                      child: Center(
                        child: ChatAvatar(
                          chatId: chat.chatId,
                          title: chat.displayTitle,
                          isGroup: isGroup,
                          isCommunity: chat.isCommunity,
                          isChannel: chat.isChannel,
                          radius: 64,
                        ),
                      ),
                    ),
                  // Gradient shadow at bottom of image
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 90,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Profile Body Content
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Name & Phone / JID Card
                Container(
                  width: double.infinity,
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.displayTitle,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        chat.isChannel
                            ? 'Channel ID: ${chat.chatId}'
                            : chat.isCommunity
                                ? 'Community ID: ${chat.chatId}'
                                : isGroup
                                    ? 'Group ID: ${chat.chatId}'
                                    : formattedPhone,
                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 16),

                      // Action Buttons Row (Message, Audio, Video, Search)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _actionBtn(
                            context,
                            Icons.chat_rounded,
                            'Message',
                            () => Navigator.pop(context),
                          ),
                          _actionBtn(
                            context,
                            Icons.call_rounded,
                            'Audio',
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(chat: chat, isVideo: false),
                                ),
                              );
                            },
                          ),
                          _actionBtn(
                            context,
                            Icons.videocam_rounded,
                            'Video',
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(chat: chat, isVideo: true),
                                ),
                              );
                            },
                          ),
                          _actionBtn(
                            context,
                            Icons.search_rounded,
                            'Search',
                            () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // About & Status (Original Data)
                Container(
                  width: double.infinity,
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.isChannel
                            ? 'Channel Description'
                            : chat.isCommunity
                                ? 'Community Description'
                                : isGroup
                                    ? 'Group Description'
                                    : 'About & Phone',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: WhatsAppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isLoadingInfo)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryGreen),
                          ),
                        )
                      else
                        Text(
                          isGroup
                              ? (realDesc ?? 'No group description provided.')
                              : (realAbout ?? 'Hey there! I am using WhatsApp.'),
                          style: const TextStyle(fontSize: 15),
                        ),
                      if (!isGroup) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(formattedPhone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text('Mobile Phone', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                            const Icon(Icons.phone_rounded, color: WhatsAppTheme.primaryGreen),
                          ],
                        ),
                      ],
                      if (isGroup && createdAtStr != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Created on $createdAtStr${ownerName != null ? " by $ownerName" : ""}',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Group Participants List (If Group)
                if (isGroup && participants.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${participants.length} participants',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen),
                        ),
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: math.min(participants.length, 30),
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                          itemBuilder: (ctx, i) {
                            final p = participants[i];
                            final pName = p['name']?.toString() ?? p['phone']?.toString() ?? p['id']?.toString() ?? '';
                            final isAdmin = p['admin'] != null;

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ChatAvatar(
                                chatId: p['id']?.toString() ?? '',
                                title: pName,
                                radius: 18,
                              ),
                              title: Text(pName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: p['phone'] != null && p['phone'].toString().isNotEmpty
                                  ? Text(p['phone'].toString(), style: const TextStyle(fontSize: 12))
                                  : null,
                              trailing: isAdmin
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: WhatsAppTheme.primaryGreen.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Admin',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen),
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Settings & Notifications
                Container(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_none_rounded, color: WhatsAppTheme.primaryGreen),
                        title: const Text('Mute notifications'),
                        trailing: Switch(
                          value: false,
                          activeColor: WhatsAppTheme.primaryGreen,
                          onChanged: (v) {},
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.lock_rounded, color: WhatsAppTheme.primaryGreen),
                        title: const Text('Encryption'),
                        subtitle: const Text('Messages and calls are end-to-end encrypted.', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: WhatsAppTheme.primaryGreen, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: WhatsAppTheme.primaryGreen)),
          ],
        ),
      ),
    );
  }
}
