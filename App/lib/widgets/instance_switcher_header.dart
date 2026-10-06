import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/instance.dart';
import '../screens/connect_screen.dart';
import '../services/auth_service.dart';

class InstanceSwitcherHeader extends StatelessWidget {
  const InstanceSwitcherHeader({super.key});

  void _showInstancePicker(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final instances = auth.instances;
    final current = auth.selectedInstance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, color: WhatsAppTheme.primaryGreen, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Switch Connected Account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF111B21),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                if (instances.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No WhatsApp accounts linked yet',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: instances.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final inst = instances[i];
                        final isSelected = inst.id == current?.id;
                        final isOnline = inst.isConnected;
                        final isDefault = inst.id == auth.defaultInstanceId;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isSelected
                                    ? WhatsAppTheme.primaryGreen.withOpacity(0.15)
                                    : Colors.grey.shade200,
                                child: Icon(
                                  Icons.phone_android_rounded,
                                  color: isSelected ? WhatsAppTheme.primaryGreen : Colors.grey.shade700,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isOnline ? WhatsAppTheme.accentGreen : Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  inst.name.isNotEmpty ? inst.name : 'Instance ${inst.id.substring(0, 6)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 15.5,
                                    color: isSelected ? WhatsAppTheme.primaryGreen : null,
                                  ),
                                ),
                              ),
                              if (isDefault) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade600, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_rounded, size: 13, color: Colors.amber.shade800),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Default',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            inst.phone != null && inst.phone!.isNotEmpty
                                ? '+${inst.phone} • ${inst.status.toUpperCase()}'
                                : inst.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isOnline ? WhatsAppTheme.accentGreen : Colors.grey.shade600,
                              fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.check_circle, color: WhatsAppTheme.primaryGreen, size: 22),
                                ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                tooltip: 'Account Options',
                                onSelected: (val) async {
                                  if (val == 'default') {
                                    await auth.setDefaultInstance(inst.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${inst.name} set as Default Account'),
                                          backgroundColor: WhatsAppTheme.primaryGreen,
                                        ),
                                      );
                                    }
                                  } else if (val == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (dlgCtx) => AlertDialog(
                                        title: const Text('Delete Account?'),
                                        content: Text(
                                          'Are you sure you want to permanently delete "${inst.name}"?\nThis will disconnect the session.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dlgCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(dlgCtx, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await auth.deleteInstance(inst.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Account deleted successfully'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      } catch (err) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Delete failed: $err')),
                                          );
                                        }
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (menuCtx) => [
                                  PopupMenuItem(
                                    value: 'default',
                                    enabled: !isDefault,
                                    child: Row(
                                      children: [
                                        Icon(
                                          isDefault ? Icons.star_rounded : Icons.star_border_rounded,
                                          color: isDefault ? Colors.grey : Colors.amber.shade700,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(isDefault ? 'Default Account' : 'Set as Default'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_forever_rounded, color: Colors.red, size: 18),
                                        SizedBox(width: 8),
                                        Text('Delete Account', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () {
                            auth.selectInstance(inst);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConnectScreen()),
                      );
                    },
                    icon: const Icon(Icons.add, color: WhatsAppTheme.primaryGreen),
                    label: const Text(
                      'Link Another WhatsApp Account',
                      style: TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: WhatsAppTheme.primaryGreen, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final inst = auth.selectedInstance;
    final isOnline = inst?.isConnected == true;

    return InkWell(
      onTap: () => _showInstancePicker(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF25D366) : const Color(0xFFFF5252),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isOnline ? const Color(0xFF25D366) : const Color(0xFFFF5252)).withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                inst != null && inst.name.isNotEmpty
                    ? inst.name
                    : (inst != null ? 'Account ${inst.id.substring(0, 4)}' : 'Select Account'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
