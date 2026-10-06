import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'email_account_setup_dialog.dart';
import 'email_composer_screen.dart';
import 'email_detail_screen.dart';

class EmailMainScreen extends StatefulWidget {
  const EmailMainScreen({super.key});

  @override
  State<EmailMainScreen> createState() => _EmailMainScreenState();
}

class _EmailMainScreenState extends State<EmailMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoadingAccounts = true;
  List<Map<String, dynamic>> _accounts = [];
  Map<String, dynamic>? _selectedAccount;

  bool _isLoadingMessages = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _messages = [];
  int _totalMessages = 0;
  int _currentPage = 1;
  final int _pageSize = 25;
  bool _hasMore = false;

  String _currentFolder = 'INBOX';
  List<Map<String, dynamic>> _folders = [];
  String _selectedFilter = 'all'; // 'all', 'unread', 'starred'

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts({String? selectAccountId}) async {
    setState(() => _isLoadingAccounts = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final list = await auth.api.getEmailAccounts();
      if (mounted) {
        setState(() {
          _accounts = list;
          if (list.isNotEmpty) {
            if (selectAccountId != null) {
              _selectedAccount = list.firstWhere(
                (a) => a['id']?.toString() == selectAccountId,
                orElse: () => list.first,
              );
            } else {
              _selectedAccount = list.firstWhere(
                (a) => a['isDefault'] == true,
                orElse: () => list.first,
              );
            }
          } else {
            _selectedAccount = null;
          }
          _isLoadingAccounts = false;
        });

        if (_selectedAccount != null) {
          _loadFolders();
          _loadMessages(reset: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accounts = [];
          _selectedAccount = null;
          _isLoadingAccounts = false;
        });
      }
    }
  }

  Future<void> _loadFolders() async {
    if (_selectedAccount == null) return;
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final res = await auth.api.getEmailFolders(accountId: _selectedAccount!['id']?.toString());
      final folderList = (res['folders'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      if (mounted) {
        setState(() {
          _folders = folderList;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages({bool reset = false}) async {
    if (_selectedAccount == null) return;

    if (reset) {
      _currentPage = 1;
      _messages.clear();
      setState(() {
        _isLoadingMessages = true;
        _errorMessage = null;
      });
    }

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final res = await auth.api.getEmailMessages(
        accountId: _selectedAccount!['id']?.toString(),
        folder: _currentFolder,
        page: _currentPage,
        limit: _pageSize,
        search: _searchController.text.trim(),
        filter: _selectedFilter,
      );

      final msgList = (res['messages'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      final total = int.tryParse(res['total']?.toString() ?? '0') ?? 0;
      final totalPages = int.tryParse(res['totalPages']?.toString() ?? '1') ?? 1;

      if (mounted) {
        setState(() {
          if (reset) {
            _messages = msgList;
          } else {
            _messages.addAll(msgList);
          }
          _totalMessages = total;
          _hasMore = _currentPage < totalPages;
          _isLoadingMessages = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
          _isLoadingMessages = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadMessages(reset: true);
    });
  }

  Future<void> _toggleStar(Map<String, dynamic> msg) async {
    final uid = msg['uid']?.toString() ?? '';
    final curStar = msg['flagged'] == true;
    final newStar = !curStar;

    setState(() {
      msg['flagged'] = newStar;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.api.flagEmailMessage(
        uid,
        accountId: _selectedAccount?['id']?.toString(),
        folder: _currentFolder,
        star: newStar,
      );
    } catch (_) {
      if (mounted) setState(() => msg['flagged'] = curStar);
    }
  }

  Future<void> _openAccountSetup([Map<String, dynamic>? accountToEdit]) async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailAccountSetupDialog(initialAccount: accountToEdit),
    );
    if (result != null) {
      _loadAccounts(selectAccountId: result is Map ? result['id']?.toString() : null);
    }
  }

  Future<void> _openManageAccountsSheet() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Business Email Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('No accounts configured yet')),
                  )
                else
                  ..._accounts.map((acc) {
                    final isSel = acc['id'] == _selectedAccount?['id'];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isSel ? WhatsAppTheme.primaryGreen : Colors.grey.shade400,
                        child: Text(
                          (acc['name']?[0] ?? acc['email']?[0] ?? 'E').toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(acc['name'] ?? acc['email'], style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(acc['email'] ?? '', style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openAccountSetup(acc);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            onPressed: () async {
                              final auth = Provider.of<AuthService>(context, listen: false);
                              await auth.api.deleteEmailAccount(acc['id']);
                              Navigator.pop(ctx);
                              _loadAccounts();
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        setState(() => _selectedAccount = acc);
                        Navigator.pop(ctx);
                        _loadFolders();
                        _loadMessages(reset: true);
                      },
                    );
                  }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openAccountSetup();
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Add Business Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatMsgDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('h:mm a').format(dt);
      } else if (dt.year == now.year) {
        return DateFormat('MMM d').format(dt);
      } else {
        return DateFormat('MM/dd/yy').format(dt);
      }
    } catch (_) {
      return '';
    }
  }

  IconData _getFolderIcon(String name, String? specialUse) {
    final lower = (specialUse ?? name).toLowerCase();
    if (lower.contains('inbox')) return Icons.inbox;
    if (lower.contains('sent')) return Icons.send_outlined;
    if (lower.contains('draft')) return Icons.drafts_outlined;
    if (lower.contains('trash') || lower.contains('junk') || lower.contains('deleted') || lower.contains('bin')) {
      return Icons.delete_outline;
    }
    if (lower.contains('star') || lower.contains('flag')) return Icons.star_outline;
    if (lower.contains('outbox')) return Icons.outbox_outlined;
    if (lower.contains('archive') || lower.contains('all')) return Icons.archive_outlined;
    return Icons.folder_outlined;
  }

  String _formatFolderName(String name) {
    if (name.toUpperCase() == 'INBOX') return 'Inbox';
    return name.replaceAll(RegExp(r'^[^\w]+'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.primaryGreen,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search emails...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : GestureDetector(
                onTap: _accounts.length > 1 ? _openManageAccountsSheet : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatFolderName(_currentFolder),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        if (_accounts.length > 1) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ],
                    ),
                    if (_selectedAccount != null)
                      Text(
                        _selectedAccount!['email'] ?? '',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _loadMessages(reset: true);
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadFolders();
              _loadMessages(reset: true);
            },
          ),
        ],
      ),
      drawer: _buildDrawer(isDark),
      body: _buildBody(isDark),
      floatingActionButton: _selectedAccount != null
          ? FloatingActionButton.extended(
              backgroundColor: WhatsAppTheme.primaryGreen,
              onPressed: () async {
                final sent = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmailComposerScreen(
                      selectedAccountId: _selectedAccount!['id']?.toString(),
                      accounts: _accounts,
                    ),
                  ),
                );
                if (sent == true) {
                  _loadMessages(reset: true);
                }
              },
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text('Compose', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildDrawer(bool isDark) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: WhatsAppTheme.primaryGreen),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                (_selectedAccount?['name']?[0] ?? _selectedAccount?['email']?[0] ?? 'Z').toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: WhatsAppTheme.primaryGreen),
              ),
            ),
            accountName: Text(
              _selectedAccount?['name'] ?? 'Business Email',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(_selectedAccount?['email'] ?? 'No account configured'),
            onDetailsPressed: _openManageAccountsSheet,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Standard & IMAP Folders
                ListTile(
                  leading: const Icon(Icons.inbox, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Inbox'),
                  selected: _currentFolder == 'INBOX',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentFolder = 'INBOX');
                    _loadMessages(reset: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.send_outlined, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Sent'),
                  selected: _currentFolder.toLowerCase().contains('sent'),
                  onTap: () {
                    Navigator.pop(context);
                    final sentFolder = _folders.firstWhere(
                      (f) => f['specialUse'] == '\\Sent' || f['name'].toString().toLowerCase().contains('sent'),
                      orElse: () => {'path': 'Sent'},
                    );
                    setState(() => _currentFolder = sentFolder['path'] ?? 'Sent');
                    _loadMessages(reset: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drafts_outlined, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Drafts'),
                  selected: _currentFolder.toLowerCase().contains('draft'),
                  onTap: () {
                    Navigator.pop(context);
                    final draftFolder = _folders.firstWhere(
                      (f) => f['specialUse'] == '\\Drafts' || f['name'].toString().toLowerCase().contains('draft'),
                      orElse: () => {'path': 'Drafts'},
                    );
                    setState(() => _currentFolder = draftFolder['path'] ?? 'Drafts');
                    _loadMessages(reset: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.outbox_outlined, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Outbox'),
                  selected: _currentFolder == 'Outbox',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _currentFolder = 'Outbox');
                    _loadMessages(reset: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Trash'),
                  selected: _currentFolder.toLowerCase().contains('trash') || _currentFolder.toLowerCase().contains('junk'),
                  onTap: () {
                    Navigator.pop(context);
                    final trashFolder = _folders.firstWhere(
                      (f) => f['specialUse'] == '\\Trash' || f['name'].toString().toLowerCase().contains('trash'),
                      orElse: () => {'path': 'Trash'},
                    );
                    setState(() => _currentFolder = trashFolder['path'] ?? 'Trash');
                    _loadMessages(reset: true);
                  },
                ),
                if (_folders.isNotEmpty) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('All Folders', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ..._folders.map((f) {
                    final fPath = f['path'] ?? f['name'] ?? '';
                    final isSel = _currentFolder == fPath;
                    final unseen = int.tryParse(f['unseen']?.toString() ?? '0') ?? 0;
                    return ListTile(
                      leading: Icon(_getFolderIcon(f['name'] ?? '', f['specialUse']), size: 20),
                      title: Text(_formatFolderName(f['name'] ?? ''), style: const TextStyle(fontSize: 14)),
                      selected: isSel,
                      trailing: unseen > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: WhatsAppTheme.primaryGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unseen',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentFolder = fPath);
                        _loadMessages(reset: true);
                      },
                    );
                  }),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.manage_accounts, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Manage Email Accounts'),
                  onTap: () {
                    Navigator.pop(context);
                    _openManageAccountsSheet();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add, color: WhatsAppTheme.primaryGreen),
                  title: const Text('Add Business Account'),
                  onTap: () {
                    Navigator.pop(context);
                    _openAccountSetup();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoadingAccounts) {
      return const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen));
    }

    if (_accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: WhatsAppTheme.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mail_outline, size: 64, color: WhatsAppTheme.primaryGreen),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connect Business Email',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Send and receive emails with custom domains, cPanel mailboxes, Google Workspace, or Outlook with full IMAP/SMTP sync and Gemini AI.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: WhatsAppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openAccountSetup(),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Set Up Business Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Quick Filters bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? WhatsAppTheme.surfaceDark : Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              _buildFilterChip('All', 'all'),
              const SizedBox(width: 8),
              _buildFilterChip('Unread', 'unread'),
              const SizedBox(width: 8),
              _buildFilterChip('Starred', 'starred'),
              const Spacer(),
              Text(
                '$_totalMessages emails',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),

        // Message List / Empty State / Error
        Expanded(
          child: _isLoadingMessages && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator(color: WhatsAppTheme.primaryGreen))
              : _errorMessage != null && _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => _loadMessages(reset: true),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _messages.isEmpty
                      ? RefreshIndicator(
                          onRefresh: () => _loadMessages(reset: true),
                          child: ListView(
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.mark_email_read_outlined, size: 54, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No emails found in ${_formatFolderName(_currentFolder)}',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadMessages(reset: true),
                          child: ListView.separated(
                            itemCount: _messages.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 72,
                              color: Colors.grey.withOpacity(0.15),
                            ),
                            itemBuilder: (context, index) {
                              if (index >= _messages.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        _currentPage++;
                                        _loadMessages();
                                      },
                                      child: const Text('Load More Emails'),
                                    ),
                                  ),
                                );
                              }

                              final msg = _messages[index];
                              final isSeen = msg['seen'] == true;
                              final isStarred = msg['flagged'] == true;
                              final fromObj = msg['from'];
                              final fromName = fromObj is Map ? fromObj['name']?.toString() ?? '' : '';
                              final fromAddress = fromObj is Map ? fromObj['address']?.toString() ?? '' : fromObj.toString();
                              final displayName = fromName.isNotEmpty ? fromName : (fromAddress.isNotEmpty ? fromAddress : 'Unknown');
                              final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                              final subject = msg['subject']?.toString().isNotEmpty == true
                                  ? msg['subject'].toString()
                                  : '(No Subject)';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: isSeen
                                          ? Colors.grey.shade400
                                          : WhatsAppTheme.primaryGreen,
                                      child: Text(
                                        initial,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                    if (!isSeen)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: WhatsAppTheme.unreadBadge,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: isSeen ? FontWeight.normal : FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatMsgDate(msg['date']),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSeen ? Colors.grey : WhatsAppTheme.primaryGreen,
                                        fontWeight: isSeen ? FontWeight.normal : FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      subject,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isSeen ? FontWeight.normal : FontWeight.w600,
                                        fontSize: 13,
                                        color: isSeen ? Colors.grey.shade700 : null,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    isStarred ? Icons.star : Icons.star_border,
                                    color: isStarred ? Colors.amber : Colors.grey.shade400,
                                    size: 22,
                                  ),
                                  onPressed: () => _toggleStar(msg),
                                ),
                                onTap: () async {
                                  // Mark local state as seen
                                  setState(() => msg['seen'] = true);
                                  final uid = msg['uid']?.toString() ?? '';
                                  final refreshed = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EmailDetailScreen(
                                        uid: uid,
                                        folder: _currentFolder,
                                        accountId: _selectedAccount?['id']?.toString(),
                                        accounts: _accounts,
                                      ),
                                    ),
                                  );
                                  if (refreshed == true) {
                                    _loadMessages(reset: true);
                                  }
                                },
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSel = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSel,
      selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.18),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSel ? WhatsAppTheme.primaryGreen : null,
        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() => _selectedFilter = value);
        _loadMessages(reset: true);
      },
    );
  }
}
