import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/membership_models.dart';
import '../services/membership_service.dart';
import '../services/wallet_service.dart';
import '../payments/qris.dart';
import '../payments/qris_pay_card.dart';
import '../utils/format_id.dart';
import '../widgets/quick_snackbar.dart';

const _ink = Color(0xFF0F172A);
const _body = Color(0xFF334155);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _bg = Color(0xFFF1F5F9);
const _brand = Color(0xFF0077E6);
const _green = Color(0xFF15803D);
const _red = Color(0xFFB91C1C);

TextStyle _t(double s, {Color c = _body, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.plusJakartaSans(fontSize: s, fontWeight: w, color: c);

/// Langganan member Bronze / Silver / Gold untuk pelanggan.
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final _service = MembershipService();
  MembershipState? _state;
  String? _error;
  String _period = 'monthly';
  (int, int)? _deliverySpent;
  MemberBenefits? _benefits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await _service.fetchState();
      final spent = await _service.deliverySpentLast30Days();
      final benefits = await _service.fetchBenefits();
      if (!mounted) return;
      setState(() {
        _state = s;
        _deliverySpent = spent;
        _benefits = benefits;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _choose(MembershipPlan plan) async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _CheckoutScreen(plan: plan, period: _period)),
    );
    if (submitted == true) _load();
  }

  Future<void> _toggleCancel(Membership m) async {
    final cancel = !m.cancelAtPeriodEnd;
    try {
      await _service.setCancelAtPeriodEnd(m.id, cancel);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(
        content: Text(cancel
            ? 'Langganan tidak diperpanjang. Benefit tetap berlaku sampai ${tanggal(m.endsAt!)}.'
            : 'Langganan akan diperpanjang seperti biasa.'),
      ));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: _red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text('Langganan Washora', style: _t(17, c: _ink, w: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: _content(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (_error != null) {
      return [
        const SizedBox(height: 60),
        const Icon(Icons.wifi_off_rounded, size: 36, color: _red),
        const SizedBox(height: 10),
        Text('Langganan gagal dimuat', textAlign: TextAlign.center, style: _t(15, c: _ink, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_error!, textAlign: TextAlign.center, style: _t(12.5, c: _muted)),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: _load, child: const Text('Coba lagi'))),
      ];
    }
    final s = _state;
    if (s == null) {
      return const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))];
    }

    return [
      if (s.active != null) _activeCard(s.active!, s.planOf(s.active)),
      if (s.pending != null) _pendingCard(s.pending!, s.planOf(s.pending)),
      if (s.lastRejected != null) _rejectedCard(s.lastRejected!, s.planOf(s.lastRejected)),
      if (s.active != null || s.pending != null || s.lastRejected != null) const SizedBox(height: 16),
      // Tahap 1: jujur soal benefit yang belum otomatis
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pembayaran dikonfirmasi manual oleh admin. Gratis ongkir, poin, dan batas klaim sudah '
                'berlaku otomatis saat checkout. Diskon Mitra Member dan gratis upgrade Express menyusul.',
                style: _t(11.5, c: const Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if ((_benefits?.pointsBalance ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Saldo poin: ${_benefits!.pointsBalance} (= ${rupiah(_benefits!.pointsBalance)} potongan)',
              style: _t(12.5, c: _ink, w: FontWeight.w700)),
        ),
      if (_deliverySpent != null && _deliverySpent!.$2 > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '30 hari terakhir kamu membayar ongkir ${rupiah(_deliverySpent!.$1)} untuk ${_deliverySpent!.$2} pesanan antar-jemput.',
            style: _t(12.5, c: _body, w: FontWeight.w600),
          ),
        ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'monthly', label: Text('Bulanan')),
          ButtonSegment(value: 'yearly', label: Text('Tahunan · 2 bulan gratis')),
        ],
        selected: {_period},
        onSelectionChanged: (v) => setState(() => _period = v.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 14),
      for (final p in s.plans) ...[
        _planCard(p, current: s.active?.planId == p.id, blocked: s.pending != null),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
      Text('Bisa berhenti kapan saja. Benefit tetap berlaku sampai akhir periode yang sudah dibayar.',
          textAlign: TextAlign.center, style: _t(11.5, c: _faint)),
    ];
  }

  Widget _planCard(MembershipPlan p, {required bool current, required bool blocked}) {
    final price = p.priceFor(_period);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: current ? p.color : _border, width: current ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.softColor, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.workspace_premium_rounded, color: p.color),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(p.name, style: _t(17, c: _ink, w: FontWeight.w800))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rupiah(price), style: _t(17, c: _ink, w: FontWeight.w800)),
                  Text(_period == 'yearly' ? '/ tahun (≈ ${rupiah((price / 12).round())}/bln)' : '/ bulan', style: _t(11, c: _muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final b in p.benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 17, color: p.color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(b, style: _t(12.5, c: _body))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: current
                ? OutlinedButton(
                    onPressed: blocked ? null : () => _choose(p),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: p.color), foregroundColor: p.color),
                    child: const Text('Perpanjang'),
                  )
                : FilledButton(
                    onPressed: blocked ? null : () => _choose(p),
                    style: FilledButton.styleFrom(backgroundColor: p.color),
                    child: Text(blocked ? 'Menunggu konfirmasi pengajuan' : 'Pilih ${p.name}'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusBox({required Color color, required Color bg, required IconData icon, required String title, required String body, Widget? action}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: _t(14.5, c: _ink, w: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: _t(12.5, c: _body)),
            ?action,
          ],
        ),
      );

  Widget _activeCard(Membership m, MembershipPlan? p) {
    final quota = p?.freeDeliveryQuota;
    return _statusBox(
      color: p?.color ?? _green,
      bg: p?.softColor ?? const Color(0xFFF0FDF4),
      icon: Icons.workspace_premium_rounded,
      title: 'Member ${p?.name ?? m.planId} aktif',
      body: [
        'Berlaku sampai ${tanggal(m.endsAt!)} (${m.daysLeft} hari lagi).',
        if (quota != null) 'Gratis ongkir terpakai ${m.freeDeliveryUsed} dari $quota bulan ini.',
        if (m.cancelAtPeriodEnd) 'Tidak diperpanjang setelah periode ini.',
      ].join('\n'),
      action: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _toggleCancel(m),
          style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
          child: Text(m.cancelAtPeriodEnd ? 'Lanjutkan langganan' : 'Berhenti di akhir periode'),
        ),
      ),
    );
  }

  Widget _pendingCard(Membership m, MembershipPlan? p) => _statusBox(
        color: const Color(0xFFB45309),
        bg: const Color(0xFFFFFBEB),
        icon: Icons.hourglass_top_rounded,
        title: 'Menunggu konfirmasi pembayaran',
        body: '${p?.name ?? m.planId} ${m.period == 'yearly' ? 'tahunan' : 'bulanan'} · ${rupiah(m.amount)} · '
            'diajukan ${tanggalJam(m.createdAt)}. Kamu akan mendapat notifikasi setelah admin memeriksa bukti bayar.',
      );

  Widget _rejectedCard(Membership m, MembershipPlan? p) => _statusBox(
        color: _red,
        bg: const Color(0xFFFEF2F2),
        icon: Icons.error_outline_rounded,
        title: 'Pengajuan ${p?.name ?? m.planId} ditolak',
        body: (m.adminNote ?? '').trim().isNotEmpty ? m.adminNote!.trim() : 'Bukti pembayaran tidak sesuai. Silakan ajukan ulang.',
      );
}

// ======================================================================
// CHECKOUT LANGGANAN: bayar manual + unggah bukti
// ======================================================================

class _CheckoutScreen extends StatefulWidget {
  final MembershipPlan plan;
  final String period;
  const _CheckoutScreen({required this.plan, required this.period});

  @override
  State<_CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<_CheckoutScreen> {
  final _service = MembershipService();
  PaymentInfo? _info;
  String? _infoError;
  String _platformQris = ''; // QRIS statis Washora → QR dengan nominal paket
  String _method = 'transfer';
  Uint8List? _proof;
  String _mime = 'image/jpeg';
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WalletService().platformQris().then((q) {
      if (mounted) setState(() => _platformQris = q);
    });
    _service.fetchPaymentInfo().then((i) {
      if (!mounted) return;
      setState(() {
        _info = i;
        if (!i.hasTransfer && i.hasQris) _method = 'qris';
      });
    }).catchError((e) {
      if (mounted) setState(() => _infoError = e.toString());
    });
  }

  bool get _hasDynamicQris => _platformQris.isNotEmpty && Qris.isValid(_platformQris);
  bool get _methodAvailable =>
      _info != null && (_method == 'transfer' ? _info!.hasTransfer : (_hasDynamicQris || _info!.hasQris));

  Future<void> _pickProof(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 75);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        setState(() => _error = 'Ukuran bukti bayar melebihi 3 MB. Pilih foto lain.');
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
    if (_proof == null) {
      setState(() => _error = 'Unggah bukti pembayaran dulu.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.submit(planId: widget.plan.id, period: widget.period, paymentMethod: _method, proof: _proof!, mime: _mime);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(const SnackBar(
        content: Text('Pengajuan terkirim. Kami kabari lewat notifikasi setelah pembayaran dikonfirmasi.'),
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
    final p = widget.plan;
    final amount = p.priceFor(widget.period);
    final info = _info;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text('Bayar ${p.name}', style: _t(17, c: _ink, w: FontWeight.w800)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Member ${p.name}', style: _t(15, c: _ink, w: FontWeight.w800)),
                          Text(widget.period == 'yearly' ? 'Tahunan · 365 hari' : 'Bulanan · 30 hari', style: _t(12, c: _muted)),
                        ],
                      ),
                    ),
                    Text(rupiah(amount), style: _t(20, c: _ink, w: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('1. Pilih cara bayar', style: _t(14, c: _ink, w: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'transfer', label: Text('Transfer bank'), icon: Icon(Icons.account_balance_outlined)),
                  ButtonSegment(value: 'qris', label: Text('QRIS'), icon: Icon(Icons.qr_code_2_rounded)),
                ],
                selected: {_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              const SizedBox(height: 10),
              if (_infoError != null)
                Text(_infoError!, style: _t(12.5, c: _red))
              else if (info == null)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (!_methodAvailable)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    'Info pembayaran ${_method == 'transfer' ? 'transfer bank' : 'QRIS'} belum diatur oleh admin Washora. '
                    'Pilih cara bayar lain atau hubungi admin.',
                    style: _t(12.5, c: _red),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                  child: _method == 'transfer'
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Transfer tepat ${rupiah(amount)} ke:', style: _t(12.5, c: _muted)),
                            const SizedBox(height: 6),
                            Text(info.bankName, style: _t(14, c: _ink, w: FontWeight.w800)),
                            Row(
                              children: [
                                Expanded(child: SelectableText(info.accountNumber, style: _t(18, c: _ink, w: FontWeight.w800))),
                                TextButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: info.accountNumber));
                                    ScaffoldMessenger.of(context).showQuickSnackBar(const SnackBar(content: Text('Nomor rekening disalin.')));
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  label: const Text('Salin'),
                                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                                ),
                              ],
                            ),
                            Text('a.n. ${info.accountName}', style: _t(12.5, c: _body)),
                            if (info.note.isNotEmpty) ...[const SizedBox(height: 6), Text(info.note, style: _t(11.5, c: _muted))],
                          ],
                        )
                      : _hasDynamicQris
                          ? QrisPayCard(payload: _platformQris, amount: amount, title: 'Langganan ${p.name}')
                          : Column(
                          children: [
                            Text('Pindai QRIS lalu bayar tepat ${rupiah(amount)}', style: _t(12.5, c: _muted)),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(info.qrisImageUrl, width: 220, height: 220, fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Text('Gambar QRIS gagal dimuat.', style: _t(12, c: _red))),
                            ),
                            if (info.note.isNotEmpty) ...[const SizedBox(height: 6), Text(info.note, style: _t(11.5, c: _muted))],
                          ],
                        ),
                ),
              const SizedBox(height: 18),
              Text('2. Unggah bukti pembayaran', style: _t(14, c: _ink, w: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_proof != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_proof!, height: 220, width: double.infinity, fit: BoxFit.contain),
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
                        label: const Text('Pilih tangkapan layar'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickProof(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Foto'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
                  onPressed: _sending || !_methodAvailable ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _brand),
                  child: _sending
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(_error != null ? 'Coba lagi' : 'Kirim pengajuan'),
                ),
              ),
              const SizedBox(height: 8),
              Text('Langganan aktif setelah admin mengonfirmasi pembayaranmu.', textAlign: TextAlign.center, style: _t(11.5, c: _faint)),
            ],
          ),
        ),
      ),
    );
  }
}
