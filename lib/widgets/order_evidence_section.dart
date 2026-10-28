import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/evidence_models.dart';
import '../models/order_model.dart';
import '../screens/damage_claim_form_screen.dart';
import '../services/evidence_service.dart';
import 'evidence_widgets.dart';

const _blue = Color(0xFF0077E6);
const _blueLight = Color(0xFFEFF6FF);
const _textDark = Color(0xFF0F172A);
const _textMid = Color(0xFF334155);
const _textLight = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);
const _amber = Color(0xFFD97706);
const _purple = Color(0xFF7C3AED);

String _fmtTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${months[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Bagian halaman Lacak pelanggan: kode serah terima, tombol "Sudah Diterima",
/// foto bukti (penerimaan & serah terima), serta klaim kerusakan & banding.
class OrderEvidenceSection extends StatefulWidget {
  final OrderModel order;
  const OrderEvidenceSection({super.key, required this.order});

  @override
  State<OrderEvidenceSection> createState() => _OrderEvidenceSectionState();
}

class _OrderEvidenceSectionState extends State<OrderEvidenceSection> {
  final EvidenceService _service = EvidenceService();
  List<OrderPhoto> _photos = [];
  DamageClaim? _claim;
  String? _code;
  bool _busy = false;

  OrderModel get _order => widget.order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrderEvidenceSection old) {
    super.didUpdateWidget(old);
    // Status berubah (realtime dari mitra) → muat ulang foto, kode & klaim
    if (old.order.status != _order.status || old.order.intakeAt != _order.intakeAt) _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.getPhotos(_order.id),
      _service.getClaimForOrder(_order.id),
      _order.status == 'done' ? _service.getHandoverCode(_order.id) : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _photos = results[0] as List<OrderPhoto>;
      _claim = results[1] as DamageClaim?;
      _code = results[2] as String?;
    });
  }

  List<OrderPhoto> _stage(String s) => _photos.where((p) => p.stage == s).toList();

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 13)), backgroundColor: color),
    );
  }

  Future<void> _confirmReceived() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cucian sudah diterima?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text(
          'Pastikan cucian sudah ada di tanganmu. Setelah dikonfirmasi, kamu punya waktu 2×24 jam '
          'untuk melaporkan kerusakan jika ada.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Belum')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Sudah Diterima'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _busy = true);
    try {
      final res = await _service.confirmReceived(_order.id);
      if (!mounted) return;
      if (res == 'OK') {
        _snack('Terima kasih! Penerimaan cucian tercatat.', color: _green);
      } else {
        _snack(res == 'NOT_READY' ? 'Pesanan belum selesai diproses outlet.' : 'Konfirmasi gagal ($res).', color: _red);
      }
    } catch (e) {
      if (mounted) _snack(evidenceErrorMessage(e), color: _red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openClaimForm() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DamageClaimFormScreen(order: _order)),
    );
    if (created == true) _load();
  }

  Future<void> _appeal() async {
    final ctrl = TextEditingController();
    String? error;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Ajukan Banding', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tim Washora akan meninjau foto dari kamu dan dari outlet, lalu memberi keputusan akhir.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textLight),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Jelaskan kenapa kamu tidak setuju dengan keputusan outlet',
                  errorText: error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white),
              onPressed: () async {
                if (ctrl.text.trim().length < 10) {
                  setDlg(() => error = 'Minimal 10 karakter');
                  return;
                }
                try {
                  final res = await _service.appealClaim(_claim!.id, ctrl.text);
                  if (res == 'OK') {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setDlg(() => error = res == 'NOT_REJECTED' ? 'Klaim ini tidak bisa dibanding.' : 'Gagal ($res)');
                  }
                } catch (e) {
                  setDlg(() => error = evidenceErrorMessage(e));
                }
              },
              child: const Text('Kirim Banding'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      _snack('Banding terkirim ke tim Washora.', color: _purple);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isCancelled) return const SizedBox.shrink();

    final cards = <Widget>[
      if (_order.status == 'done') _buildHandoverCard(),
      if (_order.status == 'delivered' && _order.receivedAt != null) _buildReceivedCard(),
      if (_claim != null) _buildClaimCard() else if (_order.canClaim) _buildReportCard(),
      if (_order.intakeAt != null || _photos.isNotEmpty) _buildPhotosCard(),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final c in cards) ...[c, const SizedBox(height: 16)],
      ],
    );
  }

  Widget _card({required Widget child, Color borderColor = _border, Color? background}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: _textDark.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 5)),
        ],
      ),
      child: child,
    );
  }

  Widget _title(IconData icon, String text, {Color color = _blue, Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: _textDark)),
        ),
        ?trailing,
      ],
    );
  }

  // ── Kode serah terima + "Sudah Diterima" ──
  Widget _buildHandoverCard() {
    return _card(
      borderColor: _blue.withValues(alpha: 0.35),
      background: _blueLight,
      child: Column(
        children: [
          _title(Icons.handshake_rounded, 'Kode Serah Terima'),
          const SizedBox(height: 6),
          Text(
            _order.isDropoff
                ? 'Tunjukkan kode ini ke kasir saat mengambil cucian di outlet.'
                : 'Sebutkan kode ini ke kurir saat cucian diantar. Jangan berikan sebelum cucian ada di tanganmu.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMid, height: 1.45),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _blue.withValues(alpha: 0.3)),
            ),
            child: Text(
              _code ?? '••••',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 14,
                color: _blue,
              ),
            ),
          ),
          if (_code == null) ...[
            const SizedBox(height: 6),
            Text('Kode belum tersedia. Pastikan SQL bukti & klaim sudah dijalankan.',
                textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textLight)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _confirmReceived,
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text('Sudah Diterima', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Info penerimaan ──
  Widget _buildReceivedCard() {
    final via = switch (_order.receivedBy) {
      'code' => 'dengan kode serah terima',
      'customer' => 'dikonfirmasi olehmu',
      'auto' => 'dikonfirmasi otomatis setelah 2×24 jam',
      _ => '',
    };
    return _card(
      borderColor: _green.withValues(alpha: 0.3),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: _green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Diterima ${_fmtTime(_order.receivedAt!)}${via.isEmpty ? '' : ' • $via'}',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tombol lapor kerusakan (dalam 2×24 jam) ──
  Widget _buildReportCard() {
    final left = _order.receivedAt!.add(OrderModel.claimWindow).difference(DateTime.now());
    final leftText = left.inHours >= 1 ? '${left.inHours} jam' : '${left.inMinutes} menit';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.report_gmailerrorred_rounded, 'Ada yang rusak atau hilang?', color: _amber),
          const SizedBox(height: 6),
          Text(
            'Laporkan dengan foto bukti. Sisa waktu klaim: $leftText.',
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openClaimForm,
              style: OutlinedButton.styleFrom(
                foregroundColor: _amber,
                side: const BorderSide(color: _amber),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text('Laporkan Kerusakan', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status klaim + banding ──
  Widget _buildClaimCard() {
    final claim = _claim!;
    final color = switch (claim.status) {
      'approved' || 'appeal_approved' => _green,
      'rejected' || 'appeal_rejected' => _red,
      'appealed' => _purple,
      _ => _amber,
    };
    return _card(
      borderColor: color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            Icons.assignment_late_outlined,
            'Klaim Kerusakan',
            color: color,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(claim.statusLabel,
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
            ),
          ),
          const SizedBox(height: 10),
          Text(claim.description, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textMid, height: 1.45)),
          const SizedBox(height: 10),
          PhotoGallery(photos: _stage('claim'), size: 64),
          if (claim.isApproved) ...[
            const SizedBox(height: 12),
            Text('Resolusi: ${claim.resolutionLabel}',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
          ],
          if (claim.ownerNote != null) ...[
            const SizedBox(height: 6),
            Text('Catatan outlet: ${claim.ownerNote}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMid)),
          ],
          if (claim.adminNote != null) ...[
            const SizedBox(height: 6),
            Text('Keputusan Washora: ${claim.adminNote}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMid)),
          ],
          if (claim.canAppeal) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _appeal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side: const BorderSide(color: _purple),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.gavel_rounded, size: 18),
                label: Text('Ajukan Banding ke Washora', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Foto bukti dari outlet ──
  Widget _buildPhotosCard() {
    final intake = _stage('intake');
    final handover = _stage('handover');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.photo_library_outlined, 'Foto Bukti dari Outlet'),
          const SizedBox(height: 12),
          Text('Saat diterima outlet', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: _textMid)),
          if (_order.intakeItemCount != null || _order.intakeNote != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (_order.intakeItemCount != null) '${_order.intakeItemCount} item',
                if (_order.intakeNote != null) _order.intakeNote!,
              ].join(' • '),
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight),
            ),
          ],
          const SizedBox(height: 8),
          PhotoGallery(photos: intake, size: 72, emptyText: 'Outlet belum mengunggah foto penerimaan.'),
          if (handover.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Saat diserahkan', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: _textMid)),
            const SizedBox(height: 8),
            PhotoGallery(photos: handover, size: 72),
          ],
        ],
      ),
    );
  }
}
