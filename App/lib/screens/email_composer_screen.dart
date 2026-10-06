import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

class EmailComposerScreen extends StatefulWidget {
  final String? initialTo;
  final String? initialCc;
  final String? initialBcc;
  final String? initialSubject;
  final String? initialBody;
  final String? inReplyTo;
  final dynamic references;
  final String? selectedAccountId;
  final List<Map<String, dynamic>> accounts;

  const EmailComposerScreen({
    super.key,
    this.initialTo,
    this.initialCc,
    this.initialBcc,
    this.initialSubject,
    this.initialBody,
    this.inReplyTo,
    this.references,
    this.selectedAccountId,
    this.accounts = const [],
  });

  @override
  State<EmailComposerScreen> createState() => _EmailComposerScreenState();
}

class _EmailComposerScreenState extends State<EmailComposerScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _toController;
  late TextEditingController _ccController;
  late TextEditingController _bccController;
  late TextEditingController _subjectController;
  late TextEditingController _bodyController;

  bool _showCcBcc = false;
  String? _currentAccountId;
  bool _isSending = false;
  bool _isGeneratingAi = false;

  final List<Map<String, dynamic>> _attachments = [];

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.initialTo ?? '');
    _ccController = TextEditingController(text: widget.initialCc ?? '');
    _bccController = TextEditingController(text: widget.initialBcc ?? '');
    _subjectController = TextEditingController(text: widget.initialSubject ?? '');
    _bodyController = TextEditingController(text: widget.initialBody ?? '');

    if (widget.initialCc?.isNotEmpty == true || widget.initialBcc?.isNotEmpty == true) {
      _showCcBcc = true;
    }

    _currentAccountId = widget.selectedAccountId;
    if (_currentAccountId == null && widget.accounts.isNotEmpty) {
      final def = widget.accounts.firstWhere(
        (a) => a['isDefault'] == true,
        orElse: () => widget.accounts.first,
      );
      _currentAccountId = def['id']?.toString();
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      for (final f in result.files) {
        List<int>? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        }
        if (bytes != null && bytes.isNotEmpty) {
          final b64 = base64Encode(bytes);
          setState(() {
            _attachments.add({
              'filename': f.name,
              'size': f.size,
              'base64Data': b64,
            });
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick attachment: $e')),
        );
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _promptAiDraft() async {
    final promptCtrl = TextEditingController();
    String selectedTone = 'Professional';

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
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
                          'Draft with Gemini AI',
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
                  const Text(
                    'What would you like this email to say? Gemini will write a polished, professional email draft.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: promptCtrl,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Confirm meeting on Thursday at 3 PM and request the updated project proposal...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Tone:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['Professional', 'Friendly', 'Concise', 'Formal', 'Urgent'].map((tone) {
                      final isSel = selectedTone == tone;
                      return ChoiceChip(
                        label: Text(tone),
                        selected: isSel,
                        selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSel ? WhatsAppTheme.primaryGreen : null,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setModalState(() => selectedTone = tone),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WhatsAppTheme.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        if (promptCtrl.text.trim().isNotEmpty) {
                          Navigator.pop(ctx, '${promptCtrl.text.trim()} [Tone: $selectedTone]');
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, color: Colors.white),
                      label: const Text(
                        'Generate Draft',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isGeneratingAi = true);
      try {
        final auth = Provider.of<AuthService>(context, listen: false);
        final res = await auth.api.generateAiEmailReply(
          subject: _subjectController.text.trim().isNotEmpty ? _subjectController.text.trim() : null,
          userIntent: result,
          emailBody: _bodyController.text.trim().isNotEmpty ? _bodyController.text.trim() : null,
        );

        if (res['replies'] is List && (res['replies'] as List).isNotEmpty) {
          final first = res['replies'][0];
          final replyText = first['reply']?.toString() ?? '';
          setState(() {
            _bodyController.text = replyText;
            if (_subjectController.text.trim().isEmpty && first['label'] != null) {
              _subjectController.text = first['label'].toString();
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AI draft generated! Review and make any adjustments before sending.'),
                backgroundColor: WhatsAppTheme.primaryGreen,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('AI drafting failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isGeneratingAi = false);
      }
    }
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;
    final toText = _toController.text.trim();
    if (toText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one recipient email')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);

      final toList = toText.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final ccText = _ccController.text.trim();
      final ccList = ccText.isNotEmpty
          ? ccText.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : null;
      final bccText = _bccController.text.trim();
      final bccList = bccText.isNotEmpty
          ? bccText.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : null;

      final attachmentsPayload = _attachments.map((a) {
        return {
          'filename': a['filename'],
          'base64Data': a['base64Data'],
        };
      }).toList();

      await auth.api.sendEmail(
        accountId: _currentAccountId,
        to: toList.length == 1 ? toList.first : toList,
        cc: ccList,
        bcc: bccList,
        subject: _subjectController.text.trim(),
        text: _bodyController.text,
        inReplyTo: widget.inReplyTo,
        references: widget.references,
        attachments: attachmentsPayload.isNotEmpty ? attachmentsPayload : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email dispatched successfully!'),
            backgroundColor: WhatsAppTheme.primaryGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send email: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.primaryGreen,
        title: const Text('Compose Business Email', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Attach Files',
            icon: const Icon(Icons.attach_file),
            onPressed: _pickAttachment,
          ),
          IconButton(
            tooltip: 'Draft with Gemini AI',
            icon: _isGeneratingAi
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome),
            onPressed: _isGeneratingAi ? null : _promptAiDraft,
          ),
          IconButton(
            tooltip: 'Send Email',
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            onPressed: _isSending ? null : _sendEmail,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Sender Account selector (if accounts > 1)
            if (widget.accounts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    const Text('From: ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _currentAccountId,
                          isDense: true,
                          isExpanded: true,
                          items: widget.accounts.map((acc) {
                            return DropdownMenuItem<String>(
                              value: acc['id']?.toString(),
                              child: Text(
                                '${acc['name']} <${acc['email']}>',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _currentAccountId = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // To field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  const Text('To: ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _toController,
                      decoration: const InputDecoration(
                        hintText: 'recipient@company.com',
                        border: InputBorder.none,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Recipient is required' : null,
                    ),
                  ),
                  IconButton(
                    icon: Icon(_showCcBcc ? Icons.expand_less : Icons.expand_more, size: 20),
                    onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
                    tooltip: 'Show Cc/Bcc',
                  ),
                ],
              ),
            ),

            // Cc & Bcc collapsible fields
            if (_showCcBcc) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    const Text('Cc: ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _ccController,
                        decoration: const InputDecoration(
                          hintText: 'colleague@company.com',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    const Text('Bcc: ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _bccController,
                        decoration: const InputDecoration(
                          hintText: 'archive@company.com',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Subject field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  const Text('Subject: ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _subjectController,
                      decoration: const InputDecoration(
                        hintText: 'Subject of your email',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Attached files row
            if (_attachments.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _attachments.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final att = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.darkBackground : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attachment, size: 16, color: WhatsAppTheme.primaryGreen),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                att['filename'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${_formatSize(att['size'] ?? 0)})',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _removeAttachment(idx),
                              child: const Icon(Icons.close, size: 16, color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Email Body
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: TextFormField(
                  controller: _bodyController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Compose your business email here...',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
