import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

class ChatAvatar extends StatelessWidget {
  final String? instanceId;
  final String chatId;
  final String title;
  final bool isGroup;
  final double radius;

  const ChatAvatar({
    super.key,
    this.instanceId,
    required this.chatId,
    required this.title,
    this.isGroup = false,
    this.radius = 24,
  });

  Color _getDeterministicColor(String text) {
    final colors = [
      const Color(0xFF1EBEA5),
      const Color(0xFF00A884),
      const Color(0xFF34B7F1),
      const Color(0xFFE542A3),
      const Color(0xFF9C27B0),
      const Color(0xFFFF9800),
      const Color(0xFF4CAF50),
      const Color(0xFF009688),
    ];
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  Widget _buildFallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _getDeterministicColor(chatId.isNotEmpty ? chatId : title);

    if (isGroup) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade300,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.groups_rounded,
            size: radius * 1.15,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    final trimmed = title.trim();
    final initial = trimmed.isNotEmpty
        ? (trimmed.startsWith('+') && trimmed.length > 1
            ? trimmed.substring(1, 2).toUpperCase()
            : trimmed[0].toUpperCase())
        : '?';

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: bg.withOpacity(0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.9,
            fontWeight: FontWeight.bold,
            color: bg,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final activeInstId = instanceId ?? auth.selectedInstance?.id;

    if (activeInstId == null || chatId.isEmpty || chatId == 'status@broadcast') {
      return _buildFallback(context);
    }

    final imageUrl = ApiConfig.chatPictureUrl(activeInstId, chatId);
    final headers = auth.api.authHeaders;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Frame 0 instant fallback: ALWAYS visible underneath, zero blank space
            _buildFallback(context),
            // Layer 2: Network image overlaid on top with gapless playback
            Image.network(
              imageUrl,
              headers: headers,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const SizedBox.shrink(); // keep fallback visible underneath with 0 empty space
              },
              errorBuilder: (ctx, error, stackTrace) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
