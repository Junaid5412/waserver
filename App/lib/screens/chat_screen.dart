import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/realtime_service.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_bubble.dart';
import 'diff_viewer_screen.dart';

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
  StreamSubscription<RealtimeEvent>? _streamSub;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final auth = Provider.of<AuthService>(context, listen: false);
    _streamSub = auth.realtime.events.listen((event) {
      if (event.chatId == widget.chat.chatId || event.type == 'message' || event.type == 'update') {
        _syncMessagesSilently();
      }
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    // 1. Instant 0ms load from local disk cache
    final cached = await CacheService.getCachedMessages(instanceId, widget.chat.chatId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _isLoading = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Fetch latest messages from API in background
    _syncMessagesSilently();
  }

  Future<void> _syncMessagesSilently() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    try {
      final fresh = await auth.api.getMessages(instanceId, widget.chat.chatId, limit: 35);
      if (mounted) {
        setState(() {
          _messages = fresh;
          _isLoading = false;
        });
        await CacheService.saveMessages(instanceId, widget.chat.chatId, fresh);
        _scrollToBottom(smooth: true);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    _textController.clear();
    setState(() => _isComposing = false);

    // 0ms Optimistic UI update: message appears immediately with pending status
    final tempWaId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      waId: tempWaId,
      chatId: widget.chat.chatId,
      fromMe: true,
      status: 'pending',
      type: 'text',
      text: text,
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
      );
      // Mark as sent
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.waId == tempWaId);
          if (idx != -1) {
            _messages[idx] = MessageModel(
              id: _messages[idx].id,
              waId: _messages[idx].waId,
              chatId: _messages[idx].chatId,
              fromMe: true,
              status: 'sent',
              type: _messages[idx].type,
              text: _messages[idx].text,
              createdAt: _messages[idx].createdAt,
            );
          }
        });
      }
      _syncMessagesSilently();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _showAttachmentSheet() {
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
            spacing: 24,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _attachIcon(Icons.insert_drive_file, 'Document', Colors.indigo),
              _attachIcon(Icons.camera_alt, 'Camera', Colors.pink),
              _attachIcon(Icons.photo, 'Gallery', Colors.purple),
              _attachIcon(Icons.headphones, 'Audio', Colors.orange),
              _attachIcon(Icons.location_on, 'Location', Colors.teal),
              _attachIcon(Icons.person, 'Contact', Colors.blue),
            ],
          ),
        );
      },
    );
  }

  Widget _attachIcon(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ChatAvatar(
              chatId: widget.chat.chatId,
              title: widget.chat.displayTitle,
              isGroup: widget.chat.isGroup,
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
                    widget.chat.isGroup ? 'Group Chat' : 'Online',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
            tooltip: 'Sync Messages',
            onPressed: _syncMessagesSilently,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),

      body: Container(
        decoration: BoxDecoration(
          color: isDark ? WhatsAppTheme.bgDark : WhatsAppTheme.bgLight,
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
                              onOpenDiff: () => DiffViewerModal.show(context, msg),
                            );
                          },
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
                                Icons.emoji_emotions_outlined,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                              onPressed: () {},
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
                                onChanged: (val) {
                                  final composing = val.trim().isNotEmpty;
                                  if (composing != _isComposing) {
                                    setState(() => _isComposing = composing);
                                  }
                                },
                              ),
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
                    GestureDetector(
                      onTap: _sendMessage,
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
          ],
        ),
      ),
    );
  }
}
