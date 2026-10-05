import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../widgets/chat_avatar.dart';

class CallScreen extends StatefulWidget {
  final ChatModel chat;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.chat,
    this.isVideo = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeaker = false;
  late bool _isVideoEnabled;
  bool _isFrontCamera = true;
  String _callStatus = 'Connecting...';
  int _callSeconds = 0;
  Timer? _callTimer;
  Timer? _statusTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideo;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _statusTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _callStatus = 'Ringing...');

      _statusTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _callStatus = 'Connected');
        _startTimer();
      });
    });
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _statusTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _launchNativeWhatsAppCall() async {
    final rawNumber = widget.chat.chatId.split('@').first.replaceAll(RegExp(r'[^\d]'), '');
    if (rawNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid phone number for this contact')),
      );
      return;
    }

    final List<Uri> callUris = [
      Uri.parse('whatsapp://call?phone=$rawNumber${widget.isVideo ? "&video=true" : ""}'),
      Uri.parse('https://api.whatsapp.com/send?phone=$rawNumber'),
      Uri.parse('https://wa.me/$rawNumber'),
      Uri.parse('tel:+$rawNumber'),
    ];

    bool launched = false;
    for (final uri in callUris) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
          break;
        }
      } catch (_) {}
    }

    if (!launched && mounted) {
      try {
        await launchUrl(Uri.parse('tel:+$rawNumber'), mode: LaunchMode.externalApplication);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp dialer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawNumber = widget.chat.chatId.split('@').first;
    final displayPhone = rawNumber.isNotEmpty ? '+$rawNumber' : widget.chat.chatId;

    return Scaffold(
      backgroundColor: const Color(0xFF101D24),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded, color: WhatsAppTheme.primaryGreen, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          widget.isVideo ? 'End-to-end encrypted video' : 'End-to-end encrypted audio',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Contact Info
            Text(
              widget.chat.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              displayPhone,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Text(
              _callStatus == 'Connected' ? _formatDuration(_callSeconds) : _callStatus,
              style: TextStyle(
                color: _callStatus == 'Connected' ? WhatsAppTheme.accentGreen : Colors.white60,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            // Center: Video stream preview or Pulsing Avatar
            if (_isVideoEnabled)
              Container(
                width: 220,
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: WhatsAppTheme.primaryGreen, width: 2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ChatAvatar(
                      chatId: widget.chat.chatId,
                      title: widget.chat.displayTitle,
                      isGroup: widget.chat.isGroup,
                      radius: 54,
                    ),
                    Positioned(
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isFrontCamera ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
                              size: 14,
                              color: WhatsAppTheme.primaryGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isFrontCamera ? 'Front Camera' : 'Rear Camera',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer pulse ripple
                      Container(
                        width: 170 + (_pulseController.value * 30),
                        height: 170 + (_pulseController.value * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WhatsAppTheme.primaryGreen.withOpacity(0.12 * (1 - _pulseController.value)),
                        ),
                      ),
                      // Inner pulse
                      Container(
                        width: 145 + (_pulseController.value * 15),
                        height: 145 + (_pulseController.value * 15),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WhatsAppTheme.primaryGreen.withOpacity(0.2 * (1 - _pulseController.value)),
                        ),
                      ),
                      // Core Avatar
                      ChatAvatar(
                        chatId: widget.chat.chatId,
                        title: widget.chat.displayTitle,
                        isGroup: widget.chat.isGroup,
                        radius: 56,
                      ),
                    ],
                  );
                },
              ),

            const SizedBox(height: 24),

            // Direct WhatsApp Native Call Action Button
            ElevatedButton.icon(
              onPressed: _launchNativeWhatsAppCall,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                widget.isVideo ? 'Open in WhatsApp Video Call' : 'Open in WhatsApp Voice Call',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),

            const Spacer(),

            // Bottom Call Action Controls
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF1F2C34),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute Button
                  _buildControlBtn(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Muted' : 'Mute',
                    isActive: _isMuted,
                    onTap: () {
                      setState(() => _isMuted = !_isMuted);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isMuted ? 'Microphone muted' : 'Microphone unmuted'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),

                  // Video Toggle Button
                  _buildControlBtn(
                    icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: _isVideoEnabled ? 'Video On' : 'Video Off',
                    isActive: _isVideoEnabled,
                    onTap: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                  ),

                  // Speaker Button
                  _buildControlBtn(
                    icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: 'Speaker',
                    isActive: _isSpeaker,
                    onTap: () {
                      setState(() => _isSpeaker = !_isSpeaker);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isSpeaker ? 'Speakerphone on' : 'Speakerphone off'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),

                  // Camera flip (if video enabled)
                  if (_isVideoEnabled)
                    _buildControlBtn(
                      icon: Icons.flip_camera_ios_rounded,
                      label: 'Flip',
                      isActive: false,
                      onTap: () => setState(() => _isFrontCamera = !_isFrontCamera),
                    ),

                  // End Call Button
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.redAccent, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
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

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white12,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF101D24) : Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
