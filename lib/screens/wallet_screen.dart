import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/shop_model.dart';
import '../payments/qris.dart';
import '../payments/qris_pay_card.dart';
import '../services/wallet_service.dart';
import '../utils/format_id.dart';
import '../widgets/quick_snackbar.dart';

const _ink = Color(0xFF0F172A);
const _body = Color(0xFF334155);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _bg = Color(0xFFF1F5F9);
const _brand = Color(0xFF0077B6);
const _green = Color(0xFF15803D);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);

TextStyle _t(double s, {Color c = _body, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: s, fontWeight: w, color: c);

/// Warna & teks status saldo (warna hanya untuk arti: hijau aman, kuning perlu perhatian, merah terblokir)
(Color, Color, String, String) walletStateStyle(WalletSummary s) => switch (s.state) {
      WalletState.intro => (_brand, const Color(0xFFE0F2FE), 'Masa pengenalan', 'Komisi Rp 0 untuk sementara. Potongan tetap dicatat sebagai informasi.'),
      WalletState.ok => (_green, const Color(0xFFDCFCE7), 'Saldo aman', 'Cukup untuk ±${s.ordersLeft} pesanan aplikasi lagi.'),
      WalletState.low => (_amber, const Color(0xFFFEF3C7), 'Saldo menipis', 'Cukup untuk ±${s.ordersLeft} pesanan lagi. Isi ulang agar outlet tetap menerima pesanan.'),
      WalletState.owing => (_amber, const Color(0xFFFEF3C7), 'Ada tagihan komisi', 'Saldo minus. Outlet berhenti menerima pesanan jika melewati batas kredit ${rupiah(s.creditLimit)}.'),
      WalletState.blocked => (_red, const Color(0xFFFEE2E2), 'Outlet tidak menerima pesanan', 'Batas kredit tercapai. Pesanan berjalan tetap bisa diselesaikan; isi saldo untuk aktif lagi.'),
    };

/// Saldo komisi mitra: ringkasan, isi saldo via QRIS Washora, riwayat potongan.
class WalletScreen extends StatefulWidget {
  final ShopModel shop;
  const WalletScreen({super.key, required this.shop});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _service = WalletService();
  WalletSummary? _summary;
  List<WalletEntry> _ledger = [];
  List<WalletTopup> _topups = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([
        _service.summary(widget.shop.id),
        _service.ledger(widget.shop.id),
        _service.topups(widget.shop.id),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = r[0] as WalletSummary;
        _ledger = r[1] as List<WalletEntry>;
        _topups = r[2] as List<WalletTopup>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _topup() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _TopupScreen(shop: widget.shop)),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _topups.where((t) => t.status == 'pending').firstOrNull;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text('Saldo Komisi', style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: _error != null
                  ? [
                      const SizedBox(height: 60),
                      const Icon(Icons.account_balance_wallet_outlined, size: 36, color: _red),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center, style: _t(13)),
                      const SizedBox(height: 12),
                      Center(child: OutlinedButton(onPressed: _load, child: const Text('Coba lagi'))),
                    ]
                  : _summary == null
                      ? const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))]
                      : _content(_summary!, pending),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(WalletSummary s, WalletTopup? pending) {
    final (color, soft, title, desc) = walletStateStyle(s);
    return [
      // Ringkasan saldo
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo komisi', style: _t(12.5, c: _muted)),
            const SizedBox(height: 4),
            Text(rupiah(s.balance),
                style: GoogleFonts.quicksand(fontSize: 32, fontWeight: FontWeight.w800, color: s.balance < 0 ? _red : _ink)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.state == WalletState.blocked ? Icons.block_rounded : Icons.info_outline_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: _t(13, c: color, w: FontWeight.w800)),
                        Text(desc, style: _t(12, c: _body)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _fact('Komisi / pesanan', s.commissionActive ? rupiah(s.commissionAmount) : 'Rp 0 (normal ${rupiah(s.commissionAmount)})'),
                _fact('Batas kredit', rupiah(s.creditLimit)),
                _fact('Pesanan bulan ini', '${s.ordersThisMonth}'),
              ],
            ),
            if (s.waivedOrders > 0) ...[
              const SizedBox(height: 10),
              Text('${s.waivedOrders} pesanan bebas komisi selama masa pengenalan (hemat ${rupiah(s.waivedAmount)}).',
                  style: _t(12, c: _muted)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: pending == null ? _topup : null,
                icon: const Icon(Icons.add_rounded),
                label: Text(pending == null ? 'Isi Saldo' : 'Menunggu konfirmasi isi saldo'),
                style: FilledButton.styleFrom(backgroundColor: _brand),
              ),
            ),
          ],
        ),
      ),
      if (pending != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFDE68A))),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: _amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Isi saldo ${rupiah(pending.payable)} diajukan ${tanggalJam(pending.createdAt)}. '
                    'Saldo bertambah setelah admin mencocokkan dana masuk.', style: _t(12.5)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      // Cara kerja (singkat)
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Cara kerja saldo komisi', style: _t(13.5, c: _ink, w: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in [
            'Pembayaran pelanggan masuk langsung ke QRIS outlet Anda.',
            'Komisi Washora dipotong dari saldo ini saat pesanan aplikasi mulai dicuci. Pesanan walk-in tidak dipotong.',
            'Saldo boleh minus sampai batas kredit. Lewat batas, outlet berhenti menerima pesanan aplikasi baru sampai saldo diisi.',
            'Isi saldo lewat QRIS Washora; nominal ditambah kode unik 3 digit dan seluruhnya masuk ke saldo.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 5, color: _muted)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: _t(12.5))),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Riwayat saldo', style: _t(14, c: _ink, w: FontWeight.w800)),
      const SizedBox(height: 8),
      if (_ledger.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text('Belum ada riwayat. Potongan muncul saat pesanan aplikasi mulai dicuci.',
              textAlign: TextAlign.center, style: _t(12.5, c: _muted)),
        )
      else
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
          child: Column(
            children: [
              for (var i = 0; i < _ledger.length; i++) ...[
                _entryRow(_ledger[i]),
                if (i < _ledger.length - 1) const Divider(height: 1, color: _border),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _fact(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _t(11, c: _muted)),
            const SizedBox(height: 2),
            Text(value, style: _t(12.5, c: _ink, w: FontWeight.w700)),
          ],
        ),
      );

  Widget _entryRow(WalletEntry e) {
    final color = e.amount > 0 ? _green : (e.amount < 0 ? _red : _faint);
    final sign = e.amount > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label, style: _t(13, c: _ink, w: FontWeight.w700)),
                Text(
                  [
                    tanggalJam(e.createdAt),
                    if (e.orderId != null) 'Pesanan #${nomorTransaksi(e.orderId!)}',
                    if (e.note.isNotEmpty && e.type != 'commission') e.note,
                  ].join(' · '),
                  style: _t(11.5, c: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$sign${rupiah(e.amount)}', style: _t(13, c: color, w: FontWeight.w800)),
              Text('Saldo ${rupiah(e.balanceAfter)}', style: _t(11, c: _faint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// ISI SALDO: pilih nominal → bayar QRIS Washora (nominal + kode unik) → bukti
// ======================================================================

class _TopupScreen extends StatefulWidget {
  final ShopModel shop;
  const _TopupScreen({required this.shop});

  @override
  State<_TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<_TopupScreen> {
  final _service = WalletService();
  final _custom = TextEditingController();
  static const _presets = [20000, 50000, 100000, 200000];
  int? _amount = 50000;
  final int _code = 100 + Random().nextInt(900);
  String? _qris;
  bool _loadingQris = true;
  Uint8List? _proof;
  String _mime = 'image/jpeg';
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.platformQris().then((q) {
      if (mounted) {
        setState(() {
          _qris = q;
          _loadingQris = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  int get _payable => (_amount ?? 0) + _code;

  Future<void> _pickProof(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 75);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        setState(() => _error = 'Ukuran bukti melebihi 3 MB.');
        return;
      }
      final n = f.name.toLowerCase();
      setState(() {
        _proof = bytes;
        _mime = f.mimeType ?? (n.endsWith('.png') ? 'image/png' : n.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Foto tidak bisa dibuka.');
    }
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null || amount < 10000) {
      setState(() => _error = 'Minimal isi saldo Rp 10.000.');
      return;
    }
    if (_proof == null) {
      setState(() => _error = 'Unggah bukti pembayaran dulu.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.requestTopup(widget.shop.id, amount, _code, _proof!, mime: _mime);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(const SnackBar(
        content: Text('Pengajuan isi saldo terkirim. Saldo bertambah setelah dikonfirmasi admin.'),
        backgroundColor: _green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrisReady = _qris != null && Qris.isValid(_qris!);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text('Isi Saldo Komisi', style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text('1. Pilih nominal', style: _t(14, c: _ink, w: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    ChoiceChip(
                      label: Text(rupiah(p)),
                      selected: _amount == p && _custom.text.isEmpty,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _custom.clear();
                        _amount = p;
                      }),
                      labelStyle: _t(13, c: _amount == p && _custom.text.isEmpty ? Colors.white : _ink, w: FontWeight.w700),
                      selectedColor: _ink,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _amount == p && _custom.text.isEmpty ? _ink : _border),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _custom,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => setState(() => _amount = int.tryParse(v)),
                decoration: InputDecoration(
                  labelText: 'Nominal lain',
                  prefixText: 'Rp ',
                  helperText: 'Minimal Rp 10.000',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 18),
              Text('2. Bayar ke QRIS Washora', style: _t(14, c: _ink, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Nominal ditambah kode unik ${_code.toString()} agar pembayaran mudah dicocokkan. Seluruhnya masuk ke saldo.',
                  style: _t(12, c: _muted)),
              const SizedBox(height: 10),
              if (_loadingQris)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (!qrisReady)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'QRIS Washora belum diatur admin (platform_settings.qris_payload). Hubungi admin Washora untuk cara isi saldo.',
                    style: _t(12.5, c: _red),
                  ),
                )
              else if ((_amount ?? 0) >= 10000)
                QrisPayCard(payload: _qris!, amount: _payable, title: 'Isi saldo ${rupiah(_amount!)} + kode $_code'),
              const SizedBox(height: 18),
              Text('3. Unggah bukti pembayaran', style: _t(14, c: _ink, w: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_proof != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_proof!, height: 200, width: double.infinity, fit: BoxFit.contain),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.filledTonal(
                        tooltip: 'Hapus bukti',
                        onPressed: () => setState(() => _proof = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickProof(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Tangkapan layar'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.white),
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickProof(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Foto'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: _t(12.5, c: _red, w: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _sending || !qrisReady ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _brand),
                  child: _sending
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(_error != null ? 'Coba lagi' : 'Kirim pengajuan ${rupiah(_payable)}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
