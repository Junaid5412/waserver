import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../services/auth_service.dart';
import '../widgets/chat_avatar.dart';

class ContactProfileScreen extends StatelessWidget {
  final ChatModel chat;

  const ContactProfileScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    final isGroup = chat.isGroup;
    final rawNumber = chat.chatId.split('@').first;
    final formattedPhone = rawNumber.isNotEmpty ? '+$rawNumber' : chat.chatId;

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
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
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
                  if (instanceId != null && !isGroup)
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
                        isGroup ? 'Group ID: ${chat.chatId}' : formattedPhone,
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
                            () => _showCallDialog(context, 'Audio Call', formattedPhone),
                          ),
                          _actionBtn(
                            context,
                            Icons.videocam_rounded,
                            'Video',
                            () => _showCallDialog(context, 'Video Call', formattedPhone),
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

                // About & Status
                Container(
                  width: double.infinity,
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGroup ? 'Group Description' : 'About & Phone',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: WhatsAppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isGroup
                            ? 'Welcome to ${chat.displayTitle}! Group notifications and media synced via Zelon Messenger.'
                            : 'Hey there! I am using Zelon Messenger.',
                        style: const TextStyle(fontSize: 15),
                      ),
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
                  ),
                ),

                const SizedBox(height: 10),

                // Media, Links, and Docs Tile
                Container(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.perm_media_rounded, color: WhatsAppTheme.primaryGreen),
                    title: const Text('Media, links, and docs'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('14', style: TextStyle(color: Colors.grey, fontSize: 14)),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Media gallery view')),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

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
                        leading: const Icon(Icons.music_note_rounded, color: WhatsAppTheme.primaryGreen),
                        title: const Text('Custom notifications'),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.lock_rounded, color: WhatsAppTheme.primaryGreen),
                        title: const Text('Encryption'),
                        subtitle: const Text('Messages and calls are end-to-end encrypted.'),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Block & Report (Danger Zone)
                Container(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.block_rounded, color: WhatsAppTheme.deletedRed),
                        title: Text(
                          isGroup ? 'Exit Group' : 'Block Contact',
                          style: const TextStyle(color: WhatsAppTheme.deletedRed, fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _showBlockDialog(context, isGroup ? 'Exit Group' : 'Block Contact'),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.thumb_down_alt_rounded, color: WhatsAppTheme.deletedRed),
                        title: Text(
                          isGroup ? 'Report Group' : 'Report Contact',
                          style: const TextStyle(color: WhatsAppTheme.deletedRed, fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _showBlockDialog(context, isGroup ? 'Report Group' : 'Report Contact'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
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

  void _showCallDialog(BuildContext context, String type, String destination) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type),
        content: Text('Initiating $type with $destination via WhatsApp API gateway...'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$type connected')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            child: const Text('Connect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context, String action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action?'),
        content: Text('Are you sure you want to $action?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$action confirmed')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.deletedRed),
            child: Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
