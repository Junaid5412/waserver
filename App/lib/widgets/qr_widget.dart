import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/theme.dart';

class QrWidget extends StatelessWidget {
  final String qrData;
  final VoidCallback onRefresh;
  final bool isLoading;

  const QrWidget({
    super.key,
    required this.qrData,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
              ),
            )
          else if (qrData.isNotEmpty)
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 210.0,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF111B21),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF111B21),
              ),
            )
          else
            Container(
              width: 200,
              height: 200,
              color: Colors.grey.shade100,
              child: const Center(
                child: Text(
                  'Click Generate QR to begin',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: WhatsAppTheme.primaryGreen),
            label: const Text(
              'Reload QR Code',
              style: TextStyle(
                color: WhatsAppTheme.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
