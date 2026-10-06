import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../config/theme.dart';

class VoicePlayerWidget extends StatefulWidget {
  final String? audioUrl;
  final Map<String, String>? headers;
  final String? localPath;
  final String? messageId;
  final String? mimetype;
  final int durationSeconds;
  final bool fromMe;

  const VoicePlayerWidget({
    super.key,
    this.audioUrl,
    this.headers,
    this.localPath,
    this.messageId,
    this.mimetype,
    this.durationSeconds = 0,
    this.fromMe = false,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  static AudioPlayer? _activePlayer;
  static _VoicePlayerWidgetState? _activeState;

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _isInit = false;
  String? _resolvedPath;
  String? _errorMessage;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;

  late final List<double> _waveformHeights;

  @override
  void initState() {
    super.initState();
    _waveformHeights = _generateWaveformHeights(28);
    if (widget.durationSeconds > 0) {
      _duration = Duration(seconds: widget.durationSeconds);
    }
  }

  @override
  void dispose() {
    if (_activePlayer == _player) {
      _activePlayer = null;
      _activeState = null;
    }
    _cancelSubscriptions();
    _player?.dispose();
    _player = null;
    super.dispose();
  }

  void _cancelSubscriptions() {
    _playerStateSub?.cancel();
    _playerStateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
  }

  List<double> _generateWaveformHeights(int count) {
    final seed = (widget.messageId ?? widget.audioUrl ?? 'voice_seed').hashCode.abs();
    return List.generate(count, (i) {
      final v = (((seed + i * 17) * 31) % 100) / 100.0;
      return 6.0 + (v * 18.0);
    });
  }

  Future<bool> _initPlayer() async {
    if (_isInit && _player != null) return true;
    if (_isLoading) return false;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final player = AudioPlayer();
      _player = player;

      _playerStateSub = player.playerStateStream.listen((state) {
        if (!mounted) return;
        final isPlaying = state.playing && state.processingState != ProcessingState.completed;
        setState(() {
          _isPlaying = isPlaying;
          if (state.processingState == ProcessingState.completed) {
            _position = _duration;
            _isPlaying = false;
          }
        });
      });

      _positionSub = player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() {
          _position = pos;
        });
      });

      _durationSub = player.durationStream.listen((dur) {
        if (!mounted || dur == null) return;
        setState(() {
          if (dur > Duration.zero) {
            _duration = dur;
          }
        });
      });

      // 1. Check if direct localPath is provided and exists
      String? targetPath = widget.localPath;
      if (targetPath != null && File(targetPath).existsSync() && (await File(targetPath).length()) > 0) {
        _resolvedPath = targetPath;
        await player.setFilePath(targetPath);
      } else {
        // 2. Check local temporary cache file
        final dir = await getTemporaryDirectory();
        final safeKey = (widget.messageId?.isNotEmpty == true
                ? widget.messageId!
                : (widget.audioUrl?.hashCode.toString() ?? 'temp'))
            .replaceAll(RegExp(r'[^\w]'), '_');

        final ext = (widget.mimetype?.contains('mp4') == true || widget.mimetype?.contains('m4a') == true)
            ? 'm4a'
            : 'ogg';
        final cachedFile = File('${dir.path}/voice_$safeKey.$ext');

        if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
          _resolvedPath = cachedFile.path;
          await player.setFilePath(cachedFile.path);
        } else if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty) {
          // 3. Download from server with headers
          final uri = Uri.parse(widget.audioUrl!);
          final res = await http.get(uri, headers: widget.headers ?? {}).timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            await cachedFile.writeAsBytes(res.bodyBytes);
            _resolvedPath = cachedFile.path;
            await player.setFilePath(cachedFile.path);
          } else {
            throw Exception('Server returned HTTP ${res.statusCode}');
          }
        } else {
          throw Exception('No audio source URL available');
        }
      }

      await player.setSpeed(_speed);
      _isInit = true;
      return true;
    } catch (e) {
      _cancelSubscriptions();
      _player?.dispose();
      _player = null;
      _isInit = false;
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot play voice message: $_errorMessage'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _playPause() async {
    if (!_isInit || _player == null) {
      final ok = await _initPlayer();
      if (!ok || _player == null) return;
    }

    try {
      if (_isPlaying) {
        await _player!.pause();
      } else {
        // Pause any other active player instance
        if (_activePlayer != null && _activePlayer != _player) {
          try {
            await _activePlayer!.pause();
          } catch (_) {}
        }
        _activePlayer = _player;
        _activeState = this;

        // If completed or at end, seek back to start
        if (_player!.processingState == ProcessingState.completed ||
            (_duration > Duration.zero && _position >= _duration)) {
          await _player!.seek(Duration.zero);
        }

        await _player!.play();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _seekToRatio(double ratio) async {
    if (!_isInit || _player == null) {
      final ok = await _initPlayer();
      if (!ok || _player == null) return;
    }

    final total = _duration > Duration.zero
        ? _duration
        : Duration(seconds: widget.durationSeconds > 0 ? widget.durationSeconds : 15);
    final targetMs = (total.inMilliseconds * ratio).clamp(0, total.inMilliseconds).toInt();
    final target = Duration(milliseconds: targetMs);
    try {
      await _player!.seek(target);
      setState(() {
        _position = target;
      });
    } catch (_) {}
  }

  Future<void> _cycleSpeed() async {
    double nextSpeed = 1.0;
    if (_speed == 1.0) {
      nextSpeed = 1.5;
    } else if (_speed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() {
      _speed = nextSpeed;
    });

    if (_player != null) {
      try {
        await _player!.setSpeed(nextSpeed);
      } catch (_) {}
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDuration = _duration > Duration.zero
        ? _duration
        : Duration(seconds: widget.durationSeconds > 0 ? widget.durationSeconds : 0);

    final double progress = totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final String displayTime = (_isPlaying || _position > Duration.zero)
        ? _formatDuration(_position)
        : (totalDuration.inSeconds > 0 ? _formatDuration(totalDuration) : '0:00');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause Circle Button
          GestureDetector(
            onTap: _playPause,
            child: CircleAvatar(
              radius: 19,
              backgroundColor: WhatsAppTheme.primaryGreen,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 8),

          // Waveform bars with interactive seeking
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (width > 0) {
                          final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
                          _seekToRatio(ratio);
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        if (width > 0) {
                          final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
                          _seekToRatio(ratio);
                        }
                      },
                      child: SizedBox(
                        height: 28,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(_waveformHeights.length, (index) {
                            final barHeight = _waveformHeights[index];
                            final barRatio = index / _waveformHeights.length;
                            final isPlayed = barRatio <= progress;

                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isPlayed
                                      ? WhatsAppTheme.primaryGreen
                                      : (isDark ? Colors.white30 : Colors.black26),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayTime,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    if (_isInit || _isPlaying || _speed != 1.0)
                      GestureDetector(
                        onTap: _cycleSpeed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: WhatsAppTheme.primaryGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_speed == 1.0 ? '1' : _speed.toString()}x',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: WhatsAppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Mic indicator icon
          CircleAvatar(
            radius: 13,
            backgroundColor: Colors.transparent,
            child: Icon(
              Icons.mic_rounded,
              size: 20,
              color: _position > Duration.zero
                  ? Colors.blue.shade400
                  : WhatsAppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}
