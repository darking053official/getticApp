// ============================================================
// lib/services/captcha_gate.dart
// (.txt olarak verildi. Projeye eklerken adını captcha_gate.dart yapın.)
// Cloudflare Turnstile doğrulaması. Android ve iOS'ta WebView ile açılır.
// Masaüstünde (Windows, macOS, Linux) WebView desteklenmediği için null döner.
// Gerekli paket: webview_flutter
// Cloudflare panelinde Turnstile widget'ının hostname listesine gettic.dpdns.org eklenmeli.
// ============================================================

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';

const String kTurnstileSiteKey = '0x4AAAAAAFS3vgW1pXHXHKOn';

const String _turnstileHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <style>
    html, body { margin:0; height:100%; background:#12121a; }
    body { display:flex; align-items:center; justify-content:center; }
  </style>
</head>
<body>
  <div class="cf-turnstile"
       data-sitekey="$kTurnstileSiteKey"
       data-theme="dark"
       data-callback="onSuccess"
       data-error-callback="onError"
       data-expired-callback="onError"></div>
  <script>
    function onSuccess(token) { TurnstileChannel.postMessage('ok:' + token); }
    function onError() { TurnstileChannel.postMessage('err'); }
  </script>
</body>
</html>
''';

class CaptchaGate {
  CaptchaGate._();

  /// Bu platformda doğrulama penceresi açılabiliyor mu?
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  /// Doğrulamayı gösterir. Başarılıysa token, iptal/hata durumunda null döner.
  static Future<String?> solve(BuildContext context) async {
    if (!supported) return null;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CaptchaSheet(),
    );
  }
}

class _CaptchaSheet extends StatefulWidget {
  const _CaptchaSheet();

  @override
  State<_CaptchaSheet> createState() => _CaptchaSheetState();
}

class _CaptchaSheetState extends State<_CaptchaSheet> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.surface)
      ..addJavaScriptChannel(
        'TurnstileChannel',
        onMessageReceived: (msg) {
          if (!mounted) return;
          final m = msg.message;
          if (m.startsWith('ok:')) {
            Navigator.pop(context, m.substring(3));
          } else {
            Navigator.pop(context, null);
          }
        },
      )
      ..loadHtmlString(_turnstileHtml, baseUrl: 'https://gettic.dpdns.org');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Text(
              'Güvenlik doğrulaması',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
