import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _broadcasts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBroadcasts();
  }

  Future<void> _loadBroadcasts() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      final list = await auth.api.getUserBroadcasts();
      if (mounted) {
        setState(() {
          _broadcasts = list;
          _isLoading = false;
        });

        // Mark all as seen
        for (final b in list) {
          if (b['seen'] != true) {
            auth.api.markBroadcastSeen(b['id']?.toString() ?? '');
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acknowledge(String id) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await auth.api.acknowledgeBroadcast(id);
      if (mounted) {
        setState(() {
          final idx = _broadcasts.indexWhere((b) => b['id'] == id);
          if (idx != -1) {
            _broadcasts[idx]['acknowledged'] = true;
            _broadcasts[idx]['acknowledgedAt'] = DateTime.now().toIso8601String();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message acknowledged successfully!'),
            backgroundColor: WhatsAppTheme.primaryGreen,
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
  }

  void _showReplyDialog(String id, String title) {
    final replyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Reply to: $title'),
        content: TextField(
          controller: replyCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Type your reply to Admin...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
            onPressed: () async {
              final text = replyCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dlgCtx);
              final auth = Provider.of<AuthService>(context, listen: false);
              try {
                await auth.api.replyToBroadcast(id, text);
                if (mounted) {
                  setState(() {
                    final idx = _broadcasts.indexWhere((b) => b['id'] == id);
                    if (idx != -1) {
                      _broadcasts[idx]['reply'] = text;
                      _broadcasts[idx]['repliedAt'] = DateTime.now().toIso8601String();
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reply sent to Admin!'),
                      backgroundColor: WhatsAppTheme.primaryGreen,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reply failed: $e')));
                }
              }
            },
            child: const Text('Send Reply'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, "0")}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? WhatsAppTheme.bgDark : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Admin Notices & Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBroadcasts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
          : _broadcasts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 14),
                      const Text(
                        'No notifications from Admin',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _broadcasts.length,
                  itemBuilder: (ctx, i) {
                    final b = _broadcasts[i];
                    final id = b['id']?.toString() ?? '';
                    final title = b['title']?.toString() ?? 'Notice';
                    final body = b['body']?.toString() ?? '';
                    final requireAck = b['requireAck'] == true;
                    final allowReply = b['allowReply'] == true;
                    final isAcked = b['acknowledged'] == true;
                    final ackAt = b['acknowledgedAt']?.toString();
                    final isUrgent = b['urgency'] == 'urgent';
                    final reply = b['reply']?.toString();
                    final createdAt = b['createdAtIso']?.toString();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: isUrgent ? const BorderSide(color: Colors.red, width: 1.5) : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isUrgent ? Colors.red.shade100 : WhatsAppTheme.primaryGreen.withOpacity(0.15),
                                  child: Icon(
                                    isUrgent ? Icons.warning_amber_rounded : Icons.campaign_rounded,
                                    color: isUrgent ? Colors.red : WhatsAppTheme.primaryGreen,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      if (createdAt != null)
                                        Text(
                                          _formatDate(createdAt),
                                          style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isUrgent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'URGENT',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 22),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.5,
                                color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF111B21),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Acknowledgment & Status
                            if (requireAck)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isAcked ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isAcked ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isAcked ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                      color: isAcked ? Colors.green : Colors.orange.shade800,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isAcked ? 'Acknowledged on ${_formatDate(ackAt)}' : 'Acknowledgment required',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                          color: isAcked ? Colors.green.shade800 : Colors.orange.shade900,
                                        ),
                                      ),
                                    ),
                                    if (!isAcked)
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: WhatsAppTheme.primaryGreen,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                        onPressed: () => _acknowledge(id),
                                        child: const Text('Acknowledge', style: TextStyle(fontSize: 12, color: Colors.white)),
                                      ),
                                  ],
                                ),
                              ),

                            // Reply display / composer
                            if (reply != null && reply.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.purple.withOpacity(0.15) : Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Your Reply:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple)),
                                    const SizedBox(height: 2),
                                    Text(reply, style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              )
                            else if (allowReply)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.reply_rounded, size: 16),
                                  label: const Text('Reply to Admin'),
                                  onPressed: () => _showReplyDialog(id, title),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
