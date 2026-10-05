import 'dart:async';
import 'package:flutter/material.dart';
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
  String _callStatus = 'Calling...';
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

    // Transition from Calling -> Ringing -> Connected
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _callStatus = 'Ringing...');

      _statusTimer = Timer(const Duration(seconds: 3), () {
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
                  const SizedBox(width: 48), // balance back button
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
            const SizedBox(height: 6),
            Text(
              displayPhone,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _callSeconds > 0 ? WhatsAppTheme.primaryGreen.withOpacity(0.2) : Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _callSeconds > 0 ? _formatDuration(_callSeconds) : _callStatus,
                style: TextStyle(
                  color: _callSeconds > 0 ? WhatsAppTheme.accentGreen : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const Spacer(),

            // Avatar with pulsing ripple rings
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 170 + (_pulseController.value * 30),
                        height: 170 + (_pulseController.value * 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: WhatsAppTheme.primaryGreen.withOpacity(0.15 * (1.0 - _pulseController.value)),
                        ),
                      );
                    },
                  ),
                  ChatAvatar(
                    chatId: widget.chat.chatId,
                    title: widget.chat.displayTitle,
                    isGroup: widget.chat.isGroup,
                    isCommunity: widget.chat.isCommunity,
                    isChannel: widget.chat.isChannel,
                    radius: 70,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Bottom Call Action Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF1F2C34),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Speaker Toggle
                      _callBtn(
                        icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Speaker',
                        isActive: _isSpeaker,
                        onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                      ),

                      // Video Toggle
                      _callBtn(
                        icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        label: 'Video',
                        isActive: _isVideoEnabled,
                        onTap: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                      ),

                      // Mute Toggle
                      _callBtn(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: 'Mute',
                        isActive: _isMuted,
                        onTap: () => setState(() => _isMuted = !_isMuted),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // End Call Button
                  FloatingActionButton(
                    heroTag: 'end_call',
                    backgroundColor: const Color(0xFFE53935),
                    elevation: 6,
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Call ended')),
                      );
                    },
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callBtn({
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
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white12,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF101D24) : Colors.white,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
