// ============================================================
// lib/services/captcha_gate.dart
// (.txt olarak verildi. Projeye eklerken adını captcha_gate.dart yapın.)
// Cloudflare Turnstile doğrulaması.
//  - Android / iOS: WebView penceresi (webview_flutter).
//  - Windows / macOS / Linux: sistem tarayıcısı açılır, doğrulama sayfası
//    (Supabase Edge Function: captcha-page) token'ı 127.0.0.1 üzerindeki
//    geçici yerel sunucuya gönderir.
// Gerekli paketler: webview_flutter, url_launcher
// Cloudflare Turnstile widget'ının hostname listesine şunlar eklenmeli:
//   gettic.dpdns.org
//   ayucfychcemsvzlgsdqq.supabase.co
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';

const String kTurnstileSiteKey = '0x4AAAAAAFS3vgW1pXHXHKOn';
const String kCaptchaPageUrl =
    'https://ayucfychcemsvzlgsdqq.supabase.co/functions/v1/captcha-page';

const String _mobileHtml = '''
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

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Artık her platformda çalışır (mobil: WebView, masaüstü: tarayıcı).
  static bool get supported => true;

  /// Doğrulamayı başlatır. Başarılıysa token, iptal/zaman aşımında null döner.
  static Future<String?> solve(BuildContext context) async {
    if (_isMobile) {
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
    return _solveInBrowser(context);
  }

  /// Masaüstü: yerel sunucu aç, tarayıcıda sayfayı aç, token'ı bekle.
  static Future<String?> _solveInBrowser(BuildContext context) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<String?>();

    server.listen((req) async {
      req.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
        ..set('Access-Control-Allow-Headers', '*');
      if (req.method == 'OPTIONS') {
        req.response.statusCode = 204;
        await req.response.close();
        return;
      }
      if (req.uri.path == '/token' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        req.response
          ..statusCode = 200
          ..write('ok');
        await req.response.close();
        if (!completer.isCompleted) {
          completer.complete(body.startsWith('ok:') ? body.substring(3) : null);
        }
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final url = Uri.parse('$kCaptchaPageUrl?port=${server.port}');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened) {
      await server.close(force: true);
      return null;
    }

    final token = await completer.future
        .timeout(const Duration(minutes: 3), onTimeout: () => null);
    await server.close(force: true);
    return token;
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
          Navigator.pop(context, m.startsWith('ok:') ? m.substring(3) : null);
        },
      )
      ..loadHtmlString(_mobileHtml, baseUrl: 'https://gettic.dpdns.org');
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
