import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';

class EmailAccountSetupDialog extends StatefulWidget {
  final Map<String, dynamic>? initialAccount;

  const EmailAccountSetupDialog({super.key, this.initialAccount});

  @override
  State<EmailAccountSetupDialog> createState() => _EmailAccountSetupDialogState();
}

class _EmailAccountSetupDialogState extends State<EmailAccountSetupDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;

  // IMAP
  late TextEditingController _imapHostController;
  late TextEditingController _imapPortController;
  late TextEditingController _imapUserController;
  late TextEditingController _imapPassController;
  bool _imapSecure = true;

  // SMTP
  late TextEditingController _smtpHostController;
  late TextEditingController _smtpPortController;
  late TextEditingController _smtpUserController;
  late TextEditingController _smtpPassController;
  bool _smtpSecure = true;

  bool _sameSmtpCredentials = true;
  bool _isDefault = false;
  bool _obscureImapPass = true;
  bool _obscureSmtpPass = true;

  String _selectedPreset = 'custom'; // 'custom', 'gmail', 'outlook'

  bool _isTesting = false;
  String? _testResultSuccess;
  String? _testResultError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final acc = widget.initialAccount;

    _nameController = TextEditingController(text: acc?['name'] ?? '');
    _emailController = TextEditingController(text: acc?['email'] ?? '');

    _imapHostController = TextEditingController(text: acc?['imap']?['host'] ?? '');
    _imapPortController = TextEditingController(text: (acc?['imap']?['port'] ?? 993).toString());
    _imapUserController = TextEditingController(text: acc?['imap']?['user'] ?? '');
    _imapPassController = TextEditingController();
    _imapSecure = acc?['imap']?['secure'] ?? true;

    _smtpHostController = TextEditingController(text: acc?['smtp']?['host'] ?? '');
    _smtpPortController = TextEditingController(text: (acc?['smtp']?['port'] ?? 465).toString());
    _smtpUserController = TextEditingController(text: acc?['smtp']?['user'] ?? '');
    _smtpPassController = TextEditingController();
    _smtpSecure = acc?['smtp']?['secure'] ?? true;

    _isDefault = acc?['isDefault'] ?? false;

    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _nameController.dispose();
    _emailController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    _imapUserController.dispose();
    _imapPassController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPassController.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    final email = _emailController.text.trim();
    if (_selectedPreset == 'custom' && email.contains('@')) {
      final parts = email.split('@');
      if (parts.length == 2 && parts[1].isNotEmpty) {
        final domain = parts[1];
        if (_imapHostController.text.isEmpty || _imapHostController.text.startsWith('mail.')) {
          _imapHostController.text = 'mail.$domain';
        }
        if (_smtpHostController.text.isEmpty || _smtpHostController.text.startsWith('mail.')) {
          _smtpHostController.text = 'mail.$domain';
        }
      }
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset == 'gmail') {
        _imapHostController.text = 'imap.gmail.com';
        _imapPortController.text = '993';
        _imapSecure = true;
        _smtpHostController.text = 'smtp.gmail.com';
        _smtpPortController.text = '465';
        _smtpSecure = true;
      } else if (preset == 'outlook') {
        _imapHostController.text = 'outlook.office365.com';
        _imapPortController.text = '993';
        _imapSecure = true;
        _smtpHostController.text = 'smtp.office365.com';
        _smtpPortController.text = '587';
        _smtpSecure = false;
      } else if (preset == 'custom') {
        _onEmailChanged();
      }
    });
  }

  Map<String, dynamic> _buildAccountPayload() {
    final email = _emailController.text.trim();
    final imapUser = _imapUserController.text.trim().isNotEmpty
        ? _imapUserController.text.trim()
        : email;
    final smtpUser = _sameSmtpCredentials
        ? imapUser
        : (_smtpUserController.text.trim().isNotEmpty
            ? _smtpUserController.text.trim()
            : email);
    final smtpPass = _sameSmtpCredentials
        ? _imapPassController.text.trim()
        : _smtpPassController.text.trim();

    return {
      if (widget.initialAccount?['id'] != null) 'id': widget.initialAccount!['id'],
      'name': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : email.split('@')[0],
      'email': email,
      'isDefault': _isDefault,
      'imap': {
        'host': _imapHostController.text.trim(),
        'port': int.tryParse(_imapPortController.text.trim()) ?? 993,
        'secure': _imapSecure,
        'auth': {
          'user': imapUser,
          'pass': _imapPassController.text.trim(),
        },
      },
      'smtp': {
        'host': _smtpHostController.text.trim(),
        'port': int.tryParse(_smtpPortController.text.trim()) ?? 465,
        'secure': _smtpSecure,
        'auth': {
          'user': smtpUser,
          'pass': smtpPass,
        },
      },
    };
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResultSuccess = null;
      _testResultError = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final payload = _buildAccountPayload();
      final res = await auth.api.testEmailAccount(payload);
      if (res['success'] == true) {
        setState(() {
          _testResultSuccess = res['message'] ?? 'IMAP & SMTP connection verified successfully!';
        });
      } else {
        setState(() {
          _testResultError = res['message'] ?? 'Connection test failed. Please verify credentials.';
        });
      }
    } catch (e) {
      setState(() {
        _testResultError = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final payload = _buildAccountPayload();
      final res = await auth.api.saveEmailAccount(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email account saved successfully!'),
            backgroundColor: WhatsAppTheme.primaryGreen,
          ),
        );
        Navigator.pop(context, res['account'] ?? true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialAccount != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            backgroundColor: WhatsAppTheme.primaryGreen,
            title: Text(
              isEdit ? 'Edit Business Email' : 'Add Business Email',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Preset Selector
                const Text(
                  'Account Preset',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('cPanel / Business Mail'),
                      selected: _selectedPreset == 'custom',
                      onSelected: (_) => _applyPreset('custom'),
                      selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: _selectedPreset == 'custom' ? WhatsAppTheme.primaryGreen : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Google Workspace / Gmail'),
                      selected: _selectedPreset == 'gmail',
                      onSelected: (_) => _applyPreset('gmail'),
                      selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: _selectedPreset == 'gmail' ? WhatsAppTheme.primaryGreen : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Outlook / M365'),
                      selected: _selectedPreset == 'outlook',
                      onSelected: (_) => _applyPreset('outlook'),
                      selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: _selectedPreset == 'outlook' ? WhatsAppTheme.primaryGreen : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Sender Info
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          hintText: 'user@company.com',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          hintText: 'Support Team',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // IMAP Configuration Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.inbox, size: 20, color: WhatsAppTheme.primaryGreen),
                          SizedBox(width: 8),
                          Text(
                            'Incoming Mail Server (IMAP)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: TextFormField(
                              controller: _imapHostController,
                              decoration: const InputDecoration(
                                labelText: 'IMAP Server *',
                                hintText: 'mail.yourdomain.com',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Server is required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _imapPortController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                hintText: '993',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _imapUserController,
                              decoration: const InputDecoration(
                                labelText: 'IMAP Username',
                                hintText: 'Defaults to full email',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Checkbox(
                            value: _imapSecure,
                            activeColor: WhatsAppTheme.primaryGreen,
                            onChanged: (v) => setState(() => _imapSecure = v ?? true),
                          ),
                          const Text('SSL/TLS', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _imapPassController,
                        obscureText: _obscureImapPass,
                        decoration: InputDecoration(
                          labelText: isEdit ? 'Password (leave blank to keep current)' : 'Password *',
                          hintText: '••••••••',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureImapPass ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscureImapPass = !_obscureImapPass),
                          ),
                        ),
                        validator: (v) {
                          if (!isEdit && (v == null || v.trim().isEmpty)) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SMTP Configuration Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.send_rounded, size: 20, color: WhatsAppTheme.primaryGreen),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Outgoing Mail Server (SMTP)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Switch(
                            value: _sameSmtpCredentials,
                            activeColor: WhatsAppTheme.primaryGreen,
                            onChanged: (v) => setState(() => _sameSmtpCredentials = v),
                          ),
                          const Text('Same Auth', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: TextFormField(
                              controller: _smtpHostController,
                              decoration: const InputDecoration(
                                labelText: 'SMTP Server *',
                                hintText: 'mail.yourdomain.com',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'SMTP server is required' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _smtpPortController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                hintText: '465',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _smtpSecure,
                            activeColor: WhatsAppTheme.primaryGreen,
                            onChanged: (v) => setState(() => _smtpSecure = v ?? true),
                          ),
                          const Text('SSL/TLS', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      if (!_sameSmtpCredentials) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _smtpUserController,
                          decoration: const InputDecoration(
                            labelText: 'SMTP Username',
                            hintText: 'Defaults to email',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _smtpPassController,
                          obscureText: _obscureSmtpPass,
                          decoration: InputDecoration(
                            labelText: 'SMTP Password',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureSmtpPass ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscureSmtpPass = !_obscureSmtpPass),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Set as Default switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set as Default Email Account', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Automatically selected when viewing inbox and drafting emails', style: TextStyle(fontSize: 12)),
                  value: _isDefault,
                  activeColor: WhatsAppTheme.primaryGreen,
                  onChanged: (v) => setState(() => _isDefault = v),
                ),

                // Diagnostics Display
                if (_testResultSuccess != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _testResultSuccess!,
                            style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_testResultError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _testResultError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: WhatsAppTheme.primaryGreen),
                        ),
                        onPressed: _isTesting || _isSaving ? null : _testConnection,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check, color: WhatsAppTheme.primaryGreen),
                        label: Text(
                          _isTesting ? 'Testing...' : 'Test Connection',
                          style: const TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WhatsAppTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isTesting || _isSaving ? null : _saveAccount,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Account',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
