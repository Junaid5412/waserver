import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/theme.dart';
import '../config/permissions.dart';
import '../models/status_model.dart';
import '../services/auth_service.dart';

class SegmentedCirclePainter extends CustomPainter {
  final int count;
  final Color color;
  final double strokeWidth;

  SegmentedCirclePainter({
    required this.count,
    required this.color,
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    if (count <= 1) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final double gapAngle = 0.08;
    final double sweepAngle = (2 * math.pi / count) - gapAngle;

    for (int i = 0; i < count; i++) {
      final double startAngle = -math.pi / 2 + i * (sweepAngle + gapAngle) + (gapAngle / 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SegmentedCirclePainter oldDelegate) =>
      oldDelegate.count != count || oldDelegate.color != color;
}

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  List<StatusModel> _statuses = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final inst = auth.selectedInstance;
    if (inst == null) return;

    setState(() => _isLoading = true);
    try {
      final list = await auth.api.getStatuses(inst.id);
      if (mounted) {
        setState(() {
          _statuses = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddStatusDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Status Update'),
          content: TextField(
            controller: textCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Type a status update...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final txt = textCtrl.text.trim();
                if (txt.isNotEmpty) {
                  Navigator.pop(ctx);
                  final auth = Provider.of<AuthService>(context, listen: false);
                  final inst = auth.selectedInstance;
                  if (inst != null) {
                    try {
                      await auth.api.postStatus(inst.id, txt, ['broadcast']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status update posted!')),
                      );
                      _loadStatuses();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: WhatsAppTheme.primaryGreen),
              child: const Text('Post', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _openMultiStatusViewer(BuildContext context, String contactName, List<StatusModel> items, bool canViewSeen) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instanceId = auth.selectedInstance?.id ?? '';
    final headers = auth.api.authHeaders;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MultiStoryViewer(
          contactName: contactName,
          statuses: items,
          canViewSeen: canViewSeen,
          instanceId: instanceId,
          headers: headers,
          onMarkRead: (waId) {
            auth.api.markMessageAsRead(instanceId, waId);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final canViewSeen = UserPermissions.canViewStatus(auth.currentUser);

    // Group multiple statuses by contact JID or name
    final Map<String, List<StatusModel>> grouped = {};
    for (final st in _statuses) {
      final key = st.participantJid.isNotEmpty
          ? st.participantJid
          : (st.name.isNotEmpty ? st.name : 'Unknown');
      grouped.putIfAbsent(key, () => []).add(st);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadStatuses,
        color: WhatsAppTheme.primaryGreen,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // My Status Section
            ListTile(
              leading: Stack(
                children: [
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: WhatsAppTheme.accentGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
              title: const Text('My status', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Tap to add status update'),
              onTap: _showAddStatusDialog,
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Recent updates',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: WhatsAppTheme.grayTick,
                ),
              ),
            ),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
                ),
              )
            else if (grouped.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'No recent status updates',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              ...grouped.entries.map((entry) {
                final list = entry.value;
                final latest = list.last;
                final count = list.length;
                final contactName = latest.name.isNotEmpty ? latest.name : 'Contact';
                final timeStr = latest.createdAt != null
                    ? DateFormat('HH:mm').format(latest.createdAt!.toLocal())
                    : '';

                return ListTile(
                  leading: CustomPaint(
                    painter: SegmentedCirclePainter(
                      count: count,
                      color: WhatsAppTheme.accentGreen,
                      strokeWidth: 2.8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: WhatsAppTheme.tealGreen.withOpacity(0.15),
                        child: Text(
                          contactName.isNotEmpty ? contactName[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen),
                        ),
                      ),
                    ),
                  ),
                  title: Text(contactName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    count > 1
                        ? '$count updates · $timeStr'
                        : (latest.hasMedia || latest.type == 'image'
                            ? '📷 Photo • $timeStr'
                            : (latest.text.isNotEmpty ? latest.text : 'Status update • $timeStr')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  onTap: () => _openMultiStatusViewer(context, contactName, list, canViewSeen),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppTheme.fabGreen,
        onPressed: _showAddStatusDialog,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}

class _MultiStoryViewer extends StatefulWidget {
  final String contactName;
  final List<StatusModel> statuses;
  final bool canViewSeen;
  final String instanceId;
  final Map<String, String> headers;
  final Function(String waId)? onMarkRead;

  const _MultiStoryViewer({
    required this.contactName,
    required this.statuses,
    required this.canViewSeen,
    required this.instanceId,
    required this.headers,
    this.onMarkRead,
  });

  @override
  State<_MultiStoryViewer> createState() => _MultiStoryViewerState();
}

class _MultiStoryViewerState extends State<_MultiStoryViewer> {
  int _currentIndex = 0;

  void _next() {
    if (_currentIndex < widget.statuses.length - 1) {
      setState(() => _currentIndex++);
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _downloadStatus(StatusModel st) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Status media saved to device gallery!'),
        backgroundColor: WhatsAppTheme.primaryGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _markAsRead(StatusModel st) {
    widget.onMarkRead?.call(st.waId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Status marked as viewed'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.statuses[_currentIndex];
    final timeStr = current.createdAt != null
        ? DateFormat('HH:mm, dd MMM').format(current.createdAt!.toLocal())
        : '';

    final isMedia = current.hasMedia ||
        current.type == 'image' ||
        current.type == 'video' ||
        current.mimetype?.startsWith('image/') == true;

    final mediaUrl = '${ApiConfig.baseUrl}/api/instances/${widget.instanceId}/inbox/${current.waId}/media?inline=1';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Media or Text Content
            Positioned.fill(
              child: isMedia
                  ? Image.network(
                      mediaUrl,
                      headers: widget.headers,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
                        );
                      },
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                            const SizedBox(height: 12),
                            Text(
                              current.text.isNotEmpty ? current.text : 'Media unavailable or expired',
                              style: const TextStyle(color: Colors.white70, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16),
                          ],
                        ),
                        child: Text(
                          current.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
            ),

            // Caption overlay for media statuses
            if (isMedia && current.text.isNotEmpty)
              Positioned(
                bottom: widget.canViewSeen ? 70 : 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    current.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),

            // Touch navigation (left half: prev, right half: next)
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _prev,
                      behavior: HitTestBehavior.translucent,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _next,
                      behavior: HitTestBehavior.translucent,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),

            // Top Status Segments Progress Bars
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.statuses.length, (idx) {
                  final isActive = idx == _currentIndex;
                  final isDone = idx < _currentIndex;

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDone || isActive ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Top Header: Contact Name, Time, Download, Read & Close Buttons
            Positioned(
              top: 24,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: WhatsAppTheme.primaryGreen,
                    child: Text(
                      widget.contactName.isNotEmpty ? widget.contactName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.contactName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Download button
                  IconButton(
                    icon: const Icon(Icons.file_download_rounded, color: Colors.white),
                    tooltip: 'Download Status Media',
                    onPressed: () => _downloadStatus(current),
                  ),

                  // Read button
                  IconButton(
                    icon: const Icon(Icons.done_all_rounded, color: WhatsAppTheme.blueTick),
                    tooltip: 'Mark as Read',
                    onPressed: () => _markAsRead(current),
                  ),

                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Bottom Admin Views Panel (if allowed)
            if (widget.canViewSeen)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.remove_red_eye_outlined, color: WhatsAppTheme.accentGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${current.viewers.length} views',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      if (current.viewers.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${current.viewers.join(", ")})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
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
