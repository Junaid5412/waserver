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
    bool isGroup = false,
    required Function(String emoji) onReact,
    required VoidCallback onReply,
    required VoidCallback onStar,
    required Function(String scope) onDelete,
    required Function(MessageModel message) onEdit,
    required Function(MessageModel message) onForward,
    VoidCallback? onDownload,
    VoidCallback? onViewPdf,
    VoidCallback? onReplyPrivately,
    VoidCallback? onMessageSender,
    VoidCallback? onMarkSeen,
    VoidCallback? onOpenDiff,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.fromMe;
    final isAdmin = currentUser?.isAdmin == true;
    final canViewDeleted = UserPermissions.canViewDeleted(currentUser);
    final canViewEdits = UserPermissions.canViewEdits(currentUser);
    final canViewReceipts = UserPermissions.canViewReceipts(currentUser);

    // Can Edit: sender (or admin), not deleted, not audio/poll/sticker, within 15 minutes
    final ageMinutes = message.createdAt != null
        ? DateTime.now().difference(message.createdAt!).inMinutes
        : 999;
    final canEdit = (isMe || isAdmin) &&
        !message.deleted &&
        !['audio', 'sticker', 'poll', 'location', 'contact'].contains(message.type) &&
        (isAdmin || ageMinutes < 15);

    final isPdfDoc = message.hasMedia &&
        (message.type == 'document' || message.mimetype?.contains('pdf') == true);

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
            child: SingleChildScrollView(
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

                  // Quick emoji reaction bar (with un-react toggle)
                  if (!message.deleted) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((emoji) {
                          final isCurrentReact = message.reactions['me'] == emoji;
                          return InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              // If tapped same emoji, un-react by sending empty string
                              onReact(isCurrentReact ? '' : emoji);
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrentReact
                                    ? WhatsAppTheme.primaryGreen.withOpacity(0.2)
                                    : Colors.transparent,
                              ),
                              child: Text(emoji, style: const TextStyle(fontSize: 26)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ],

                  // 1. Reply
                  if (!message.deleted)
                    ListTile(
                      leading: const Icon(Icons.reply_rounded, color: WhatsAppTheme.primaryGreen),
                      title: const Text('Reply'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onReply();
                      },
                    ),

                  // 2. Edit message (sender or admin within 15 min)
                  if (canEdit)
                    ListTile(
                      leading: const Icon(Icons.edit_rounded, color: WhatsAppTheme.accentGreen),
                      title: const Text('Edit Message'),
                      subtitle: Text(
                        isAdmin && !isMe ? 'Admin permission' : 'Available within 15 minutes',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onEdit(message);
                      },
                    ),

                  // 3. Copy text
                  if (!message.deleted && message.text.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.copy_rounded, color: WhatsAppTheme.primaryGreen),
                      title: const Text('Copy Text'),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message copied to clipboard')),
                        );
                      },
                    )
                  else if (message.deleted && canViewDeleted && message.text.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.copy_rounded, color: WhatsAppTheme.deletedRed),
                      title: const Text('Copy Preserved Text (Admin)'),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Preserved text copied to clipboard')),
                        );
                      },
                    ),

                  // 4. Forward
                  if (!message.deleted)
                    ListTile(
                      leading: const Icon(Icons.forward_rounded, color: WhatsAppTheme.primaryGreen),
                      title: const Text('Forward'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onForward(message);
                      },
                    ),

                  // 5. Star / Unstar
                  if (!message.deleted)
                    ListTile(
                      leading: Icon(
                        message.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: message.starred ? Colors.amber : WhatsAppTheme.primaryGreen,
                      ),
                      title: Text(message.starred ? 'Unstar Message' : 'Star Message'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onStar();
                      },
                    ),

                  // 6. Download media
                  if (message.hasMedia && (!message.deleted || canViewDeleted))
                    ListTile(
                      leading: const Icon(Icons.file_download_rounded, color: WhatsAppTheme.primaryGreen),
                      title: Text(message.deleted ? 'Download Preserved Media' : 'Download Media'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onDownload?.call();
                      },
                    ),

                  // 7. View PDF / Document
                  if (isPdfDoc && (!message.deleted || canViewDeleted))
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                      title: const Text('View Document'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onViewPdf?.call();
                      },
                    ),

                  // 8. Group Actions: Reply Privately & Message Sender
                  if (isGroup && !isMe && !message.deleted) ...[
                    ListTile(
                      leading: const Icon(Icons.reply_all_rounded, color: WhatsAppTheme.primaryGreen),
                      title: const Text('Reply Privately'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onReplyPrivately?.call();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline_rounded, color: WhatsAppTheme.primaryGreen),
                      title: Text('Message ${message.senderName.isNotEmpty ? message.senderName : "Sender"}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        onMessageSender?.call();
                      },
                    ),
                  ],

                  // 9. Mark as seen (for incoming messages)
                  if (!isMe && !message.deleted && canViewReceipts)
                    ListTile(
                      leading: const Icon(Icons.done_all_rounded, color: WhatsAppTheme.blueTick),
                      title: const Text('Mark as Seen'),
                      subtitle: const Text('Send read receipt to sender', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(ctx);
                        onMarkSeen?.call();
                      },
                    ),

                  // 10. Message Info & Revisions
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded, color: WhatsAppTheme.primaryGreen),
                    title: const Text('Message Info'),
                    subtitle: message.edited && canViewEdits
                        ? const Text('Includes revision history', style: TextStyle(fontSize: 11, color: WhatsAppTheme.editedChip))
                        : null,
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

                  // 11. Delete Message
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: WhatsAppTheme.deletedRed),
                    title: const Text(
                      'Delete Message',
                      style: TextStyle(color: WhatsAppTheme.deletedRed, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteConfirmDialog(
                        context: context,
                        isMe: isMe || isAdmin,
                        onDelete: onDelete,
                      );
                    },
                  ),
                ],
              ),
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
              Text('Message Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('Type', message.type.toUpperCase()),
                _infoRow('Direction', message.fromMe ? 'Outgoing' : 'Incoming'),
                if (message.senderName.isNotEmpty && !message.fromMe)
                  _infoRow('From', message.senderName),
                _infoRow('Time', sentStr),
                _infoRow('Status', message.status.toUpperCase()),
                _infoRow('Message ID', message.waId),
                if (message.quotedText.isNotEmpty)
                  _infoRow('Quoted', message.quotedText),

                const Divider(height: 20),

                // Edited Status & Revisions
                if (message.edited) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Edited:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      Text(
                        canViewEdits
                            ? 'Yes (${message.edits.length} revisions)'
                            : 'Yes',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: WhatsAppTheme.editedChip, fontSize: 13),
                      ),
                    ],
                  ),
                  if (canViewEdits) ...[
                    if (message.originalText?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text('Original text: ${message.originalText}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                    if (onOpenDiff != null) ...[
                      const SizedBox(height: 8),
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
                  ],
                  const SizedBox(height: 12),
                ],

                // Deleted Status & Preserved Content
                if (message.deleted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Deleted by sender:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      const Text(
                        'Yes',
                        style: TextStyle(fontWeight: FontWeight.w600, color: WhatsAppTheme.deletedRed, fontSize: 13),
                      ),
                    ],
                  ),
                  if (canViewDeleted) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: WhatsAppTheme.deletedRed.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: WhatsAppTheme.deletedRed.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🛡️ Admin Preserved Content:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: WhatsAppTheme.deletedRed),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            message.text.isNotEmpty ? message.text : '[Preserved media attachment]',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
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
        content: Text(
          isMe
              ? 'You can delete this message for everyone, or only remove it from this client.'
              : 'This removes the message from this client.',
        ),
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
