import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    // 1. Instant load from local cache
    final cached = await CacheService.getCachedMessages(instanceId, widget.chat.chatId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
      });
      _scrollToBottom();
    }

    // 2. Fetch fresh from API
    setState(() => _isLoading = true);
    try {
      final fresh = await auth.api.getMessages(instanceId, widget.chat.chatId);
      if (mounted) {
        setState(() {
          _messages = fresh;
          _isLoading = false;
        });
        await CacheService.saveMessages(instanceId, widget.chat.chatId, fresh);
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
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

    // Optimistic UI update
    final tempMsg = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      waId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
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
    _scrollToBottom();

    try {
      await auth.api.sendMessage(
        instanceId,
        to: widget.chat.chatId,
        text: text,
      );
      // Re-fetch messages in background
      final fresh = await auth.api.getMessages(instanceId, widget.chat.chatId);
      if (mounted) {
        setState(() => _messages = fresh);
        await CacheService.saveMessages(instanceId, widget.chat.chatId, fresh);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Colors.white24,
              child: Text(
                widget.chat.displayTitle.isNotEmpty ? widget.chat.displayTitle[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
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
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    widget.chat.isGroup ? 'Group' : 'WhatsApp Contact',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call), onPressed: () {}),
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
              const PopupMenuItem(value: 'mute', child: Text('Mute notifications')),
              const PopupMenuItem(value: 'info', child: Text('Contact info')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? WhatsAppTheme.chatBgDark : WhatsAppTheme.chatBgLight,
        ),
        child: Column(
          children: [
            // Messages ListView
            Expanded(
              child: _isLoading && _messages.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
                  : _messages.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black45 : Colors.white70,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('No messages yet. Send a message to start chatting!'),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
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

            // Chat Input Bar
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    // Text Box Container
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.sentiment_satisfied_alt_outlined, color: WhatsAppTheme.grayTick),
                              onPressed: () {},
                            ),
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                maxLines: 4,
                                minLines: 1,
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  border: InputBorder.none,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _isComposing = val.trim().isNotEmpty;
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: WhatsAppTheme.grayTick),
                              onPressed: _showAttachmentSheet,
                            ),
                            if (!_isComposing) ...[
                              IconButton(
                                icon: const Icon(Icons.camera_alt, color: WhatsAppTheme.grayTick),
                                onPressed: () {},
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Send or Mic FAB
                    GestureDetector(
                      onTap: _isComposing ? _sendMessage : null,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: WhatsAppTheme.fabGreen,
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
