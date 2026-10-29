import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- KAPAK VE AVATAR ALANI ---
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.4),
                    AppTheme.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (profile.avatarUrl != null) {
                      _showFullImage(context, profile.avatarUrl!);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 65,
                      backgroundColor: AppTheme.surface,
                      backgroundImage: profile.avatarUrl != null
                          ? CachedNetworkImageProvider(profile.avatarUrl!)
                          : null,
                      child: profile.avatarUrl == null
                          ? Text(
                              profile.username.isNotEmpty
                                  ? profile.username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 45,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),

            // --- BİLGİ ALANI ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    profile.username,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (profile.fullName != null && profile.fullName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      profile.fullName!,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  
                  // Durum Bilgisi
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.inputBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: profile.status == 'online'
                                ? AppTheme.online
                                : AppTheme.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          profile.status == 'online' ? 'Çevrimiçi' : 'Çevrimdışı',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- AKSİYON BUTONLARI ---
                  Row(
                    children: [
                      // Mesaj Gönder Butonu
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onMessageTap ?? () => Navigator.pop(context),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Mesaj Gönder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- GÜVENLİK SEÇENEKLERİ ---
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.inputBorder),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.block, color: Colors.orange),
                          title: const Text(
                            'Kullanıcıyı Engelle',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: const Text(
                            'Bu kullanıcıdan gelen mesajları alma',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          onTap: onBlockTap ?? () {},
                        ),
                        const Divider(color: AppTheme.inputBorder, height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(Icons.report_gmailerrorred, color: Colors.redAccent),
                          title: const Text(
                            'Kullanıcıyı Bildir',
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: const Text(
                            'Uygunsuz davranışı bildir',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
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
