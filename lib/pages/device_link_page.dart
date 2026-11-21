// ============================================================
// lib/pages/device_link_page.dart
// (.txt olarak verildi. Projeye eklerken adını device_link_page.dart yapın.)
// Cihaz bağlama ekranı.
//  - Bu cihaz onaylı değilse: bağlantı metnini ve kodu gösterir, onay bekler.
//  - Bu cihaz onaylıysa: başka bir cihazın bağlantı metnini yapıştırıp kodu karşılaştırır, onaylar.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../services/e2ee_chat.dart';
import '../services/e2ee_device.dart';
import '../services/e2ee_backup.dart';
import '../services/e2ee_link.dart';

class DeviceLinkPage extends StatefulWidget {
  const DeviceLinkPage({super.key});

  @override
  State<DeviceLinkPage> createState() => _DeviceLinkPageState();
}

class _DeviceLinkPageState extends State<DeviceLinkPage> {
  bool _loading = true;
  bool _approved = false;
  String? _payload;
  String? _code;
  String? _error;

  // Onaylı cihaz tarafı
  final _pasteCtl = TextEditingController();
  String? _pasteCode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pasteCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final me = await E2eeDevice.instance.ensureIdentity();
      _approved = me.approved;
      if (!_approved) {
        final payload = await E2eeLink.instance.pendingPayload();
        _payload = payload;
        _code = await E2eeLink.instance.codeFor(payload);
        _waitAndRefresh();
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _waitAndRefresh() async {
    final ok = await E2eeLink.instance.waitForApproval();
    if (!mounted) return;
    if (ok) {
      setState(() => _approved = true);
      _snack('Cihaz onaylandı. Mesajlar yakında çözülecek.');
    }
  }

  Future<void> _checkPaste() async {
    setState(() {
      _pasteCode = null;
      _error = null;
    });
    try {
      final code = await E2eeLink.instance.codeFor(_pasteCtl.text);
      if (mounted) setState(() => _pasteCode = code);
    } catch (e) {
      if (mounted) setState(() => _error = 'Geçersiz bağlantı metni');
    }
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await E2eeLink.instance.approve(_pasteCtl.text);
      if (!mounted) return;
      _pasteCtl.clear();
      setState(() => _pasteCode = null);
      _snack('Yeni cihaz onaylandı');
    } catch (e) {
      _snack('Onaylanamadı: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromBackup() async {
    final count = await showBackupRestoreDialog(context);
    if (count == null || !mounted) return;
    _snack('$count anahtar geri yüklendi');
    setState(() => _loading = true);
    await _init();
  }

  /// Yerel anahtarların sunucudaki kayıtla eşleşip eşleşmediğini kontrol eder.
  Future<void> _checkKeys() async {
    setState(() => _busy = true);
    try {
      final me = await E2eeDevice.instance.ensureIdentity();
      final row = await Supabase.instance.client
          .from('devices')
          .select('identity_pub_x25519, identity_pub_ed25519, approved_at, revoked_at')
          .eq('id', me.deviceId)
          .maybeSingle();
      if (row == null) {
        _snack('Sunucuda bu cihaz kaydı yok', isError: true);
        return;
      }
      final xOk = row['identity_pub_x25519'] == me.x25519PubB64;
      final edOk = row['identity_pub_ed25519'] == me.ed25519PubB64;
      final approved = row['approved_at'] != null;
      final msg = (xOk && edOk)
          ? 'Anahtarlar eşleşiyor. ${approved ? "Cihaz onaylı." : "Cihaz onaylı değil."}'
          : 'UYUŞMA: Yerel anahtarlar sunucuyla eşleşmiyor. Cihazı yeniden bağlayın.';
      _snack(msg, isError: !(xOk && edOk));
    } catch (e) {
      _snack('Kontrol edilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareHistoryAll() async {
    setState(() => _busy = true);
    try {
      final me = await E2eeDevice.instance.ensureIdentity();
      final devices = await Supabase.instance.client
          .from('devices')
          .select('id, identity_pub_x25519')
          .neq('id', me.deviceId)
          .isFilter('revoked_at', null)
          .not('approved_at', 'is', null);
      final list = List<Map<String, dynamic>>.from(devices as List);
      for (final d in list) {
        await E2eeChat.instance.shareHistoryWith(
          targetDeviceId: d['id'].toString(),
          targetX25519PubB64: d['identity_pub_x25519'] as String,
        );
      }
      _snack('Geçmiş ${list.length} cihaza paylaşıldı');
    } catch (e) {
      _snack('Paylaşılamadı: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : AppTheme.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Cihaz bağlama'),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _approved ? _approvedView() : _pendingView(),
            ),
    );
  }

  List<Widget> _pendingView() {
    return [
      const Text(
        'Bu cihaz henüz onaylı değil',
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Mesajlarınızı görmek ve göndermek için mevcut bir cihazdan bu cihazı onaylamanız gerekiyor. '
        'Aşağıdaki metni o cihaza yapıştırın ve iki cihazda aynı kodun göründüğünü kontrol edin.',
        style: TextStyle(color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 16),
      if (_code != null)
        Center(
          child: Text(
            _code!,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
        ),
      const SizedBox(height: 16),
      if (_payload != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.inputBorder),
          ),
          child: SelectableText(
            _payload!,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _payload == null
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: _payload!));
                _snack('Bağlantı metni kopyalandı');
              },
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('Metni kopyala'),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _busy ? null : _restoreFromBackup,
        icon: const Icon(Icons.restore, size: 18),
        label: const Text('Yedekten geri yükle'),
      ),
      const SizedBox(height: 16),
      const Row(
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Onay bekleniyor...', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ],
    ];
  }

  List<Widget> _approvedView() {
    return [
      const Text(
        'Yeni cihaz onayla',
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Yeni cihazda gösterilen bağlantı metnini buraya yapıştırın. '
        'Kod, yeni cihazdaki kodla aynıysa onaylayın.',
        style: TextStyle(color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pasteCtl,
        minLines: 3,
        maxLines: 6,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
        decoration: const InputDecoration(hintText: 'Bağlantı metnini yapıştırın'),
        onChanged: (_) => _checkPaste(),
      ),
      const SizedBox(height: 12),
      if (_pasteCode != null) ...[
        Center(
          child: Text(
            _pasteCode!,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : _approve,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kodlar aynı, onayla'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ],
      const SizedBox(height: 28),
      const Divider(color: AppTheme.inputBorder),
      const SizedBox(height: 12),
      const Text(
        'Geçmişi diğer cihazlarla paylaş',
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      const Text(
        'Bu cihazın bildiği eski sohbet anahtarlarını bağlı diğer cihazlara gönderir. '
        'Eski mesajların o cihazlarda açılması için bu düğmeyi ilk (eski) cihazdan kullanın.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _checkKeys,
        icon: const Icon(Icons.vpn_key_outlined, size: 18),
        label: const Text('Anahtarları kontrol et'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _shareHistoryAll,
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('Geçmişi paylaş'),
      ),
    ];
  }
}
