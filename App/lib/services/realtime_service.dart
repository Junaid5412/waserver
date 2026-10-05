import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';

class RealtimeEvent {
  final String type;
  final String? chatId;
  final String? waId;
  final bool? fromMe;
  final Map<String, dynamic> raw;

  RealtimeEvent({
    required this.type,
    this.chatId,
    this.waId,
    this.fromMe,
    required this.raw,
  });

  static String normalizeJid(String? jid) {
    if (jid == null || jid.isEmpty) return '';
    String clean = jid.trim();
    // Strip device suffix e.g. 12345:1@s.whatsapp.net -> 12345@s.whatsapp.net
    if (clean.contains(':') && clean.contains('@')) {
      final parts = clean.split('@');
      final userPart = parts[0].split(':')[0];
      clean = '$userPart@${parts[1]}';
    }
    return clean.toLowerCase();
  }

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final eventType = json['type']?.toString() ?? 'unknown';
    String? chat = json['chatId']?.toString();
    String? msgWaId = json['waId']?.toString();
    bool? isFromMe = json['fromMe'] is bool ? json['fromMe'] : null;

    if (chat == null && json['id'] != null && json['id'].toString().contains('@')) {
      chat = json['id'].toString();
    }
    if (json['data'] is Map) {
      final d = json['data'] as Map;
      if (chat == null && d['chatId'] != null) chat = d['chatId'].toString();
      if (chat == null && d['id'] != null && d['id'].toString().contains('@')) chat = d['id'].toString();
      if (d['key'] is Map) {
        chat ??= d['key']['remoteJid']?.toString();
        msgWaId ??= d['key']['id']?.toString();
        isFromMe ??= (d['key']['fromMe'] == true);
      }
      if (chat == null && d['updates'] is List && (d['updates'] as List).isNotEmpty) {
        final firstUpdate = (d['updates'] as List)[0];
        if (firstUpdate is Map && firstUpdate['key'] is Map) {
          chat = firstUpdate['key']['remoteJid']?.toString();
          msgWaId ??= firstUpdate['key']['id']?.toString();
        }
      }
    }

    return RealtimeEvent(
      type: eventType,
      chatId: chat != null ? normalizeJid(chat) : null,
      waId: msgWaId,
      fromMe: isFromMe,
      raw: json,
    );
  }
}

class RealtimeService {
  final ApiService api;
  final StreamController<RealtimeEvent> _controller = StreamController<RealtimeEvent>.broadcast();

  String? _currentInstanceId;
  http.Client? _streamClient;
  bool _isDisposed = false;
  Timer? _reconnectTimer;
  Timer? _fallbackPollTimer;
  bool _isConnected = false;

  Stream<RealtimeEvent> get events => _controller.stream;
  bool get isConnected => _isConnected;

  RealtimeService({required this.api});

  void ensureConnected(String instanceId) {
    if (_currentInstanceId != instanceId || !_isConnected || _streamClient == null) {
      connect(instanceId);
    }
  }

  void connect(String instanceId) {
    if (_currentInstanceId == instanceId && _streamClient != null && _isConnected) return;
    disconnect();
    _currentInstanceId = instanceId;
    _startStream(instanceId);
    _startFallbackPoll(instanceId);
  }

  void disconnect() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _fallbackPollTimer?.cancel();
    _streamClient?.close();
    _streamClient = null;
    _currentInstanceId = null;
  }

  Future<void> _startStream(String instanceId) async {
    if (_isDisposed) return;
    _streamClient?.close();
    final client = http.Client();
    _streamClient = client;

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/instances/$instanceId/stream');
      final request = http.Request('GET', uri);
      request.headers.addAll(api.authHeaders);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await client.send(request);

      if (response.statusCode == 200) {
        _isConnected = true;
        // Fire an immediate sync event on connection
        _controller.add(RealtimeEvent(
          type: 'ready',
          raw: {'instanceId': instanceId, 'status': 'connected'},
        ));

        String buffer = '';
        response.stream.transform(utf8.decoder).listen(
          (chunk) {
            buffer += chunk;
            final lines = buffer.split('\n');
            buffer = lines.removeLast();

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.startsWith('data:')) {
                final jsonStr = trimmed.substring(5).trim();
                if (jsonStr.isNotEmpty) {
                  try {
                    final data = jsonDecode(jsonStr);
                    if (data is Map<String, dynamic>) {
                      _controller.add(RealtimeEvent.fromJson(data));
                    }
                  } catch (_) {}
                }
              }
            }
          },
          onError: (_) => _handleStreamDisconnect(instanceId),
          onDone: () => _handleStreamDisconnect(instanceId),
          cancelOnError: true,
        );
      } else {
        _handleStreamDisconnect(instanceId);
      }
    } catch (_) {
      _handleStreamDisconnect(instanceId);
    }
  }

  void _handleStreamDisconnect(String instanceId) {
    _isConnected = false;
    _scheduleReconnect(instanceId);
  }

  void _scheduleReconnect(String instanceId) {
    if (_isDisposed || _currentInstanceId != instanceId) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!_isDisposed && _currentInstanceId == instanceId) {
        _startStream(instanceId);
      }
    });
  }

  void _startFallbackPoll(String instanceId) {
    _fallbackPollTimer?.cancel();
    // Pulse every 3 seconds to keep UI responsive under all network conditions
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isDisposed || _currentInstanceId != instanceId) return;
      _controller.add(RealtimeEvent(
        type: 'poll_tick',
        raw: {'instanceId': instanceId},
      ));
    });
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _controller.close();
  }
}
