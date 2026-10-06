import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/realtime_service.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_actions_sheet.dart';
import 'diff_viewer_screen.dart';
import 'contact_profile_screen.dart';
import 'pdf_viewer_screen.dart';
import 'location_picker_screen.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/chat_design_service.dart';
import '../config/permissions.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  bool _isLoading = false;
  bool _isComposing = false;
  bool _showEmojiPicker = false;
  MessageModel? _replyingTo;
  MessageModel? _editingMessage;
  String? _livePresence;
  Timer? _presenceTimer;
  Timer? _presenceKeepaliveTimer;
  Timer? _outgoingPresenceTimer;
  bool _sentComposing = false;
  StreamSubscription<RealtimeEvent>? _streamSub;
  Timer? _foregroundPollTimer;
  Timer? _debounceTimer;

  // Voice recording
  AudioRecorder? _recorder;
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  String _recordingDuration = '0:00';

  // AI Smart Reply
  bool _isLoadingAiSuggestions = false;
  List<String> _aiSuggestions = [];
  String? _lastAutoSuggestedMsgId;
  Timer? _autoSuggestDebounceTimer;

  final List<String> _popularEmojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '😉', '😌', '😍', '🥰', '😘', '😋', '😜', '🤪', '😎',
    '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '😣',
    '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡', '🤬',
    '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓', '🤗',
    '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄', '😯',
    '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵', '🤐',
    '👍', '👎', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✌️', '🤞',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '🔥', '⭐', '✨', '🎉', '🎊', '💯', '🚀', '🎁', '🎂', '☕',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribePresenceAndRealtime();
    _startForegroundPolling();
  }

  void _startForegroundPolling() {
    _foregroundPollTimer?.cancel();
    // Fast active poll every 2.5s guarantees incoming messages never stall or require manual refresh
    _foregroundPollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) {
        _syncMessagesSilently(checkForNewOnly: true);
      }
    });
  }

  bool _isSameChat(String? incomingChatId) {
    if (incomingChatId == null || incomingChatId.isEmpty) return true;
    final a = RealtimeEvent.normalizeJid(incomingChatId);
    final b = RealtimeEvent.normalizeJid(widget.chat.chatId);
    if (a == b) return true;
    final phoneA = a.split('@')[0].replaceAll(RegExp(r'\D'), '');
    final phoneB = b.split('@')[0].replaceAll(RegExp(r'\D'), '');
    if (phoneA.isNotEmpty && phoneB.isNotEmpty && phoneA == phoneB) return true;
    return false;
  }

  void _debouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _syncMessagesSilently();
    });
  }

  void _handleOutgoingTyping(bool isTyping) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    if (isTyping) {
      if (!_sentComposing) {
        _sentComposing = true;
        auth.api.sendPresence(instanceId, widget.chat.chatId, 'composing');
      }
      _outgoingPresenceTimer?.cancel();
      _outgoingPresenceTimer = Timer(const Duration(milliseconds: 2500), () {
        if (_sentComposing) {
          _sentComposing = false;
          auth.api.sendPresence(instanceId, widget.chat.chatId, 'paused');
        }
      });
    } else if (_sentComposing) {
      _sentComposing = false;
      _outgoingPresenceTimer?.cancel();
      auth.api.sendPresence(instanceId, widget.chat.chatId, 'paused');
    }
  }

  void _subscribePresenceAndRealtime() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId != null) {
      auth.realtime.ensureConnected(instanceId);
      auth.api.subscribePresence(instanceId, widget.chat.chatId);
      _presenceKeepaliveTimer?.cancel();
      _presenceKeepaliveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) {
          auth.api.subscribePresence(instanceId, widget.chat.chatId);
        }
      });
    }

    _streamSub?.cancel();
    _streamSub = auth.realtime.events.listen((event) {
      if (_isSameChat(event.chatId) || event.type == 'message' || event.type == 'update' || event.type == 'receipt') {
        _debouncedSync();
      }

      // Handle presence updates dynamically
      if (event.type == 'presence' && _isSameChat(event.chatId)) {
        final rawData = event.raw['data'] ?? event.raw;
        if (rawData is Map && rawData['presences'] is Map) {
          final presences = rawData['presences'] as Map;
          String? status;
          for (final entry in presences.values) {
            if (entry is Map) {
              final state = entry['lastKnownPresence']?.toString();
              if (state == 'composing') {
                status = 'typing...';
                break;
              } else if (state == 'recording') {
                status = 'recording audio...';
                break;
              } else if (state == 'available') {
                status = 'online';
              }
            }
          }
          if (status != null && mounted) {
            setState(() => _livePresence = status);
            _presenceTimer?.cancel();
            _presenceTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) setState(() => _livePresence = null);
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _autoSuggestDebounceTimer?.cancel();
    _foregroundPollTimer?.cancel();
    _debounceTimer?.cancel();
    _recordingTimer?.cancel();
    _recorder?.dispose();
    _streamSub?.cancel();
    _presenceTimer?.cancel();
    _presenceKeepaliveTimer?.cancel();
    _outgoingPresenceTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    final cached = await CacheService.getCachedMessages(instanceId, widget.chat.chatId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _isLoading = false;
      });
      _scrollToBottom();
      _triggerAutoSuggestIfEligible();
    } else {
      setState(() => _isLoading = true);
    }

    _syncMessagesSilently(forceScroll: true);
  }

  void _triggerAutoSuggestIfEligible() {
    if (_messages.isEmpty) return;

    // Auto-check previous/recent messages from the contact
    final recent = _messages.reversed.take(20).toList();
    final hasContactMessages = recent.any((m) => !m.fromMe);
    if (!hasContactMessages) return;

    final triggerId = _messages.last.waId;
    if (_lastAutoSuggestedMsgId == triggerId) return;

    _autoSuggestDebounceTimer?.cancel();
    _autoSuggestDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _lastAutoSuggestedMsgId = triggerId;
      _autoReadAndSuggestReplies();
    });
  }

  Future<void> _autoReadAndSuggestReplies() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;
    if (auth.currentUser?.permissions.canUseAi == false) return;
    if (_messages.isEmpty) return;

    setState(() => _isLoadingAiSuggestions = true);

    try {
      final activeModel = await auth.api.getActiveGeminiModel();
      final suggestions = await auth.api.generateSmartReply(
        instanceId,
        widget.chat.chatId,
        _messages.reversed.take(25).toList().reversed.toList(),
        model: activeModel,
      );
      if (mounted && suggestions.isNotEmpty) {
        setState(() {
          _aiSuggestions = suggestions;
          _isLoadingAiSuggestions = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingAiSuggestions = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAiSuggestions = false);
    }
  }

  Future<void> _syncMessagesSilently({bool checkForNewOnly = false, bool forceScroll = false}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    try {
      final fresh = await auth.api.getMessages(instanceId, widget.chat.chatId, limit: 40);
      if (!mounted) return;

      if (_messages.isNotEmpty && fresh.length == _messages.length) {
        if (fresh.last.waId == _messages.last.waId &&
            fresh.last.text == _messages.last.text &&
            fresh.last.status == _messages.last.status &&
            fresh.last.edited == _messages.last.edited &&
            fresh.last.deleted == _messages.last.deleted) {
          return;
        }
      }

      final hadMessages = _messages.isNotEmpty;
      final isNearBottom = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent - _scrollController.offset < 120);

      setState(() {
        _messages = fresh;
        _isLoading = false;
      });
      await CacheService.saveMessages(instanceId, widget.chat.chatId, fresh);
      _triggerAutoSuggestIfEligible();

      if (forceScroll || !hadMessages || (isNearBottom && fresh.length > _messages.length)) {
        _scrollToBottom(smooth: hadMessages);
      }
    } catch (_) {
      if (mounted && _messages.isEmpty) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom({bool smooth = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (smooth) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  void _showAiAssistantDialog() {
    final customPromptCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Color(0xFF1A73E8), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gemini Smart Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('Intelligently analyze past chat & draft replies', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.flash_on, size: 16, color: Color(0xFF1A73E8)),
                      label: const Text('Auto Smart Replies'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generateAiReplies();
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                      label: const Text('Polite Agree'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generateAiReplies(customPrompt: 'Politely agree and confirm');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.cancel_outlined, size: 16, color: Colors.orange),
                      label: const Text('Polite Decline'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generateAiReplies(customPrompt: 'Politely decline with reason');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.schedule, size: 16, color: Colors.blue),
                      label: const Text('Get Back Later'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generateAiReplies(customPrompt: 'Say I am currently busy and will get back shortly');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Custom Instruction to Gemini',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customPromptCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Ask for discount, confirm appointment...',
                          hintStyle: const TextStyle(fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WhatsAppTheme.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: () {
                        final p = customPromptCtrl.text.trim();
                        Navigator.pop(ctx);
                        _generateAiReplies(customPrompt: p.isNotEmpty ? p : null);
                      },
                      child: const Text('Generate', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateAiReplies({String? customPrompt}) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    if (auth.currentUser?.permissions.canUseAi == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI features are disabled for your account by Admin.')),
        );
      }
      return;
    }

    if (_messages.isEmpty && (customPrompt == null || customPrompt.trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No messages in this chat yet to analyze.')),
        );
      }
      return;
    }

    setState(() {
      _isLoadingAiSuggestions = true;
      _aiSuggestions = [];
    });

    try {
      final activeModel = await auth.api.getActiveGeminiModel();
      final suggestions = await auth.api.generateSmartReply(
        instanceId,
        widget.chat.chatId,
        _messages.reversed.take(25).toList().reversed.toList(),
        prompt: customPrompt,
        model: activeModel,
      );
      if (mounted) {
        setState(() {
          _aiSuggestions = suggestions;
          _isLoadingAiSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAiSuggestions = false);
        final errText = e.toString().replaceAll('Exception: ', '').replaceAll('Gemini AI: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Smart Reply: $errText'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      _recorder = AudioRecorder();
      if (!await _recorder!.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        _recordingDuration = '0:00';
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recordingStartTime != null && mounted) {
          final elapsed = DateTime.now().difference(_recordingStartTime!);
          setState(() {
            _recordingDuration = '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      if (_recorder != null) {
        final path = await _recorder!.stop();
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        _recorder!.dispose();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
        _recordingDuration = '0:00';
        _recorder = null;
      });
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    try {
      if (_recorder == null) return;
      final path = await _recorder!.stop();
      _recorder!.dispose();
      _recorder = null;
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
        _recordingDuration = '0:00';
      });
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final auth = Provider.of<AuthService>(context, listen: false);
      final instanceId = auth.selectedInstance?.id;
      if (instanceId == null) return;

      await auth.api.sendMediaMessage(
        instanceId,
        to: widget.chat.chatId,
        type: 'audio',
        base64Data: b64,
        mimetype: 'audio/mp4',
        filename: 'voice_note.m4a',
        ptt: true,
      );
      _debouncedSync();
      await file.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice note: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    // Handle Message Editing
    if (_editingMessage != null) {
      final target = _editingMessage!;
      _textController.clear();
      setState(() {
        _editingMessage = null;
        _isComposing = false;
      });
      try {
        await auth.api.editMessageText(instanceId, target.waId, text);
        final idx = _messages.indexWhere((m) => m.waId == target.waId);
        if (idx != -1 && mounted) {
          setState(() {
            final old = _messages[idx];
            _messages[idx] = MessageModel(
              id: old.id,
              waId: old.waId,
              chatId: old.chatId,
              fromMe: old.fromMe,
              status: old.status,
              type: old.type,
              text: text,
              mimetype: old.mimetype,
              filename: old.filename,
              quotedText: old.quotedText,
              starred: old.starred,
              deleted: old.deleted,
              edited: true,
              editedAt: DateTime.now(),
              originalText: (old.originalText != null && old.originalText!.isNotEmpty) ? old.originalText : old.text,
              edits: [...old.edits, MessageEditHistory(text: old.text, at: DateTime.now())],
              reactions: old.reactions,
              createdAt: old.createdAt,
              name: old.name,
              participant: old.participant,
            );
          });
        }
        _debouncedSync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message edited successfully'),
              backgroundColor: WhatsAppTheme.primaryGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to edit: $e'), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    final quoted = _replyingTo;
    _textController.clear();
    if (_sentComposing) {
      _sentComposing = false;
      _outgoingPresenceTimer?.cancel();
      auth.api.sendPresence(instanceId, widget.chat.chatId, 'paused');
    }
    setState(() {
      _isComposing = false;
      _replyingTo = null;
      _showEmojiPicker = false;
    });

    final tempWaId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      waId: tempWaId,
      chatId: widget.chat.chatId,
      fromMe: true,
      status: 'pending',
      type: 'text',
      text: text,
      quotedText: quoted?.text ?? '',
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom(smooth: true);

    try {
      await auth.api.sendMessage(
        instanceId,
        to: widget.chat.chatId,
        text: text,
        quotedWaId: quoted?.waId,
      );
      _debouncedSync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _showMessageActions(MessageModel message) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    MessageActionsSheet.show(
      context: context,
      message: message,
      currentUser: auth.currentUser,
      isGroup: widget.chat.isGroup,
      onReact: (emoji) async {
        try {
          await auth.api.reactMessage(instanceId, message.waId, emoji);
          _debouncedSync();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Reaction failed: $e')),
            );
          }
        }
      },
      onReply: () {
        setState(() {
          _replyingTo = message;
          _editingMessage = null;
        });
      },
      onEdit: (msg) {
        setState(() {
          _editingMessage = msg;
          _replyingTo = null;
          _textController.text = msg.text;
          _isComposing = msg.text.isNotEmpty;
        });
      },
      onForward: (msg) => _openForwardDialog(msg),
      onStar: () async {
        try {
          await auth.api.starMessage(instanceId, message.waId, !message.starred);
          _debouncedSync();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message.starred ? 'Message unstarred' : 'Message starred'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: $e')),
            );
          }
        }
      },
      onDelete: (scope) async {
        if (!UserPermissions.canDeleteMsg(auth.currentUser)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Deleting messages is restricted for your account by Admin.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        try {
          await auth.api.deleteMessage(instanceId, message.waId, scope: scope);
          _debouncedSync();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Message deleted for $scope')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete: $e')),
            );
          }
        }
      },
      onDownload: () => _downloadMedia(message),
      onViewPdf: () => _viewPdf(message),
      onReplyPrivately: () => _replyPrivately(message),
      onMessageSender: () => _messageSender(message),
      onMarkSeen: () => _markMessageSeen(message),
      onOpenDiff: () => DiffViewerModal.show(context, message),
    );
  }

  void _downloadMedia(MessageModel msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${msg.filename ?? "media attachment"} to device gallery'),
        backgroundColor: WhatsAppTheme.primaryGreen,
      ),
    );
  }

  void _viewPdf(MessageModel msg) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;
    final mediaUrl = '${ApiConfig.baseUrl}/api/instances/$instanceId/inbox/${msg.waId}/media?inline=1';
    final docName = msg.filename ?? (msg.text.isNotEmpty ? msg.text : 'Document.pdf');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          title: docName,
          documentUrl: mediaUrl,
          headers: auth.api.authHeaders,
          filename: docName,
          mimetype: msg.mimetype,
        ),
      ),
    );
  }

  void _replyPrivately(MessageModel msg) {
    final sender = msg.senderJid.isNotEmpty ? msg.senderJid : (msg.fromMe ? '' : widget.chat.chatId);
    if (sender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sender JID not available for private reply')),
      );
      return;
    }
    final privateChat = ChatModel(
      chatId: sender,
      name: msg.senderName.isNotEmpty ? msg.senderName : sender.split('@')[0],
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(chat: privateChat),
      ),
    );
  }

  void _messageSender(MessageModel msg) {
    final sender = msg.senderJid.isNotEmpty ? msg.senderJid : (msg.fromMe ? '' : widget.chat.chatId);
    if (sender.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sender JID not available')),
      );
      return;
    }
    final privateChat = ChatModel(
      chatId: sender,
      name: msg.senderName.isNotEmpty ? msg.senderName : sender.split('@')[0],
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(chat: privateChat),
      ),
    );
  }

  void _markMessageSeen(MessageModel msg) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;
    try {
      await auth.api.markMessageAsRead(instanceId, msg.waId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message marked as seen ✓ (read receipt sent)'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
  }

  void _openForwardDialog(MessageModel message) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    List<ChatModel> chatOptions = [];
    try {
      final cached = await CacheService.getCachedChats(instanceId);
      chatOptions = cached;
      if (chatOptions.isEmpty) {
        chatOptions = await auth.api.getChats(instanceId);
      }
    } catch (_) {}

    if (!mounted) return;

    final selectedChatIds = <String>{};
    String filterQuery = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = chatOptions.where((c) {
              final query = filterQuery.toLowerCase();
              return c.displayTitle.toLowerCase().contains(query) ||
                     c.chatId.toLowerCase().contains(query);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Forward message',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: selectedChatIds.isEmpty ? null : () async {
                          Navigator.pop(ctx);
                          int count = 0;
                          for (final targetId in selectedChatIds) {
                            try {
                              await auth.api.forwardMessage(
                                instanceId,
                                to: targetId,
                                forwardWaId: message.waId,
                              );
                              count++;
                            } catch (_) {}
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Forwarded to $count conversation${count == 1 ? "" : "s"}'),
                                backgroundColor: WhatsAppTheme.primaryGreen,
                              ),
                            );
                          }
                        },
                        child: Text(
                          selectedChatIds.isEmpty ? 'Select' : 'Send (${selectedChatIds.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selectedChatIds.isEmpty ? Colors.grey : WhatsAppTheme.primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search chats...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (q) {
                      setModalState(() => filterQuery = q);
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching chats found', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final c = filtered[i];
                              final isSelected = selectedChatIds.contains(c.chatId);
                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: WhatsAppTheme.primaryGreen,
                                secondary: ChatAvatar(
                                  chatId: c.chatId,
                                  title: c.displayTitle,
                                  isGroup: c.isGroup,
                                  isCommunity: c.isCommunity,
                                  isChannel: c.isChannel,
                                  radius: 18,
                                ),
                                title: Text(c.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  c.isChannel
                                      ? 'Channel'
                                      : c.isCommunity
                                          ? 'Community'
                                          : c.isGroup
                                              ? 'Group'
                                              : c.chatId,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onChanged: (v) {
                                  setModalState(() {
                                    if (v == true) {
                                      selectedChatIds.add(c.chatId);
                                    } else {
                                      selectedChatIds.remove(c.chatId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showAttachmentSheet() {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!UserPermissions.canSendMediaAttachments(auth.currentUser)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sending media is restricted for your account by Admin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _attachAction(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                gradient: const [Color(0xFF5E72E4), Color(0xFF825EE4)],
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
              _attachAction(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                gradient: const [Color(0xFFF5365C), Color(0xFFFB6340)],
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _attachAction(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                gradient: const [Color(0xFF8965E0), Color(0xFFBC8CEB)],
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _attachAction(
                icon: Icons.headphones_rounded,
                label: 'Audio',
                gradient: const [Color(0xFFFA8231), Color(0xFFFD9644)],
                onTap: () {
                  Navigator.pop(context);
                  _pickAudio();
                },
              ),
              _attachAction(
                icon: Icons.location_on_rounded,
                label: 'Location',
                gradient: const [Color(0xFF20BF6B), Color(0xFF26DE81)],
                onTap: () {
                  Navigator.pop(context);
                  _showLocationDialog();
                },
              ),
              _attachAction(
                icon: Icons.person_rounded,
                label: 'Contact',
                gradient: const [Color(0xFF0984E3), Color(0xFF74B9FF)],
                onTap: () {
                  Navigator.pop(context);
                  _showContactDialog();
                },
              ),
              _attachAction(
                icon: Icons.poll_rounded,
                label: 'Poll',
                gradient: const [Color(0xFF11CDEF), Color(0xFF1171EF)],
                onTap: () {
                  Navigator.pop(context);
                  _showPollDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attachAction({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: gradient.first.withOpacity(0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;

      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      final filename = picked.name.isNotEmpty
          ? picked.name
          : (source == ImageSource.camera ? 'camera_photo.jpg' : 'gallery_photo.jpg');
      final ext = filename.split('.').last.toLowerCase();
      final mimetype = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');

      if (!mounted) return;
      _showMediaConfirmation(
        type: 'image',
        filename: filename,
        fileBytes: bytes,
        mimetype: mimetype,
        base64Data: base64Data,
        previewFile: file,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'zip', 'rar', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      List<int>? bytes = pickedFile.bytes;
      if (bytes == null && pickedFile.path != null) {
        bytes = await File(pickedFile.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Selected file is empty');
      }

      final base64Data = base64Encode(bytes);
      final filename = pickedFile.name;
      final ext = pickedFile.extension?.toLowerCase() ?? '';
      String mimetype = 'application/octet-stream';
      if (ext == 'pdf') mimetype = 'application/pdf';
      else if (ext == 'docx') mimetype = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      else if (ext == 'doc') mimetype = 'application/msword';
      else if (ext == 'xlsx') mimetype = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      else if (ext == 'xls') mimetype = 'application/vnd.ms-excel';
      else if (ext == 'txt' || ext == 'csv' || ext == 'json') mimetype = 'text/plain';
      else if (ext == 'zip') mimetype = 'application/zip';

      if (!mounted) return;
      _showMediaConfirmation(
        type: 'document',
        filename: filename,
        fileBytes: bytes,
        mimetype: mimetype,
        base64Data: base64Data,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick document: $e')),
        );
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      List<int>? bytes = pickedFile.bytes;
      if (bytes == null && pickedFile.path != null) {
        bytes = await File(pickedFile.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) return;

      final base64Data = base64Encode(bytes);
      final filename = pickedFile.name;
      final ext = pickedFile.extension?.toLowerCase() ?? 'mp3';
      String mimetype = 'audio/mpeg';
      if (ext == 'ogg') mimetype = 'audio/ogg';
      else if (ext == 'wav') mimetype = 'audio/wav';
      else if (ext == 'm4a') mimetype = 'audio/mp4';

      if (!mounted) return;
      _showMediaConfirmation(
        type: 'audio',
        filename: filename,
        fileBytes: bytes,
        mimetype: mimetype,
        base64Data: base64Data,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick audio: $e')),
        );
      }
    }
  }

  void _showMediaConfirmation({
    required String type,
    required String filename,
    required List<int> fileBytes,
    required String mimetype,
    required String base64Data,
    File? previewFile,
  }) {
    final captionCtrl = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        type == 'image'
                            ? Icons.image_rounded
                            : (type == 'audio' ? Icons.audiotrack_rounded : Icons.insert_drive_file_rounded),
                        color: WhatsAppTheme.primaryGreen,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              '${_formatBytes(fileBytes.length)} • $mimetype',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (type == 'image' && previewFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        width: double.infinity,
                        color: Colors.black12,
                        child: Image.file(
                          previewFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  if (type == 'image' && previewFile == null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        width: double.infinity,
                        color: Colors.black12,
                        child: Image.memory(
                          Uint8List.fromList(fileBytes),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  if (type == 'document')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, size: 40, color: Colors.redAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              filename,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (type == 'audio')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.headphones_rounded, size: 40, color: Colors.deepOrangeAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              filename,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_replyingTo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(left: BorderSide(color: WhatsAppTheme.primaryGreen, width: 3)),
                      ),
                      child: Text(
                        'Replying to: ${_replyingTo!.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: captionCtrl,
                          decoration: InputDecoration(
                            hintText: type == 'document' ? 'Add document note...' : 'Add a caption...',
                            filled: true,
                            fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'send_media_fab',
                        backgroundColor: WhatsAppTheme.primaryGreen,
                        onPressed: isSending
                            ? null
                            : () async {
                                setModalState(() => isSending = true);
                                final auth = Provider.of<AuthService>(this.context, listen: false);
                                final instanceId = auth.selectedInstance?.id;
                                if (instanceId == null) {
                                  Navigator.pop(ctx);
                                  return;
                                }
                                try {
                                  await auth.api.sendMediaMessage(
                                    instanceId,
                                    to: widget.chat.chatId,
                                    type: type,
                                    base64Data: base64Data,
                                    filename: filename,
                                    mimetype: mimetype,
                                    caption: captionCtrl.text.trim().isNotEmpty ? captionCtrl.text.trim() : null,
                                    quotedWaId: _replyingTo?.waId,
                                  );
                                  if (mounted) {
                                    setState(() => _replyingTo = null);
                                    _syncMessagesSilently();
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('${type[0].toUpperCase()}${type.substring(1)} sent!'),
                                        backgroundColor: WhatsAppTheme.primaryGreen,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isSending = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(content: Text('Failed to send media: $e')),
                                    );
                                  }
                                }
                              },
                        child: isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLocationDialog() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    final result = await Navigator.push<LocationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(),
      ),
    );

    if (result != null && mounted) {
      try {
        await auth.api.sendLocationMessage(
          instanceId,
          to: widget.chat.chatId,
          latitude: result.latitude,
          longitude: result.longitude,
          name: result.name,
          address: result.address,
          quotedWaId: _replyingTo?.waId,
        );
        if (mounted) {
          setState(() => _replyingTo = null);
          _debouncedSync();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 Location pin sent successfully!'),
              backgroundColor: WhatsAppTheme.primaryGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send location: $e')),
          );
        }
      }
    }
  }

  void _showContactDialog() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.person_rounded, color: Color(0xFF0984E3), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Share Contact Card',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Contact Full Name *',
                      hintText: 'e.g. John Doe',
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number *',
                      hintText: 'e.g. +1 555 123 4567 or 15551234567',
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.support_agent_rounded, size: 16),
                        label: const Text('Support (+1234567890)'),
                        onPressed: () {
                          setModalState(() {
                            nameCtrl.text = 'Zelon Support';
                            phoneCtrl.text = '+1234567890';
                          });
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.storefront_rounded, size: 16),
                        label: const Text('Sales (+1987654321)'),
                        onPressed: () {
                          setModalState(() {
                            nameCtrl.text = 'Sales Team';
                            phoneCtrl.text = '+1987654321';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSending
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final phone = phoneCtrl.text.trim();
                            if (name.isEmpty || phone.isEmpty) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Name and phone number are required')),
                              );
                              return;
                            }
                            setModalState(() => isSending = true);
                            try {
                              await auth.api.sendContactMessage(
                                instanceId,
                                to: widget.chat.chatId,
                                name: name,
                                phone: phone,
                                quotedWaId: _replyingTo?.waId,
                              );
                              if (mounted) {
                                setState(() => _replyingTo = null);
                                _syncMessagesSilently();
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('👤 Contact shared!'),
                                    backgroundColor: WhatsAppTheme.primaryGreen,
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isSending = false);
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('Failed to share contact: $e')),
                                );
                              }
                            }
                          },
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      isSending ? 'Sending...' : 'Send Contact',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPollDialog() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    final questionCtrl = TextEditingController();
    final optionCtrls = [
      TextEditingController(),
      TextEditingController(),
    ];
    bool allowMultiple = false;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.poll_rounded, color: Color(0xFF11CDEF), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Create Poll',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: questionCtrl,
                    decoration: InputDecoration(
                      labelText: 'Question *',
                      hintText: 'Ask a question...',
                      filled: true,
                      fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Options (min 2, max 12):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      itemCount: optionCtrls.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: optionCtrls[i],
                                decoration: InputDecoration(
                                  labelText: 'Option ${i + 1}',
                                  hintText: 'Enter option text',
                                  filled: true,
                                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            if (optionCtrls.length > 2)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  setModalState(() {
                                    optionCtrls.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (optionCtrls.length < 12)
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          optionCtrls.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Option'),
                      style: TextButton.styleFrom(foregroundColor: WhatsAppTheme.primaryGreen),
                    ),
                  SwitchListTile(
                    title: const Text('Allow multiple answers', style: TextStyle(fontSize: 14)),
                    value: allowMultiple,
                    activeColor: WhatsAppTheme.primaryGreen,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setModalState(() => allowMultiple = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSending
                        ? null
                        : () async {
                            final question = questionCtrl.text.trim();
                            final validOptions = optionCtrls
                                .map((c) => c.text.trim())
                                .where((t) => t.isNotEmpty)
                                .toList();

                            if (question.isEmpty) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Please enter a poll question')),
                              );
                              return;
                            }
                            if (validOptions.length < 2) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Please provide at least 2 non-empty options')),
                              );
                              return;
                            }

                            setModalState(() => isSending = true);
                            try {
                              await auth.api.sendPollMessage(
                                instanceId,
                                to: widget.chat.chatId,
                                question: question,
                                options: validOptions,
                                selectableCount: allowMultiple ? validOptions.length : 1,
                                quotedWaId: _replyingTo?.waId,
                              );
                              if (mounted) {
                                setState(() => _replyingTo = null);
                                _syncMessagesSilently();
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('📊 Poll created!'),
                                    backgroundColor: WhatsAppTheme.primaryGreen,
                                  ),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isSending = false);
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('Failed to create poll: $e')),
                                );
                              }
                            }
                          },
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      isSending ? 'Sending...' : 'Create & Send Poll',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _buildSubtitle() {
    if (_livePresence != null) {
      return _livePresence!;
    }
    if (widget.chat.isChannel) {
      return 'Channel • tap for info';
    }
    if (widget.chat.isCommunity) {
      return 'Community • tap for info';
    }
    if (widget.chat.isGroup) {
      return 'tap for group info';
    }
    final rawNumber = widget.chat.chatId.split('@').first;
    return rawNumber.isNotEmpty ? '+$rawNumber' : 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;
    final instanceId = auth.selectedInstance?.id;
    final subtitle = _buildSubtitle();
    final isTypingOrRecording = _livePresence == 'typing...' || _livePresence == 'recording audio...';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContactProfileScreen(chat: widget.chat),
              ),
            );
          },
          child: Row(
            children: [
              ChatAvatar(
                chatId: widget.chat.chatId,
                title: widget.chat.displayTitle,
                isGroup: widget.chat.isGroup,
                isCommunity: widget.chat.isCommunity,
                isChannel: widget.chat.isChannel,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.chat.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isTypingOrRecording ? FontWeight.bold : FontWeight.normal,
                        color: isTypingOrRecording ? WhatsAppTheme.accentGreen : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded, color: Colors.white, size: 22),
            tooltip: 'Mark as read',
            onPressed: () async {
              if (instanceId != null) {
                try {
                  await auth.api.markChatAsRead(instanceId, widget.chat.chatId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat marked as read')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
            tooltip: 'Sync Messages',
            onPressed: _syncMessagesSilently,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) async {
              if (val == 'mark_read') {
                if (instanceId != null) {
                  try {
                    await auth.api.markChatAsRead(instanceId, widget.chat.chatId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Chat marked as read')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                }
              } else if (val == 'info') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContactProfileScreen(chat: widget.chat),
                  ),
                );
              } else if (val == 'clear') {
                setState(() => _messages.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat view cleared')),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(
                      widget.chat.isChannel
                          ? Icons.campaign_rounded
                          : widget.chat.isCommunity
                              ? Icons.diversity_3_rounded
                              : widget.chat.isGroup
                                  ? Icons.group
                                  : Icons.person,
                      color: WhatsAppTheme.primaryGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.chat.isChannel
                          ? 'Channel info'
                          : widget.chat.isCommunity
                              ? 'Community info'
                              : widget.chat.isGroup
                                  ? 'Group info'
                                  : 'Contact info',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mark_read',
                child: Row(
                  children: [
                    Icon(Icons.mark_chat_read, color: WhatsAppTheme.primaryGreen, size: 20),
                    SizedBox(width: 10),
                    Text('Mark as read'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.grey, size: 20),
                    SizedBox(width: 10),
                    Text('Clear chat view'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: Container(
        decoration: BoxDecoration(
          color: Provider.of<ChatDesignService>(context).wallpaperColor != Colors.transparent
              ? Provider.of<ChatDesignService>(context).wallpaperColor
              : (isDark ? WhatsAppTheme.bgDark : WhatsAppTheme.bgLight),
        ),
        child: Column(
          children: [
            // Messages List View
            Expanded(
              child: _isLoading && _messages.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
                  : _messages.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black38 : Colors.white70,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Messages are end-to-end encrypted.\nSay hello!',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return ChatBubble(
                              message: msg,
                              currentUser: user,
                              instanceId: instanceId,
                              onOpenDiff: () => DiffViewerModal.show(context, msg),
                              onLongPress: () => _showMessageActions(msg),
                            );
                          },
                        ),
            ),

            // Editing Message Banner (if editing)
            if (_editingMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: WhatsAppTheme.editedChip, width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Editing message',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: WhatsAppTheme.editedChip,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _editingMessage!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _editingMessage = null;
                          _textController.clear();
                          _isComposing = false;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Quoted Reply Banner (if replying)
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: WhatsAppTheme.primaryGreen, width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyingTo!.fromMe ? 'You' : (_replyingTo!.name.isNotEmpty ? _replyingTo!.name : 'Contact'),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replyingTo!.text.isNotEmpty ? _replyingTo!.text : '[Attachment]',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _replyingTo = null),
                    ),
                  ],
                ),
              ),

            // AI Suggestions bar
            if (_isLoadingAiSuggestions)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE8F0FE),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Gemini AI is drafting replies...',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : const Color(0xFF1A73E8),
                      ),
                    ),
                  ],
                ),
              )
            else if (_aiSuggestions.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 14, color: isDark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8)),
                        const SizedBox(width: 6),
                        Text(
                          'Suggested replies (Gemini AI)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _aiSuggestions.clear()),
                          child: const Icon(Icons.close, size: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _aiSuggestions.map((suggestion) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: isDark ? const Color(0xFF334155) : Colors.white,
                              side: BorderSide(
                                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                              ),
                              label: Text(
                                suggestion,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              onPressed: () {
                                _textController.text = suggestion;
                                _textController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: suggestion.length),
                                );
                                setState(() {
                                  _isComposing = true;
                                  _aiSuggestions.clear();
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

            // Message Composer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.transparent,
              child: SafeArea(
                child: Row(
                  children: [
                    // Text input bubble
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showEmojiPicker = !_showEmojiPicker;
                                });
                              },
                            ),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                maxLines: 5,
                                minLines: 1,
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                ),
                                onTap: () {
                                  if (_showEmojiPicker) {
                                    setState(() => _showEmojiPicker = false);
                                  }
                                },
                                onChanged: (val) {
                                  final composing = val.trim().isNotEmpty;
                                  if (composing != _isComposing) {
                                    setState(() => _isComposing = composing);
                                  }
                                  _handleOutgoingTyping(composing);
                                },
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.auto_awesome,
                                color: isDark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8),
                                size: 22,
                              ),
                              tooltip: 'Gemini AI Smart Reply',
                              onPressed: _showAiAssistantDialog,
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.attach_file,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                              onPressed: _showAttachmentSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Send or Mic Button
                    _isRecording
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Cancel
                            GestureDetector(
                              onTap: _cancelRecording,
                              child: const CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.red,
                                child: Icon(Icons.delete, color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Duration
                            Text(
                              _recordingDuration,
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Send recording
                            GestureDetector(
                              onTap: _stopAndSendRecording,
                              child: const CircleAvatar(
                                radius: 24,
                                backgroundColor: WhatsAppTheme.primaryGreen,
                                child: Icon(Icons.send, color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        )
                      : GestureDetector(
                          onTap: _isComposing ? _sendMessage : _startRecording,
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: WhatsAppTheme.primaryGreen,
                            child: Icon(
                              _isComposing ? Icons.send : Icons.mic,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),

            // In-app WhatsApp Emoji Picker drawer
            if (_showEmojiPicker)
              Container(
                height: 230,
                color: isDark ? WhatsAppTheme.surfaceDark : const Color(0xFFF0F2F5),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: _popularEmojis.length,
                  itemBuilder: (ctx, i) {
                    final emoji = _popularEmojis[i];
                    return InkWell(
                      onTap: () {
                        _textController.text = _textController.text + emoji;
                        _textController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _textController.text.length),
                        );
                        if (!_isComposing) {
                          setState(() => _isComposing = true);
                        }
                      },
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
