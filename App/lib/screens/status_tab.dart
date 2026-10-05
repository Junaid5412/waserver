import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/permissions.dart';
import '../models/status_model.dart';
import '../services/auth_service.dart';

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
                      // Post status
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthService>(context);
    final canViewSeen = UserPermissions.canViewStatus(auth.currentUser);

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
              const Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen),
              ))
            else if (_statuses.isEmpty)
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
              ..._statuses.map((st) {
                final timeStr = st.createdAt != null
                    ? DateFormat('HH:mm, dd MMM').format(st.createdAt!.toLocal())
                    : '';

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: WhatsAppTheme.accentGreen, width: 2.2),
                    ),
                    child: CircleAvatar(
                      radius: 23,
                      backgroundColor: WhatsAppTheme.tealGreen.withOpacity(0.15),
                      child: Text(
                        st.name.isNotEmpty ? st.name[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen),
                      ),
                    ),
                  ),
                  title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(st.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          // If user has permission, show viewer seen count
                          if (canViewSeen && st.viewers.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.remove_red_eye_outlined, size: 13, color: WhatsAppTheme.primaryGreen),
                            const SizedBox(width: 3),
                            Text('${st.viewers.length} views', style: const TextStyle(fontSize: 11, color: WhatsAppTheme.primaryGreen)),
                          ],
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    // Show full screen status preview
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: isDark ? WhatsAppTheme.bgDark : Colors.white,
                        title: Text(st.name),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: WhatsAppTheme.tealGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(st.text, style: const TextStyle(fontSize: 17)),
                            ),
                            const SizedBox(height: 12),
                            Text('Posted: $timeStr', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            if (canViewSeen) ...[
                              const SizedBox(height: 10),
                              const Divider(),
                              const Text('Viewers List (Admin Allowed):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(st.viewers.isNotEmpty ? st.viewers.join(', ') : 'No views recorded yet',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
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
