import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../config/theme.dart';
import '../config/permissions.dart';
import 'status_indicator.dart';

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  final UserModel? currentUser;
  final VoidCallback? onOpenDiff;
  final Function(String emoji)? onReact;

  const ChatBubble({
    super.key,
    required this.message,
    this.currentUser,
    this.onOpenDiff,
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.fromMe;

    final bubbleBg = isMe
        ? (isDark ? WhatsAppTheme.bubbleOutDark : WhatsAppTheme.bubbleOutLight)
        : (isDark ? WhatsAppTheme.bubbleInDark : WhatsAppTheme.bubbleInLight);

    final textColor = isDark ? Colors.white : Colors.black87;
    final timeStr = message.createdAt != null
        ? DateFormat('HH:mm').format(message.createdAt!.toLocal())
        : '';

    final canViewDeleted = UserPermissions.canViewDeleted(currentUser);
    final canViewEdits = UserPermissions.canViewEdits(currentUser);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Group / counterparty name if incoming
              if (!isMe && message.name.isNotEmpty) ...[
                Text(
                  message.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: WhatsAppTheme.primaryGreen,
                  ),
                ),
                const SizedBox(height: 2),
              ],

              // Quoted reply banner
              if (message.quotedText.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(
                      left: BorderSide(color: WhatsAppTheme.primaryGreen, width: 3.5),
                    ),
                  ),
                  child: Text(
                    message.quotedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],

              // Deleted Message Handling
              if (message.deleted) ...[
                if (canViewDeleted) ...[
                  // Super Admin / Allowed user: Show deleted warning badge + recovered text!
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: WhatsAppTheme.deletedRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.block, size: 13, color: WhatsAppTheme.deletedRed),
                        SizedBox(width: 4),
                        Text(
                          'Deleted by sender (Recovered)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WhatsAppTheme.deletedRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    message.text.isNotEmpty ? message.text : 'Original text preserved',
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                ] else ...[
                  // Normal User: Standard WhatsApp "This message was deleted"
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 14, color: isDark ? Colors.white60 : Colors.black45),
                      const SizedBox(width: 6),
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                // Normal Active Message Content
                Text(
                  message.text,
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ],

              const SizedBox(height: 3),

              // Bottom row: Edited chip + Timestamp + Delivery ticks
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Spacer(),
                  // Edited chip (Only shown if permitted)
                  if (message.edited && canViewEdits) ...[
                    InkWell(
                      onTap: onOpenDiff,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: WhatsAppTheme.editedChip.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.edit, size: 11, color: WhatsAppTheme.editedChip),
                            SizedBox(width: 3),
                            Text(
                              'Edited · View history',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: WhatsAppTheme.editedChip,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (message.edited) ...[
                    // Subtle edited text indicator for regular users
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        'Edited',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ],

                  // Time
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),

                  // Ticks for outgoing
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    StatusIndicator(status: message.status),
                  ],
                ],
              ),

              // Reactions
              if (message.reactions.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: message.reactions.values.toSet().map((emoji) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black38 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 2),
                          ],
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
