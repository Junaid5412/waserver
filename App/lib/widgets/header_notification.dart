import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

enum HeaderNotificationType {
  message,
  success,
  error,
  info,
}

class HeaderNotification {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;
  static const MethodChannel _systemChannel = MethodChannel('com.zelon.messenger/system_notifications');

  /// Trigger a native Android status bar system notification (works in background/closed)
  static Future<void> showSystemNotification({
    required String title,
    required String body,
    String? chatId,
    bool isBroadcast = false,
  }) async {
    try {
      if (isBroadcast) {
        await _systemChannel.invokeMethod('showBroadcast', {
          'title': title,
          'body': body,
        });
      } else {
        await _systemChannel.invokeMethod('showNotification', {
          'title': title,
          'body': body,
          'chatId': chatId ?? '',
        });
      }
    } catch (_) {}
  }

  /// Show Top Header Notification / Banner on screen
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    HeaderNotificationType type = HeaderNotificationType.info,
    VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (ctx) => _HeaderNotificationWidget(
        title: title,
        message: message,
        type: type,
        onTap: () {
          dismiss();
          onTap?.call();
        },
        onDismiss: dismiss,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      dismiss();
    });
  }

  static void showMessage(
    BuildContext context, {
    required String sender,
    required String text,
    VoidCallback? onTap,
  }) {
    HapticFeedback.lightImpact();
    show(
      context,
      title: sender,
      message: text,
      type: HeaderNotificationType.message,
      onTap: onTap,
    );
  }

  static void showSuccess(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    HapticFeedback.lightImpact();
    show(
      context,
      title: title ?? 'Success',
      message: message,
      type: HeaderNotificationType.success,
    );
  }

  static void showError(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    HapticFeedback.mediumImpact();
    show(
      context,
      title: title ?? 'Error',
      message: message,
      type: HeaderNotificationType.error,
      duration: const Duration(milliseconds: 4500),
    );
  }

  static void showInfo(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    show(
      context,
      title: title,
      message: message,
      type: HeaderNotificationType.info,
    );
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_currentEntry != null) {
      _currentEntry?.remove();
      _currentEntry = null;
    }
  }
}

class _HeaderNotificationWidget extends StatefulWidget {
  final String? title;
  final String message;
  final HeaderNotificationType type;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _HeaderNotificationWidget({
    this.title,
    required this.message,
    required this.type,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_HeaderNotificationWidget> createState() => _HeaderNotificationWidgetState();
}

class _HeaderNotificationWidgetState extends State<_HeaderNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _getBackgroundColor(bool isDark) {
    switch (widget.type) {
      case HeaderNotificationType.success:
        return const Color(0xFF0F766E); // Deep Teal / Emerald
      case HeaderNotificationType.error:
        return const Color(0xFFB91C1C); // Crimson Red
      case HeaderNotificationType.message:
        return isDark ? const Color(0xFF1E293B) : const Color(0xFF0B141B);
      case HeaderNotificationType.info:
        return const Color(0xFF1D4ED8); // Royal Blue
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case HeaderNotificationType.success:
        return Icons.check_circle_rounded;
      case HeaderNotificationType.error:
        return Icons.error_rounded;
      case HeaderNotificationType.message:
        return Icons.chat_bubble_rounded;
      case HeaderNotificationType.info:
        return Icons.info_rounded;
    }
  }

  Color _getIconBadgeColor() {
    switch (widget.type) {
      case HeaderNotificationType.success:
        return Colors.greenAccent;
      case HeaderNotificationType.error:
        return Colors.redAccent;
      case HeaderNotificationType.message:
        return WhatsAppTheme.primaryGreen;
      case HeaderNotificationType.info:
        return Colors.lightBlueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = _getBackgroundColor(isDark);
    final iconColor = _getIconBadgeColor();

    return Positioned(
      top: topPadding + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < -100) {
                  widget.onDismiss();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: iconColor.withOpacity(0.2),
                      child: Icon(_getIcon(), color: iconColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.title != null && widget.title!.isNotEmpty)
                            Text(
                              widget.title!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            widget.message,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: widget.onDismiss,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(Icons.close, color: Colors.white.withOpacity(0.6), size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
