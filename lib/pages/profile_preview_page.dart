// lib/pages/profile_preview_page.dart
// (.txt olarak verildi. Projeye eklerken adını profile_preview_page.dart yapın.)
// Başka bir kullanıcının profil önizlemesi. Durum: kullanıcının seçtiği mod (Aktif, Boşta, Rahatsız etmeyin).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/profile.dart';

class ProfilePreviewPage extends StatelessWidget {
  final Profile profile;
  final VoidCallback? onMessageTap;
  final VoidCallback? onBlockTap;
  final VoidCallback? onReportTap;

  const ProfilePreviewPage({
    super.key,
    required this.profile,
    this.onMessageTap,
    this.onBlockTap,
    this.onReportTap,
  });

  Color _modeColor() {
    switch (profile.mode) {
      case 'idle':
        return Colors.amber;
      case 'dnd':
        return Colors.redAccent;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final hasAvatar = profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Kapak ve avatar
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.primary.withOpacity(0.4), c.background],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: GestureDetector(
                  onTap: hasAvatar ? () => _showFullImage(context, profile.avatarUrl!) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.primary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: c.primary.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 65,
                      backgroundColor: c.surface,
                      backgroundImage: hasAvatar
                          ? CachedNetworkImageProvider(profile.avatarUrl!)
                          : null,
                      child: hasAvatar
                          ? null
                          : Text(
                              profile.initial,
                              style: const TextStyle(
                                fontSize: 45,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // Bilgi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    profile.username,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (profile.fullName != null && profile.fullName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      profile.fullName!,
                      style: TextStyle(color: c.textSecondary, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Durum modu
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _modeColor(),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          profile.modeLabel,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Aksiyon
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onMessageTap ?? () => Navigator.pop(context),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mesaj Gönder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Güvenlik
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.block, color: Colors.orange),
                          title: Text('Kullanıcıyı Engelle',
                              style: TextStyle(color: c.textPrimary)),
                          subtitle: Text('Bu kullanıcıdan gelen mesajları alma',
                              style: TextStyle(color: c.textSecondary, fontSize: 12)),
                          onTap: onBlockTap ?? () {},
                        ),
                        Divider(color: c.border, height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.report_gmailerrorred,
                              color: Colors.redAccent),
                          title: Text('Kullanıcıyı Bildir',
                              style: TextStyle(color: c.textPrimary)),
                          subtitle: Text('Uygunsuz davranışı bildir',
                              style: TextStyle(color: c.textSecondary, fontSize: 12)),
                          onTap: onReportTap ?? () {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
