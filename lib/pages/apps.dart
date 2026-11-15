import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'chat_list_page.dart';
import 'notebook_page.dart';
import 'meet_home_page.dart';
import 'pass_vault_page.dart';
import 'settings_page.dart';

/// Giriş yapıldıktan sonra açılan ana ekran.
/// Kullanıcı buradan Sohbet, Parola Kasası veya Notebook'a geçer.
class AppsPage extends StatelessWidget {
  const AppsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Gettic'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: Text(
                'Bir uygulama seç',
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
            ),
            _AppCard(
              icon: Icons.chat_bubble_outline,
              logoAsset: 'assets/logo.png',
              title: 'Sohbet',
              subtitle: 'Mesajlar ve gruplar',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatListPage()),
              ),
            ),
            const SizedBox(height: 12),
            _AppCard(
              icon: Icons.key_outlined,
              logoAsset: 'assets/getticpass_logo.png',
              title: 'Gettic Pass',
              subtitle: 'Şifreli parolalar, eklentiyle senkron',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PassVaultPage()),
              ),
            ),
            const SizedBox(height: 12),
            _AppCard(
              icon: Icons.menu_book_outlined,
              logoAsset: 'assets/getticnotebook_logo.png',
              title: 'Gettic Notebook',
              subtitle: 'Kişisel notlar',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotebookPage()),
              ),
            ),
            const SizedBox(height: 12),
            _AppCard(
              icon: Icons.videocam_outlined,
              logoAsset: 'assets/getticmeet_logo.png',
              title: 'Gettic Meet',
              subtitle: 'Görüntülü ve sesli arama',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MeetHomePage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final IconData icon;
  final String? logoAsset;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _AppCard({
    required this.icon,
    this.logoAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: logoAsset != null
                      ? Image.asset(
                          logoAsset!,
                          errorBuilder: (_, __, ___) =>
                              Icon(icon, color: c.primary),
                        )
                      : Icon(icon, color: c.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  Icon(Icons.chevron_right, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
