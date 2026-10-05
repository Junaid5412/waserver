import 'package:flutter/material.dart';
import '../config/theme.dart';

class StatusIndicator extends StatelessWidget {
  final String status;
  final double size;

  const StatusIndicator({
    super.key,
    required this.status,
    this.size = 15,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'read':
      case 'played':
        return Icon(Icons.done_all, size: size, color: WhatsAppTheme.blueTick);
      case 'delivered':
        return Icon(Icons.done_all, size: size, color: WhatsAppTheme.grayTick);
      case 'sent':
        return Icon(Icons.done, size: size, color: WhatsAppTheme.grayTick);
      case 'pending':
        return Icon(Icons.access_time, size: size - 2, color: WhatsAppTheme.grayTick);
      case 'failed':
        return Icon(Icons.error_outline, size: size, color: Colors.red);
      default:
        return const SizedBox.shrink();
    }
  }
}
