import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/permissions.dart';
import '../models/message.dart';
import '../models/user.dart';

class MessageActionsSheet {
  static void show({
    required BuildContext context,
    required MessageModel message,
    required UserModel? currentUser,
    required Function(String emoji) onReact,
    required VoidCallback onReply,
    required VoidCallback onStar,
    required Function(String scope) onDelete,
    VoidCallback? onOpenDiff,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.fromMe;
    final canViewDeleted = UserPermissions.canViewDeleted(currentUser);
    final canViewEdits = UserPermissions.canViewEdits(currentUser);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Quick emoji reaction bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          onReact(emoji);
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),

                // Reply
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReply();
                  },
                ),

                // Copy Text
                if (message.text.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: WhatsAppTheme.primaryGreen),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),

                // Star
                ListTile(
                  leading: const Icon(Icons.star_outline_rounded, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Star Message'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onStar();
                  },
                ),

                // Message Info / Details
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Message Info & Revisions'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMessageDetailsDialog(
                      context: context,
                      message: message,
                      canViewDeleted: canViewDeleted,
                      canViewEdits: canViewEdits,
                      onOpenDiff: onOpenDiff,
                    );
                  },
                ),

                // Delete
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: WhatsAppTheme.deletedRed),
                  title: const Text(
                    'Delete Message',
                    style: TextStyle(color: WhatsAppTheme.deletedRed),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDeleteConfirmDialog(context: context, isMe: isMe, onDelete: onDelete);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showMessageDetailsDialog({
    required BuildContext context,
    required MessageModel message,
    required bool canViewDeleted,
    required bool canViewEdits,
    VoidCallback? onOpenDiff,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sentStr = message.createdAt != null
        ? DateFormat('EEEE, dd MMM yyyy, HH:mm:ss').format(message.createdAt!.toLocal())
        : 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
          title: Row(
            children: const [
              Icon(Icons.info_rounded, color: WhatsAppTheme.primaryGreen),
              SizedBox(width: 8),
              Text('Message Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('Type', message.type.toUpperCase()),
                _infoRow('Status', message.status.toUpperCase()),
                _infoRow('Direction', message.fromMe ? 'Outgoing' : 'Incoming'),
                _infoRow('Sent At', sentStr),
                _infoRow('Message ID', message.waId),
                if (message.quotedText.isNotEmpty)
                  _infoRow('Quoted', message.quotedText),

                const Divider(height: 20),

                // Edited information
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Edited Status:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    Text(
                      message.edited ? 'Edited (${message.edits.length} revisions)' : 'Original',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: message.edited ? WhatsAppTheme.editedChip : Colors.green,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (message.edited && canViewEdits && onOpenDiff != null) ...[
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onOpenDiff();
                    },
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('View Full Edit History & Diff'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.editedChip,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 36),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Deleted information
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Deleted Status:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    Text(
                      message.deleted ? 'Deleted by sender' : 'Active',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: message.deleted ? WhatsAppTheme.deletedRed : Colors.green,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (message.deleted && canViewDeleted) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: WhatsAppTheme.deletedRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: WhatsAppTheme.deletedRed.withOpacity(0.2)),
                    ),
                    child: Text(
                      'Admin Preserved Content:\n${message.text.isNotEmpty ? message.text : 'Original text preserved in audit log'}',
                      style: const TextStyle(fontSize: 12.5, color: WhatsAppTheme.deletedRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  static void _showDeleteConfirmDialog({
    required BuildContext context,
    required bool isMe,
    required Function(String scope) onDelete,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Choose whether to delete this message for everyone or only for yourself.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete('me');
            },
            child: const Text('Delete for me'),
          ),
          if (isMe)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onDelete('everyone');
              },
              style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.deletedRed),
              child: const Text('Delete for everyone', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
