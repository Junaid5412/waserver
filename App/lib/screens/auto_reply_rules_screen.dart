import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

/// Lists, creates, enables/disables and deletes the auto-reply rules of one instance.
/// Backed by GET/POST /api/instances/:id/rules and PUT/DELETE /api/instances/:id/rules/:rule.
class AutoReplyRulesScreen extends StatefulWidget {
  final String instanceId;
  final String? instanceName;

  const AutoReplyRulesScreen({
    super.key,
    required this.instanceId,
    this.instanceName,
  });

  @override
  State<AutoReplyRulesScreen> createState() => _AutoReplyRulesScreenState();
}

class _AutoReplyRulesScreenState extends State<AutoReplyRulesScreen> {
  List<Map<String, dynamic>> _rules = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _busyRuleIds = {};

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  String _cleanError(Object e) => e.toString().replaceAll('Exception:', '').trim();

  bool _isEnabled(Map<String, dynamic> rule) {
    if (rule['enabled'] is bool) return rule['enabled'] as bool;
    return rule['status']?.toString() != 'disabled';
  }

  Future<void> _loadRules() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final list = await auth.api.getAutoReplyRules(widget.instanceId);
      if (!mounted) return;
      setState(() {
        _rules = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRule(Map<String, dynamic> rule, bool enabled) async {
    final id = rule['id']?.toString() ?? '';
    if (id.isEmpty || _busyRuleIds.contains(id)) return;
    final previous = _isEnabled(rule);
    setState(() {
      _busyRuleIds.add(id);
      rule['enabled'] = enabled;
      rule['status'] = enabled ? 'enabled' : 'disabled';
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.api.updateAutoReplyRule(widget.instanceId, id, enabled: enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        rule['enabled'] = previous;
        rule['status'] = previous ? 'enabled' : 'disabled';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update rule: ${_cleanError(e)}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(id));
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    final id = rule['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Rule?'),
        content: Text('Delete the auto-reply rule "${rule['name'] ?? ''}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyRuleIds.add(id));
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.api.deleteAutoReplyRule(widget.instanceId, id);
      if (!mounted) return;
      setState(() => _rules.removeWhere((r) => r['id']?.toString() == id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rule deleted'), backgroundColor: WhatsAppTheme.primaryGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete rule: ${_cleanError(e)}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(id));
    }
  }

  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RuleFormSheet(instanceId: widget.instanceId),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-reply rule created'), backgroundColor: WhatsAppTheme.primaryGreen),
      );
      _loadRules();
    }
  }

  String _matchLabel(Map<String, dynamic> rule) {
    final match = rule['match']?.toString() ?? 'any';
    final keyword = rule['keyword']?.toString() ?? '';
    switch (match) {
      case 'exact':
        return 'Exact match: "$keyword"';
      case 'contains':
        return 'Contains: "$keyword"';
      default:
        return 'Any incoming message';
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadRules, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_rules.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRules,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(Icons.reply_all_rounded, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Center(
              child: Text('No auto-reply rules yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            SizedBox(height: 6),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Tap "New Rule" to reply automatically to messages that match a keyword.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRules,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _rules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final rule = _rules[index];
          final id = rule['id']?.toString() ?? '';
          final enabled = _isEnabled(rule);
          final busy = _busyRuleIds.contains(id);
          final cooldown = rule['cooldownSeconds'];
          final reply = rule['reply']?.toString() ?? '';

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rule['name']?.toString() ?? 'Rule',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Switch(
                        value: enabled,
                        activeColor: WhatsAppTheme.primaryGreen,
                        onChanged: busy ? null : (v) => _toggleRule(rule, v),
                      ),
                      IconButton(
                        tooltip: 'Delete rule',
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: busy ? null : () => _deleteRule(rule),
                      ),
                    ],
                  ),
                  Text(_matchLabel(rule), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Text(
                    reply,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cooldown: ${cooldown ?? 60}s · ${rule['stopAfterMatch'] == false ? 'Continues to other rules' : 'Stops after match'} · ${enabled ? 'Enabled' : 'Disabled'}',
                    style: TextStyle(fontSize: 11, color: enabled ? WhatsAppTheme.primaryGreen : Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.primaryGreen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auto-Reply Rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (widget.instanceName != null && widget.instanceName!.isNotEmpty)
              Text(widget.instanceName!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadRules,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: WhatsAppTheme.primaryGreen,
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Rule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// Minimal create form matching the server schema:
/// name (1-60), match (any|exact|contains), keyword (<=200, required unless match is any),
/// reply (1-20000), cooldownSeconds (0-86400), enabled, stopAfterMatch.
class _RuleFormSheet extends StatefulWidget {
  final String instanceId;

  const _RuleFormSheet({required this.instanceId});

  @override
  State<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends State<_RuleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _keywordCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _cooldownCtrl = TextEditingController(text: '60');
  String _match = 'contains';
  bool _stopAfterMatch = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keywordCtrl.dispose();
    _replyCtrl.dispose();
    _cooldownCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.api.createAutoReplyRule(
        widget.instanceId,
        name: _nameCtrl.text.trim(),
        match: _match,
        keyword: _match == 'any' ? '' : _keywordCtrl.text.trim(),
        reply: _replyCtrl.text.trim(),
        cooldownSeconds: int.tryParse(_cooldownCtrl.text.trim()) ?? 60,
        enabled: true,
        stopAfterMatch: _stopAfterMatch,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('New Auto-Reply Rule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Rule name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _match,
                decoration: const InputDecoration(
                  labelText: 'When a message',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'contains', child: Text('Contains the keyword')),
                  DropdownMenuItem(value: 'exact', child: Text('Exactly matches the keyword')),
                  DropdownMenuItem(value: 'any', child: Text('Is anything (reply to every message)')),
                ],
                onChanged: _isSaving ? null : (v) => setState(() => _match = v ?? 'contains'),
              ),
              if (_match != 'any') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _keywordCtrl,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Keyword',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (_match != 'any' && (v == null || v.trim().isEmpty)) ? 'Keyword is required' : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _replyCtrl,
                minLines: 3,
                maxLines: 6,
                maxLength: 20000,
                decoration: const InputDecoration(
                  labelText: 'Reply message',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the reply text' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cooldownCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cooldown per chat (seconds)',
                  helperText: '0 - 86400. Prevents replying to the same chat repeatedly.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 0 || n > 86400) return 'Enter a whole number from 0 to 86400';
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: WhatsAppTheme.primaryGreen,
                title: const Text('Stop after this rule matches'),
                subtitle: const Text('Do not evaluate further rules for the same message'),
                value: _stopAfterMatch,
                onChanged: _isSaving ? null : (v) => setState(() => _stopAfterMatch = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WhatsAppTheme.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check, color: Colors.white),
                  label: const Text('Create Rule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
