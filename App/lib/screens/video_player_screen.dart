import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen player for chat and status videos fetched from the Zelon server.
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    this.title = 'Video',
  });

  static Future<void> open(BuildContext context, String url, Map<String, String> headers, {String title = 'Video'}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: url, headers: headers, title: title)),
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers,
    );
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = 'This video could not be played');
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              )
            : !_ready
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => value.isPlaying ? _controller.pause() : _controller.play(),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () => value.isPlaying ? _controller.pause() : _controller.play(),
                          ),
                          Text(
                            '${_fmt(value.position)} / ${_fmt(value.duration)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
