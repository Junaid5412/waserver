import 'package:flutter/material.dart';
import '../config/theme.dart';

class VoicePlayerWidget extends StatefulWidget {
  final String? audioUrl;
  final int durationSeconds;

  const VoicePlayerWidget({
    super.key,
    this.audioUrl,
    this.durationSeconds = 12,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  bool _isPlaying = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause Circle Button
          GestureDetector(
            onTap: () {
              setState(() {
                _isPlaying = !_isPlaying;
                if (_isPlaying && _progress >= 1.0) _progress = 0.0;
              });
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: WhatsAppTheme.primaryGreen,
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Waveform bars simulation
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: List.generate(24, (index) {
                    final height = 6.0 + ((index * 7 + 3) % 18);
                    final isPlayed = (index / 24.0) <= _progress;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: height,
                        decoration: BoxDecoration(
                          color: isPlayed
                              ? WhatsAppTheme.primaryGreen
                              : (isDark ? Colors.white38 : Colors.black26),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  '0:${widget.durationSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Mic icon
          const CircleAvatar(
            radius: 14,
            backgroundColor: Colors.transparent,
            child: Icon(Icons.mic, size: 20, color: WhatsAppTheme.primaryGreen),
          ),
        ],
      ),
    );
  }
}
