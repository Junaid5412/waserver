import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'document_viewer_screen.dart';
import 'email_composer_screen.dart';

class EmailDetailScreen extends StatefulWidget {
  final String uid;
  final String folder;
  final String? accountId;
  final List<Map<String, dynamic>> accounts;

  const EmailDetailScreen({
    super.key,
    required this.uid,
    this.folder = 'INBOX',
    this.accountId,
    this.accounts = const [],
  });

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _email;
  bool _isStarred = false;
  bool _isGeneratingAi = false;

  @override
  void initState() {
    super.initState();
    _loadEmailDetail();
  }

  Future<void> _loadEmailDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final data = await auth.api.getEmailMessageDetail(
        widget.uid,
        accountId: widget.accountId,
        folder: widget.folder,
      );
      if (mounted) {
        setState(() {
          _email = data;
          _isStarred = data['flagged'] == true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleStar() async {
    final nextState = !_isStarred;
    setState(() => _isStarred = nextState);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.api.flagEmailMessage(
        widget.uid,
        accountId: widget.accountId,
        folder: widget.folder,
        star: nextState,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isStarred = !nextState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to star email: $e')),
        );
      }
    }
  }

  Future<void> _deleteEmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Email'),
        content: const Text('Are you sure you want to move this email to Trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final auth = Provider.of<AuthService>(context, listen: false);
        await auth.api.deleteEmailMessage(
          widget.uid,
          accountId: widget.accountId,
          folder: widget.folder,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email moved to Trash')),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete email: $e')),
          );
        }
      }
    }
  }

  String _formatDateTime(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  String _cleanHtml(String html) {
    // Strips script, style, head, and tags for clean text rendering
    var text = html.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?<\/style>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'</?(p|div|tr|br|h[1-6])[^>]*>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _openAttachment(Map<String, dynamic> att) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final index = att['index'] ?? 0;
    final filename = att['filename'] ?? 'attachment';
    final mimetype = att['contentType'] ?? 'application/octet-stream';
    final downloadUrl = '${ApiConfig.emailAttachmentUrl(widget.uid, index)}?folder=${widget.folder}${widget.accountId != null ? "&accountId=${widget.accountId}" : ""}';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          title: filename,
          documentUrl: downloadUrl,
          headers: auth.apiHeaders,
          filename: filename,
          mimetype: mimetype,
        ),
      ),
    );
  }

  void _reply({bool replyAll = false, String? prefilledBody}) {
    if (_email == null) return;

    final fromObj = _email!['from'];
    final replyToAddress = fromObj is Map ? fromObj['address'] ?? '' : fromObj.toString();
    final subject = _email!['subject'] ?? '';
    final replySubject = subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject';

    String? ccList;
    if (replyAll) {
      final toList = _email!['to'];
      if (toList is List) {
        final others = toList
            .map((t) => t is Map ? t['address'] : t.toString())
            .where((addr) => addr != null && addr != replyToAddress)
            .toList();
        if (others.isNotEmpty) ccList = others.join(', ');
      }
    }

    final rawBody = _email!['text']?.toString().isNotEmpty == true
        ? _email!['text'].toString()
        : _cleanHtml(_email!['html']?.toString() ?? '');

    final originalHeader = '\n\n--- Original Message ---\n'
        'From: ${_email!['from']?['name'] ?? ''} <$replyToAddress>\n'
        'Date: ${_formatDateTime(_email!['date'])}\n'
        'Subject: $subject\n\n'
        '$rawBody';

    final body = prefilledBody != null
        ? '$prefilledBody$originalHeader'
        : '\n$originalHeader';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmailComposerScreen(
          initialTo: replyToAddress,
          initialCc: ccList,
          initialSubject: replySubject,
          initialBody: body,
          inReplyTo: _email!['messageId']?.toString(),
          references: _email!['messageId']?.toString(),
          selectedAccountId: widget.accountId,
          accounts: widget.accounts,
        ),
      ),
    );
  }

  void _forward() {
    if (_email == null) return;
    final subject = _email!['subject'] ?? '';
    final forwardSubject = subject.toLowerCase().startsWith('fwd:') ? subject : 'Fwd: $subject';

    final rawBody = _email!['text']?.toString().isNotEmpty == true
        ? _email!['text'].toString()
        : _cleanHtml(_email!['html']?.toString() ?? '');

    final body = '\n\n---------- Forwarded message ---------\n'
        'From: ${_email!['from']?['name'] ?? ''} <${_email!['from']?['address'] ?? ''}>\n'
        'Date: ${_formatDateTime(_email!['date'])}\n'
        'Subject: $subject\n\n'
        '$rawBody';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmailComposerScreen(
          initialSubject: forwardSubject,
          initialBody: body,
          selectedAccountId: widget.accountId,
          accounts: widget.accounts,
        ),
      ),
    );
  }

  Future<void> _openAiSmartReplySheet() async {
    if (_email == null) return;

    final subject = _email!['subject']?.toString() ?? '';
    final senderName = _email!['from']?['name']?.toString() ?? '';
    final senderEmail = _email!['from']?['address']?.toString() ?? '';
    final emailBody = _email!['text']?.toString().isNotEmpty == true
        ? _email!['text'].toString()
        : _cleanHtml(_email!['html']?.toString() ?? '');

    final customIntentCtrl = TextEditingController();
    List<dynamic> generatedReplies = [];
    bool isGenerating = false;
    String? aiError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> triggerGeneration([String? intent]) async {
              setSheetState(() {
                isGenerating = true;
                aiError = null;
              });
              try {
                final auth = Provider.of<AuthService>(context, listen: false);
                final res = await auth.api.generateAiEmailReply(
                  subject: subject,
                  senderName: senderName,
                  senderEmail: senderEmail,
                  emailBody: emailBody,
                  userIntent: intent ?? customIntentCtrl.text.trim(),
                );
                if (res['replies'] is List) {
                  setSheetState(() {
                    generatedReplies = res['replies'];
                    isGenerating = false;
                  });
                }
              } catch (e) {
                setSheetState(() {
                  aiError = e.toString().replaceAll('Exception:', '').trim();
                  isGenerating = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome, color: WhatsAppTheme.primaryGreen, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'AI Smart Email Reply',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick Tone Buttons
                    const Text('Quick Suggestions:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.thumb_up_alt_outlined, size: 16, color: WhatsAppTheme.primaryGreen),
                          label: const Text('Polite Confirmation'),
                          onPressed: isGenerating ? null : () => triggerGeneration('Confirm receipt and agree to proceed politely'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.help_outline, size: 16, color: WhatsAppTheme.primaryGreen),
                          label: const Text('Request More Info'),
                          onPressed: isGenerating ? null : () => triggerGeneration('Ask for more details and specific requirements politely'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.cancel_outlined, size: 16, color: Colors.orange),
                          label: const Text('Polite Decline'),
                          onPressed: isGenerating ? null : () => triggerGeneration('Politely decline with well-wishes'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.schedule, size: 16, color: Colors.blue),
                          label: const Text('Will Review Later'),
                          onPressed: isGenerating ? null : () => triggerGeneration('Acknowledge and inform that I am reviewing and will get back shortly'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Custom instructions input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customIntentCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Or type custom instructions...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.filled(backgroundColor: WhatsAppTheme.primaryGreen),
                          icon: isGenerating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_upward, color: Colors.white),
                          onPressed: isGenerating
                              ? null
                              : () {
                                  if (customIntentCtrl.text.trim().isNotEmpty) {
                                    triggerGeneration();
                                  }
                                },
                        ),
                      ],
                    ),

                    if (aiError != null) ...[
                      const SizedBox(height: 10),
                      Text(aiError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],

                    const SizedBox(height: 14),

                    // Generated replies
                    if (isGenerating)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
                              SizedBox(height: 12),
                              Text('Gemini 3.1+ is drafting replies...', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else if (generatedReplies.isNotEmpty)
                      Expanded(
                        child: ListView.separated(
                          itemCount: generatedReplies.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final r = generatedReplies[index];
                            final tone = r['tone'] ?? 'Professional';
                            final label = r['label'] ?? '';
                            final replyText = r['reply'] ?? '';
                            final reasoning = r['reasoning'] ?? '';

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: WhatsAppTheme.primaryGreen.withOpacity(0.3)),
                                color: WhatsAppTheme.primaryGreen.withOpacity(0.04),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: WhatsAppTheme.primaryGreen.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          tone,
                                          style: const TextStyle(
                                            color: WhatsAppTheme.primaryGreen,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: WhatsAppTheme.primaryGreen,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _reply(prefilledBody: replyText);
                                        },
                                        icon: const Icon(Icons.send, size: 14, color: Colors.white),
                                        label: const Text('Use Reply', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    replyText,
                                    style: const TextStyle(fontSize: 13, height: 1.4),
                                  ),
                                  if (reasoning.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '💡 $reasoning',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: WhatsAppTheme.primaryGreen,
          title: const Text('Reading Email'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
        ),
      );
    }

    if (_errorMessage != null || _email == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: WhatsAppTheme.primaryGreen,
          title: const Text('Email Error'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainTestAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? 'Unable to load email',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadEmailDetail,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final subject = _email!['subject']?.toString().isNotEmpty == true
        ? _email!['subject'].toString()
        : '(No Subject)';
    final fromObj = _email!['from'];
    final fromName = fromObj is Map ? fromObj['name']?.toString() ?? '' : '';
    final fromAddress = fromObj is Map ? fromObj['address']?.toString() ?? '' : fromObj.toString();
    final displayName = fromName.isNotEmpty ? fromName : fromAddress;
    final initialLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final toList = _email!['to'];
    String toText = '';
    if (toList is List) {
      toText = toList.map((t) => t is Map ? (t['name'] ?? t['address']) : t.toString()).join(', ');
    } else if (toList != null) {
      toText = toList.toString();
    }

    final attachments = (_email!['attachments'] as List?) ?? [];

    final rawBody = _email!['text']?.toString().isNotEmpty == true
        ? _email!['text'].toString()
        : _cleanHtml(_email!['html']?.toString() ?? '');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.primaryGreen,
        title: const Text('Email Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: _isStarred ? 'Unstar' : 'Star',
            icon: Icon(
              _isStarred ? Icons.star : Icons.star_border,
              color: _isStarred ? Colors.amber : Colors.white,
            ),
            onPressed: _toggleStar,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteEmail,
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'reply') _reply();
              if (val == 'replyAll') _reply(replyAll: true);
              if (val == 'forward') _forward();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reply', child: Text('Reply')),
              const PopupMenuItem(value: 'replyAll', child: Text('Reply All')),
              const PopupMenuItem(value: 'forward', child: Text('Forward')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Subject
                SelectableText(
                  subject,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.3),
                ),
                const SizedBox(height: 16),

                // Sender Card
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: WhatsAppTheme.primaryGreen.withOpacity(0.85),
                      child: Text(
                        initialLetter,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                              Text(
                                _formatDateTime(_email!['date']),
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fromAddress,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          if (toText.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'To: $toText',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // Attachments section
                if (attachments.isNotEmpty) ...[
                  Text(
                    'Attachments (${attachments.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments.map((att) {
                      final map = Map<String, dynamic>.from(att);
                      final fname = map['filename']?.toString() ?? 'attachment';
                      final sizeBytes = int.tryParse(map['size']?.toString() ?? '0') ?? 0;
                      return InkWell(
                        onTap: () => _openAttachment(map),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.insert_drive_file, color: WhatsAppTheme.primaryGreen, size: 20),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  fname,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatSize(sizeBytes),
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.visibility, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                ],

                // Email Body Text
                SelectableText(
                  rawBody,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // AI Smart Reply Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WhatsAppTheme.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: _openAiSmartReplySheet,
                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  label: const Text('AI Reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: () => _reply(),
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('Reply'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: () => _forward(),
                  icon: const Icon(Icons.forward, size: 18),
                  label: const Text('Forward'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
