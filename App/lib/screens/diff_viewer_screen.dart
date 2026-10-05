import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/message.dart';

class DiffViewerModal extends StatelessWidget {
  final MessageModel message;

  const DiffViewerModal({super.key, required this.message});

  static void show(BuildContext context, MessageModel message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiffViewerModal(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? WhatsAppTheme.surfaceDark : Colors.white;

    final origText = message.originalText ?? (message.edits.isNotEmpty ? message.edits.first.text : 'Original text');
    final origTime = message.createdAt != null ? DateFormat('HH:mm, dd MMM').format(message.createdAt!.toLocal()) : '';
    final editTime = message.editedAt != null ? DateFormat('HH:mm, dd MMM').format(message.editedAt!.toLocal()) : '';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              const Icon(Icons.history_rounded, color: WhatsAppTheme.primaryGreen, size: 24),
              const SizedBox(width: 10),
              Text(
                'Edit History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF111B21),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),

          // "Old was this" Card
          Text(
            'ORIGINAL MESSAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.red.shade400,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  origText,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (origTime.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Sent at $origTime',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // "Was This" / Current Edited Message Card
          Text(
            'CURRENT EDITED MESSAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: WhatsAppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WhatsAppTheme.primaryGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WhatsAppTheme.primaryGreen.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (editTime.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Edited at $editTime',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ],
            ),
          ),

          // Intermediate edits if any
          if (message.edits.length > 1) ...[
            const SizedBox(height: 16),
            Text(
              'ALL REVISIONS (${message.edits.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            ...message.edits.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final e = entry.value;
              final t = e.at != null ? DateFormat('HH:mm, dd MMM').format(e.at!.toLocal()) : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '#$idx: "${e.text}" ${t.isNotEmpty ? '($t)' : ''}',
                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : Colors.black87),
                ),
              );
            }),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
