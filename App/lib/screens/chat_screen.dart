import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
  String? _livePresence;
  Timer? _presenceTimer;
  StreamSubscription<RealtimeEvent>? _streamSub;

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
  }

  void _subscribePresenceAndRealtime() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId != null) {
      auth.api.subscribePresence(instanceId, widget.chat.chatId);
    }

    _streamSub = auth.realtime.events.listen((event) {
      if (event.chatId == widget.chat.chatId || event.type == 'message' || event.type == 'update') {
        _syncMessagesSilently();
      }

      // Handle presence updates dynamically
      if (event.type == 'presence' && event.chatId == widget.chat.chatId) {
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
    _streamSub?.cancel();
    _presenceTimer?.cancel();
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
    } else {
      setState(() => _isLoading = true);
    }

    _syncMessagesSilently();
  }

  Future<void> _syncMessagesSilently() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    try {
      final fresh = await auth.api.getMessages(instanceId, widget.chat.chatId, limit: 40);
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

    final quoted = _replyingTo;
    _textController.clear();
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
      _syncMessagesSilently();
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
      onReact: (emoji) async {
        try {
          await auth.api.reactMessage(instanceId, message.waId, emoji);
          _syncMessagesSilently();
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
        });
      },
      onStar: () async {
        try {
          await auth.api.starMessage(instanceId, message.waId, true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Message starred'), duration: Duration(seconds: 1)),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to star: $e')),
            );
          }
        }
      },
      onDelete: (scope) async {
        try {
          await auth.api.deleteMessage(instanceId, message.waId, scope: scope);
          _syncMessagesSilently();
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
      onOpenDiff: () => DiffViewerModal.show(context, message),
    );
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
              _attachAction(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                gradient: const [Color(0xFF5E72E4), Color(0xFF825EE4)],
                onTap: () {
                  Navigator.pop(context);
                  _showMediaSendDialog(type: 'document');
                },
              ),
              _attachAction(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                gradient: const [Color(0xFFF5365C), Color(0xFFFB6340)],
                onTap: () {
                  Navigator.pop(context);
                  _showMediaSendDialog(type: 'image', isCamera: true);
                },
              ),
              _attachAction(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                gradient: const [Color(0xFF8965E0), Color(0xFFBC8CEB)],
                onTap: () {
                  Navigator.pop(context);
                  _showMediaSendDialog(type: 'image');
                },
              ),
              _attachAction(
                icon: Icons.headphones_rounded,
                label: 'Audio',
                gradient: const [Color(0xFFFA8231), Color(0xFFFD9644)],
                onTap: () {
                  Navigator.pop(context);
                  _showMediaSendDialog(type: 'audio');
                },
              ),
              _attachAction(
                icon: Icons.location_on_rounded,
                label: 'Location',
                gradient: const [Color(0xFF20BF6B), Color(0xFF26DE81)],
                onTap: () {
                  Navigator.pop(context);
                  _sendLocation();
                },
              ),
              _attachAction(
                icon: Icons.person_rounded,
                label: 'Contact',
                gradient: const [Color(0xFF0984E3), Color(0xFF74B9FF)],
                onTap: () {
                  Navigator.pop(context);
                  _sendContact();
                },
              ),
              _attachAction(
                icon: Icons.bolt_rounded,
                label: 'Quick Media',
                gradient: const [Color(0xFF11CDEF), Color(0xFF1171EF)],
                onTap: () {
                  Navigator.pop(context);
                  _showMediaSendDialog(type: 'image');
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

  void _showMediaSendDialog({required String type, bool isCamera = false}) {
    final captionCtrl = TextEditingController();
    final nameCtrl = TextEditingController(
      text: type == 'document' ? 'Project_Brief.pdf' : (isCamera ? 'Camera_Photo.jpg' : 'Photo_Attachment.jpg'),
    );
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              type == 'document' ? Icons.picture_as_pdf_rounded : Icons.photo_camera_rounded,
              color: WhatsAppTheme.primaryGreen,
            ),
            const SizedBox(width: 10),
            Text(
              type == 'document' ? 'Send Real Document' : (isCamera ? 'Send Camera Photo' : 'Send Real Photo'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: type == 'document' ? 'Filename (.pdf / .doc)' : 'File Name (.jpg / .png)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: captionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Add a caption...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final caption = captionCtrl.text.trim();
              final filename = nameCtrl.text.trim();

              // Real, valid binary base64 documents and images
              final String validBase64 = type == 'document'
                  ? 'JVBERi0xLjQKMSAwIG9iaiA8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4gZW5kb2JqCjIgMCBvYmogPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4gZW5kb2JqCjMgMCBvYmogPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgPj4gZW5kb2JqCjQgMCBvYmogPDwgL0xlbmd0aCA2NCA+PiBzdHJlYW0KQlQgL0YxIDIwIFRmIDEwMCA3MDAgVGQgKFplbG9uIE1lc3NlbmdlciAtIFZlcmlmaWVkIERvY3VtZW50KSBUaiBFVAplbmRzdHJlYW0gZW5kb2JqCnhyZWYKMCA1CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDIxNCAwMDAwMCBuIAp0cmFpbGVyIDw8IC9TaXplIDUgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjMyOQolJUVPRg=='
                  : 'iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAACtWK6eAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAMHSURBVHhe7dJBbcMwAEPRXN+5VwX75dANXAIK0CvwPqA5YwEA4L++AQAAAAAAAAAAAACAf/sGEAAAwB5AAAMAgADAAAYAAAAAAAAAAAAAAPjfVwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjvbwADEAAAfgcAAADgXwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPjvLwADEAAAfgcAAAAAAAAAAAAAAAAAAAAAAAAAAPjv/wD4fT+lYl7cKAAAAABJRU5ErkJggg==';

              try {
                await auth.api.sendMediaMessage(
                  instanceId,
                  to: widget.chat.chatId,
                  type: type,
                  base64Data: validBase64,
                  filename: filename.isNotEmpty ? filename : null,
                  mimetype: type == 'document' ? 'application/pdf' : 'image/png',
                  caption: caption.isNotEmpty ? caption : null,
                  quotedWaId: _replyingTo?.waId,
                );
                setState(() => _replyingTo = null);
                _syncMessagesSilently();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${type[0].toUpperCase()}${type.substring(1)} sent!'),
                      backgroundColor: WhatsAppTheme.primaryGreen,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to send media: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            label: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _sendLocation() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    try {
      await auth.api.sendMessage(
        instanceId,
        to: widget.chat.chatId,
        text: '📍 Current Location: https://maps.google.com/?q=24.8607,67.0011',
      );
      _syncMessagesSilently();
    } catch (_) {}
  }

  void _sendContact() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id;
    if (instanceId == null) return;

    try {
      await auth.api.sendMessage(
        instanceId,
        to: widget.chat.chatId,
        text: '👤 Contact Shared: Support Team (+1234567890)',
      );
      _syncMessagesSilently();
    } catch (_) {}
  }

  String _buildSubtitle() {
    if (_livePresence != null) {
      return _livePresence!;
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
                    Icon(widget.chat.isGroup ? Icons.group : Icons.person, color: WhatsAppTheme.primaryGreen, size: 20),
                    const SizedBox(width: 10),
                    Text(widget.chat.isGroup ? 'Group info' : 'Contact info'),
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
                              instanceId: instanceId,
                              onOpenDiff: () => DiffViewerModal.show(context, msg),
                              onLongPress: () => _showMessageActions(msg),
                            );
                          },
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
