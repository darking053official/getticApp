// ============================================================
// lib/pages/incoming_call_page.dart
// (.txt olarak verildi. Projeye eklerken adını incoming_call_page.dart yapın.)
// Gelen arama: tam ekran, sade. Cevapla / Reddet. Zil sesi MeetService'te çalar.
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme.dart';

class IncomingCallPage extends StatelessWidget {
  final String fromName;
  final bool video;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallPage({
    super.key,
    required this.fromName,
    required this.video,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final initial = fromName.isNotEmpty ? fromName[0].toUpperCase() : '?';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.background,
              c.primary.withOpacity(0.35),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 48),
                Text(
                  video ? 'Görüntülü arama' : 'Sesli arama',
                  style: TextStyle(color: c.textSecondary, fontSize: 14),
                ),
                const Spacer(),
                CircleAvatar(
                  radius: 56,
                  backgroundColor: c.primary,
                  child: Text(
                    initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  fromName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'arıyor',
                  style: TextStyle(color: c.textSecondary, fontSize: 15),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionButton(
                      icon: Icons.call_end,
                      label: 'Reddet',
                      color: c.danger,
                      onTap: onDecline,
                    ),
                    _actionButton(
                      icon: video ? Icons.videocam : Icons.call,
                      label: 'Cevapla',
                      color: c.online,
                      onTap: onAccept,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

}
