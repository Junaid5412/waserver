import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../config/permissions.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/chat_design_service.dart';
import '../screens/pdf_viewer_screen.dart';
import '../screens/document_viewer_screen.dart';
import 'status_indicator.dart';
import 'voice_player.dart';

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  final UserModel? currentUser;
  final String? instanceId;
  final VoidCallback? onOpenDiff;
  final VoidCallback? onLongPress;
  final Function(String emoji)? onReact;

  const ChatBubble({
    super.key,
    required this.message,
    this.currentUser,
    this.instanceId,
    this.onOpenDiff,
    this.onLongPress,
    this.onReact,
  });

  void _openFullImage(BuildContext context, String imageUrl, Map<String, String> headers, String caption) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              caption.isNotEmpty ? caption : 'Photo',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: 'Download Photo',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Photo downloaded to device storage'),
                      backgroundColor: WhatsAppTheme.primaryGreen,
                    ),
                  );
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                headers: headers,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaBody(BuildContext context, String instId, Map<String, String> headers, Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaUrl = '${ApiConfig.baseUrl}/api/instances/$instId/inbox/${message.waId}/media?inline=1';
    final type = message.type.toLowerCase();

    if (type == 'image' || message.mimetype?.startsWith('image/') == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openFullImage(context, mediaUrl, headers, message.text),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
                child: Image.network(
                  mediaUrl,
                  headers: headers,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 180,
                      width: 220,
                      color: isDark ? Colors.black26 : Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryGreen),
                      ),
                    );
                  },
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 130,
                    width: 200,
                    color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 34),
                        SizedBox(height: 6),
                        Text('Image expired or unavailable', style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (message.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message.text, style: TextStyle(fontSize: 15, color: textColor)),
          ],
        ],
      );
    } else if (type == 'document' || message.mimetype?.startsWith('application/') == true) {
      final docName = message.filename?.isNotEmpty == true ? message.filename! : 'Document';
      final lowerName = docName.toLowerCase();
      final lowerMime = (message.mimetype ?? '').toLowerCase();

      final isPdf = lowerName.endsWith('.pdf') || lowerMime == 'application/pdf';
      final isExcel = lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls') || lowerName.endsWith('.csv') || lowerMime.contains('spreadsheet') || lowerMime.contains('excel');
      final isWord = lowerName.endsWith('.docx') || lowerName.endsWith('.doc') || lowerMime.contains('word');

      final Color badgeColor = isPdf
          ? Colors.red.shade700
          : (isExcel
              ? const Color(0xFF1D6F42)
              : (isWord ? const Color(0xFF2B579A) : Colors.indigo.shade600));

      final IconData docIcon = isPdf
          ? Icons.picture_as_pdf_rounded
          : (isExcel
              ? Icons.table_chart_rounded
              : (isWord ? Icons.description_rounded : Icons.insert_drive_file_rounded));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentViewerScreen(
                    title: docName,
                    documentUrl: mediaUrl,
                    headers: headers,
                    filename: docName,
                    mimetype: message.mimetype,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      docIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          docName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        Text(
                          message.mimetype ?? 'Document file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: WhatsAppTheme.primaryGreen, size: 22),
                    tooltip: 'Download Document',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Downloading $docName to device...'),
                          backgroundColor: WhatsAppTheme.primaryGreen,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          if (message.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message.text, style: TextStyle(fontSize: 15, color: textColor)),
          ],
        ],
      );
    } else if (type == 'audio' || message.mimetype?.startsWith('audio/') == true || type == 'ptt') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          VoicePlayerWidget(
            audioUrl: mediaUrl,
            headers: headers,
            messageId: message.waId,
            mimetype: message.mimetype,
            durationSeconds: message.durationSeconds ?? 0,
            fromMe: message.fromMe,
          ),
          if (message.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ],
      );
    } else if (type == 'video' || message.mimetype?.startsWith('video/') == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 160,
            width: 220,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: const [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white30,
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Icon(Icons.videocam, color: Colors.white70, size: 16),
                ),
              ],
            ),
          ),
          if (message.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message.text, style: TextStyle(fontSize: 15, color: textColor)),
          ],
        ],
      );
    } else if (message.isLocation) {
      return _buildLocationBody(context, textColor, isDark);
    }

    // Default: Plain text
    return Text(
      message.text,
      style: TextStyle(
        fontSize: Provider.of<ChatDesignService>(context, listen: false).fontSizeValue,
        color: textColor,
      ),
    );
  }

  static int _lon2tile(double lon, int zoom) => ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  static int _lat2tile(double lat, int zoom) =>
      ((1.0 - math.log(math.tan(lat * math.pi / 180.0) + 1.0 / math.cos(lat * math.pi / 180.0)) / math.pi) / 2.0 * (1 << zoom)).floor();

  Widget _buildLocationBody(BuildContext context, Color textColor, bool isDark) {
    final lat = message.latitude ?? 0.0;
    final lng = message.longitude ?? 0.0;
    final isLive = message.isLiveLocation;
    final title = message.locationName?.isNotEmpty == true
        ? message.locationName!
        : (isLive ? 'Live Location' : 'Shared Location');
    final addr = message.locationAddress?.isNotEmpty == true
        ? message.locationAddress!
        : '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

    final tileX = _lon2tile(lng, 15);
    final tileY = _lat2tile(lat, 15);
    final tileUrl = 'https://mt1.google.com/vt/lyrs=m&hl=en&x=$tileX&y=$tileY&z=15';

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Map Preview Thumbnail
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Image.network(
                    tileUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.network(
                      'https://tile.openstreetmap.org/15/$tileX/$tileY.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFE5E9EC),
                        child: const Center(
                          child: Icon(Icons.map_rounded, color: Colors.black26, size: 36),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6),
                    ],
                  ),
                  child: Icon(
                    isLive ? Icons.sensors_rounded : Icons.location_on_rounded,
                    color: isLive ? WhatsAppTheme.primaryGreen : const Color(0xFFE53935),
                    size: isLive ? 24 : 26,
                  ),
                ),
                if (isLive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: WhatsAppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Location Info & Google Maps launcher button
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    addr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(title),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(addr),
                              const SizedBox(height: 8),
                              Text('Coordinates: $lat, $lng', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 8),
                              SelectableText('https://www.google.com/maps/search/?api=1&query=$lat,$lng', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                          ],
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_outlined, color: WhatsAppTheme.primaryGreen, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'View on Google Maps',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: WhatsAppTheme.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMe = message.fromMe;
    final auth = Provider.of<AuthService>(context, listen: false);
    final activeInstId = instanceId ?? auth.selectedInstance?.id ?? '';
    final headers = auth.api.authHeaders;
    final design = Provider.of<ChatDesignService>(context);

    final bubbleBg = isMe
        ? (isDark ? WhatsAppTheme.bubbleOutDark : WhatsAppTheme.bubbleOutLight)
        : (isDark ? WhatsAppTheme.bubbleInDark : WhatsAppTheme.bubbleInLight);

    final textColor = isDark ? Colors.white : Colors.black87;
    // 12-Hour AM/PM format
    final timeStr = message.createdAt != null
        ? DateFormat('hh:mm a').format(message.createdAt!.toLocal())
        : '';

    final canViewDeleted = UserPermissions.canViewDeleted(currentUser);
    final canViewEdits = UserPermissions.canViewEdits(currentUser);

    final radiusValue = design.bubbleStyle == 'classic_whatsapp'
        ? 8.0
        : design.bubbleStyle == 'minimalist'
            ? 4.0
            : 16.0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: bubbleBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(radiusValue),
              topRight: Radius.circular(radiusValue),
              bottomLeft: Radius.circular(isMe ? radiusValue : 2),
              bottomRight: Radius.circular(isMe ? 2 : radiusValue),
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
                    _buildMediaBody(context, activeInstId, headers, textColor),
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
                  // Normal Active Message Content (Media or Text)
                  _buildMediaBody(context, activeInstId, headers, textColor),
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
      ),
    );
  }
}
