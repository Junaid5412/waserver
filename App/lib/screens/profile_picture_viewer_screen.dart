import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../widgets/chat_avatar.dart';

class ProfilePictureViewerScreen extends StatefulWidget {
  final String? instanceId;
  final String chatId;
  final String title;
  final bool isGroup;

  const ProfilePictureViewerScreen({
    super.key,
    required this.instanceId,
    required this.chatId,
    required this.title,
    this.isGroup = false,
  });

  @override
  State<ProfilePictureViewerScreen> createState() => _ProfilePictureViewerScreenState();
}

class _ProfilePictureViewerScreenState extends State<ProfilePictureViewerScreen> {
  bool _isSaving = false;

  Future<void> _downloadPhoto() async {
    if (widget.instanceId == null) return;
    setState(() => _isSaving = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final url = ApiConfig.chatPictureUrl(widget.instanceId!, widget.chatId, hd: true);
      final response = await http.get(
        Uri.parse(url),
        headers: auth.api.authHeaders,
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        Directory? targetDir;
        if (Platform.isAndroid) {
          final extDir = Directory('/storage/emulated/0/Download');
          if (await extDir.exists()) {
            targetDir = extDir;
          } else {
            targetDir = await getExternalStorageDirectory();
          }
        } else {
          targetDir = await getApplicationDocumentsDirectory();
        }

        final filename = 'zelon_profile_${widget.chatId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${targetDir!.path}/$filename');
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Photo saved to: ${targetDir.path}/$filename')),
                ],
              ),
              backgroundColor: WhatsAppTheme.primaryGreen,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw Exception('Photo not available to download');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save photo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final hasPhoto = widget.instanceId != null && widget.chatId.isNotEmpty;
    final photoUrl = hasPhoto ? ApiConfig.chatPictureUrl(widget.instanceId!, widget.chatId, hd: true) : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Profile Photo',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (hasPhoto)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    tooltip: 'Download Photo',
                    onPressed: _downloadPhoto,
                  ),
        ],
      ),
      body: Center(
        child: hasPhoto && photoUrl != null
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  photoUrl,
                  headers: auth.api.authHeaders,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                            : null,
                        color: WhatsAppTheme.primaryGreen,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => ChatAvatar(
                    chatId: widget.chatId,
                    title: widget.title,
                    isGroup: widget.isGroup,
                    radius: 90,
                  ),
                ),
              )
            : ChatAvatar(
                chatId: widget.chatId,
                title: widget.title,
                isGroup: widget.isGroup,
                radius: 90,
              ),
      ),
    );
  }
}
