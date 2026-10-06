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

  // Gemini AI Key & Model
  late TextEditingController _geminiKeyController;
  String _selectedGeminiModel = 'gemini-3.1-pro';
  bool _obscureGeminiKey = true;

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

    _geminiKeyController = TextEditingController(text: acc?['geminiKey'] ?? '');
    _selectedGeminiModel = acc?['geminiModel'] ?? 'gemini-3.1-pro';

    _isDefault = acc?['isDefault'] ?? false;

    _emailController.addListener(_onEmailChanged);
    _loadInitialGeminiKey();
  }

  Future<void> _loadInitialGeminiKey() async {
    if (_geminiKeyController.text.isEmpty) {
      try {
        final auth = Provider.of<AuthService>(context, listen: false);
        final data = await auth.api.getAdminGeminiData();
        final keys = List<String>.from(data['keys'] ?? []);
        if (keys.isNotEmpty && mounted) {
          setState(() {
            _geminiKeyController.text = keys.first;
            if (data['model'] != null) {
              _selectedGeminiModel = data['model'];
            }
          });
        }
      } catch (_) {}
    }
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
    _geminiKeyController.dispose();
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
      'geminiKey': _geminiKeyController.text.trim(),
      'geminiModel': _selectedGeminiModel,
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

      // If user provided a Gemini key, immediately save to database settings & local storage
      final gemKey = _geminiKeyController.text.trim();
      if (gemKey.length > 10) {
        await auth.api.addAdminGeminiKey(gemKey);
        await auth.api.setAdminGeminiModel(_selectedGeminiModel);
      }

      final res = await auth.api.saveEmailAccount(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business email account saved successfully!'),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            backgroundColor: WhatsAppTheme.primaryGreen,
            leading: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 24),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit Business Email' : 'Add Business Email Account',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Text(
                  'Full IMAP/SMTP corporate mail sync & AI assistant',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // Preset Selection Tabs
                const Text(
                  'Choose Provider Preset',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildPresetCard(
                        id: 'custom',
                        icon: Icons.business_rounded,
                        title: 'cPanel / Domain',
                        subtitle: 'Recommended',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPresetCard(
                        id: 'gmail',
                        icon: Icons.mail_outline_rounded,
                        title: 'Google Workspace',
                        subtitle: 'Gmail App Pass',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPresetCard(
                        id: 'outlook',
                        icon: Icons.laptop_windows_rounded,
                        title: 'Outlook / M365',
                        subtitle: 'Microsoft 365',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Account Credentials Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_pin_rounded, size: 18, color: WhatsAppTheme.primaryGreen),
                          SizedBox(width: 8),
                          Text('Account Identity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Business Email *',
                                hintText: 'contact@yourdomain.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Email is required';
                                if (!v.contains('@')) return 'Invalid email address';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Display Name',
                                hintText: 'HostZelon Support',
                                prefixIcon: Icon(Icons.badge_outlined, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // IMAP Configuration Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inbox_rounded, size: 18, color: WhatsAppTheme.primaryGreen),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Incoming Mail Server (IMAP)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          FilterChip(
                            label: Text(_imapSecure ? 'SSL/TLS' : 'STARTTLS', style: const TextStyle(fontSize: 11)),
                            selected: _imapSecure,
                            selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.18),
                            onSelected: (v) => setState(() => _imapSecure = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                                labelText: 'IMAP Username (optional)',
                                hintText: 'Defaults to full email',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _imapPassController,
                              obscureText: _obscureImapPass,
                              decoration: InputDecoration(
                                labelText: isEdit ? 'Password (keep blank)' : 'Password *',
                                hintText: '••••••••',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureImapPass ? Icons.visibility : Icons.visibility_off, size: 18),
                                  onPressed: () => setState(() => _obscureImapPass = !_obscureImapPass),
                                ),
                              ),
                              validator: (v) {
                                if (!isEdit && (v == null || v.trim().isEmpty)) {
                                  return 'Password required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // SMTP Configuration Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.send_rounded, size: 18, color: WhatsAppTheme.primaryGreen),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Outgoing Mail Server (SMTP)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          FilterChip(
                            label: Text(_smtpSecure ? 'SSL (465)' : 'TLS (587)', style: const TextStyle(fontSize: 11)),
                            selected: _smtpSecure,
                            selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.18),
                            onSelected: (v) => setState(() => _smtpSecure = v),
                          ),
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
                              validator: (v) => v == null || v.trim().isEmpty ? 'Server is required' : null,
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Use same authentication credentials as IMAP', style: TextStyle(fontSize: 13)),
                        value: _sameSmtpCredentials,
                        activeColor: WhatsAppTheme.primaryGreen,
                        onChanged: (v) => setState(() => _sameSmtpCredentials = v),
                      ),
                      if (!_sameSmtpCredentials) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _smtpUserController,
                                decoration: const InputDecoration(
                                  labelText: 'SMTP Username',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _smtpPassController,
                                obscureText: _obscureSmtpPass,
                                decoration: InputDecoration(
                                  labelText: 'SMTP Password',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureSmtpPass ? Icons.visibility : Icons.visibility_off, size: 18),
                                    onPressed: () => setState(() => _obscureSmtpPass = !_obscureSmtpPass),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Gemini AI Assistant Settings Card (REQUESTED)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WhatsAppTheme.primaryGreen.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WhatsAppTheme.primaryGreen.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: WhatsAppTheme.primaryGreen.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.auto_awesome, color: WhatsAppTheme.primaryGreen, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gemini AI Assistant (Smart Email Reply)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Saved securely to database to power instant email replies',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _geminiKeyController,
                        obscureText: _obscureGeminiKey,
                        decoration: InputDecoration(
                          labelText: 'Gemini API Key (Optional / Saved to DB)',
                          hintText: 'AIzaSy...',
                          prefixIcon: const Icon(Icons.key_rounded, size: 18),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(_obscureGeminiKey ? Icons.visibility : Icons.visibility_off, size: 18),
                            onPressed: () => setState(() => _obscureGeminiKey = !_obscureGeminiKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('AI Model: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedGeminiModel,
                              isDense: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'gemini-3.1-pro', child: Text('gemini-3.1-pro (Executive)')),
                                DropdownMenuItem(value: 'gemini-3.8-flash', child: Text('gemini-3.8-flash (Fastest)')),
                                DropdownMenuItem(value: 'gemini-3.6-flash', child: Text('gemini-3.6-flash (Balanced)')),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedGeminiModel = v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Set as Default switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Set as Default Email Mailbox', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Selected automatically on opening the Email screen', style: TextStyle(fontSize: 11)),
                  value: _isDefault,
                  activeColor: WhatsAppTheme.primaryGreen,
                  onChanged: (v) => setState(() => _isDefault = v),
                ),

                // Diagnostics Display
                if (_testResultSuccess != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _testResultSuccess!,
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_testResultError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _testResultError!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // Footer Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: const BorderSide(color: WhatsAppTheme.primaryGreen),
                        ),
                        onPressed: _isTesting || _isSaving ? null : _testConnection,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check_rounded, color: WhatsAppTheme.primaryGreen, size: 18),
                        label: Text(
                          _isTesting ? 'Verifying...' : 'Test Connection',
                          style: const TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WhatsAppTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isTesting || _isSaving ? null : _saveAccount,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save & Connect',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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

  Widget _buildPresetCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSel = _selectedPreset == id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => _applyPreset(id),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSel
              ? WhatsAppTheme.primaryGreen.withOpacity(0.12)
              : (isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? WhatsAppTheme.primaryGreen : Colors.grey.withOpacity(0.2),
            width: isSel ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSel ? WhatsAppTheme.primaryGreen : Colors.grey,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                color: isSel ? WhatsAppTheme.primaryGreen : null,
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: isSel ? WhatsAppTheme.primaryGreen : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
