import 'package:flutter/material.dart';
import '../widgets/quick_snackbar.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/evidence_models.dart';
import '../models/order_model.dart';
import '../services/evidence_service.dart';
import '../services/supabase_service.dart';
import '../widgets/evidence_widgets.dart';
import '../widgets/claim_widgets.dart';
import 'chat_room_screen.dart';

const _primary = Color(0xFF0077B6);
const _textDark = Color(0xFF0F172A);
const _textMid = Color(0xFF334155);
const _textLight = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

Color claimStatusColor(String status) {
  switch (status) {
    case 'pending':
      return const Color(0xFFD97706);
    case 'approved':
    case 'appeal_approved':
      return const Color(0xFF16A34A);
    case 'resolved':
      return const Color(0xFF0F766E);
    case 'rejected':
    case 'appeal_rejected':
      return const Color(0xFFDC2626);
    case 'appealed':
      return const Color(0xFF7C3AED);
    default:
      return _textLight;
  }
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${months[d.month - 1]} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Daftar klaim kerusakan di outlet mitra (realtime)
class OwnerClaimsScreen extends StatelessWidget {
  final String shopId;
  const OwnerClaimsScreen({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text('Klaim Kerusakan', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, color: _textDark)),
        iconTheme: const IconThemeData(color: _textDark),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: StreamBuilder<List<DamageClaim>>(
            stream: EvidenceService().getShopClaims(shopId),
            builder: (context, snap) {
              if (snap.hasError) {
                return _empty('Gagal memuat klaim. Pastikan SQL supabase_bukti_klaim.sql sudah dijalankan.');
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final claims = snap.data!;
              if (claims.isEmpty) {
                return _empty('Belum ada klaim kerusakan. Klaim dari pelanggan akan muncul di sini, '
                    'lengkap dengan foto pembanding saat cucian diterima.');
              }
              // Urutan kerja: yang lewat batas & menunggu di atas
              final sorted = [...claims]..sort((a, b) {
                  int rank(DamageClaim c) => c.isOverdue ? 0 : (c.isPending ? 1 : (c.awaitingSettlement ? 2 : 3));
                  final r = rank(a).compareTo(rank(b));
                  return r != 0 ? r : b.createdAt.compareTo(a.createdAt);
                });
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ClaimStatsCard(shopId: shopId, claims: claims),
                  const SizedBox(height: 14),
                  for (final c in sorted) ...[
                    _ClaimCard(claim: c),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.inter(color: _textLight)),
        ),
      );
}

/// Statistik klaim: menunggu, lewat batas, rata-rata waktu respons, tingkat klaim
class _ClaimStatsCard extends StatelessWidget {
  final String shopId;
  final List<DamageClaim> claims;
  const _ClaimStatsCard({required this.shopId, required this.claims});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ClaimStats?>(
      future: EvidenceService().claimStats(shopId),
      builder: (context, snap) {
        final st = snap.data;
        final pending = claims.where((c) => c.isPending).length;
        final overdue = claims.where((c) => c.isOverdue).length;
        final settle = claims.where((c) => c.awaitingSettlement).length;
        Widget tile(String value, String label, Color color) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: GoogleFonts.quicksand(fontSize: 20, fontWeight: FontWeight.w800, color: _textDark)),
                    Text(label, style: GoogleFonts.inter(fontSize: 11, color: _textMid, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  tile('$pending', 'Menunggu', const Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  tile('$overdue', 'Lewat 2x24 jam', const Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  tile('$settle', 'Perlu dituntaskan', const Color(0xFF0077B6)),
                ],
              ),
              if (st != null) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    if (st.avgResponseHours != null) 'Rata-rata respons ${st.avgResponseHours!.toStringAsFixed(1).replaceAll('.', ',')} jam',
                    if (st.approvedRate != null) '${st.approvedRate}% klaim diberi penyelesaian',
                    if (st.claimRatePct != null) '${st.claimRatePct!.toStringAsFixed(1).replaceAll('.', ',')} klaim per 100 pesanan selesai',
                  ].join(' · '),
                  style: GoogleFonts.inter(fontSize: 11.5, color: _textLight),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ClaimCard extends StatelessWidget {
  final DamageClaim claim;
  const _ClaimCard({required this.claim});

  @override
  Widget build(BuildContext context) {
    final color = claimStatusColor(claim.status);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OwnerClaimDetailScreen(claim: claim)),
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: claim.isPending ? color.withValues(alpha: 0.5) : _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Pesanan #${claim.orderId.substring(0, 8).toUpperCase()}',
                  style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: _textDark),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(claim.statusLabel,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ),
            if (claim.categoryLabel != null) ...[
              const SizedBox(height: 6),
              Text(claim.categoryLabel!, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _textDark)),
            ],
            const SizedBox(height: 6),
            Text(claim.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: _textMid)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Diajukan ${_formatDate(claim.createdAt)}',
                      style: GoogleFonts.inter(fontSize: 11, color: _textLight)),
                ),
                if (claim.isPending)
                  Text(
                    claim.isOverdue
                        ? 'Lewat batas respons'
                        : 'Sisa ${claimTimeLeft(claim.responseDeadline.difference(DateTime.now()))}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: claim.isOverdue ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    ),
                  )
                else if (claim.awaitingSettlement)
                  Text('Perlu dituntaskan',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0077B6))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail klaim: bandingkan foto penerimaan vs foto klaim, lalu putuskan
class OwnerClaimDetailScreen extends StatefulWidget {
  final DamageClaim claim;
  const OwnerClaimDetailScreen({super.key, required this.claim});

  @override
  State<OwnerClaimDetailScreen> createState() => _OwnerClaimDetailScreenState();
}

class _OwnerClaimDetailScreenState extends State<OwnerClaimDetailScreen> {
  final EvidenceService _evidence = EvidenceService();
  late DamageClaim _claim = widget.claim;
  OrderModel? _order;
  List<OrderPhoto> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SupabaseService().getOrderById(_claim.orderId),
      _evidence.getPhotos(_claim.orderId),
      _evidence.getClaimForOrder(_claim.orderId),
    ]);
    if (!mounted) return;
    setState(() {
      _order = results[0] as OrderModel?;
      _photos = results[1] as List<OrderPhoto>;
      _claim = (results[2] as DamageClaim?) ?? _claim;
      _loading = false;
    });
  }

  List<OrderPhoto> _stage(String s) => _photos.where((p) => p.stage == s).toList();

  Future<void> _showDecision({required bool approve}) async {
    // Isi awal dari permintaan pelanggan
    String resolution = _claim.requestedResolution ?? 'rewash';
    final amountCtrl = TextEditingController(text: _claim.requestedAmount?.toString() ?? '');
    final cap = await _evidence.compensationCap(_claim.orderId, _claim.affectedItems);
    if (!mounted) return;
    final noteCtrl = TextEditingController();
    bool busy = false;
    String? error;

    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(approve ? 'Setujui Klaim' : 'Tolak Klaim',
                    style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
                const SizedBox(height: 16),
                if (approve) ...[
                  RadioGroup<String>(
                    groupValue: resolution,
                    onChanged: (v) => setSheet(() => resolution = v!),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'rewash',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Cuci ulang gratis', style: GoogleFonts.inter(fontSize: 14)),
                        ),
                        RadioListTile<String>(
                          value: 'compensation',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Ganti rugi uang', style: GoogleFonts.inter(fontSize: 14)),
                          subtitle: Text('Tandai selesai setelah uang ditransfer', style: GoogleFonts.inter(fontSize: 11.5, color: _textLight)),
                        ),
                        RadioListTile<String>(
                          value: 'points',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Kredit poin Washora', style: GoogleFonts.inter(fontSize: 14)),
                          subtitle: Text('Langsung masuk saldo pelanggan, klaim otomatis selesai', style: GoogleFonts.inter(fontSize: 11.5, color: _textLight)),
                        ),
                      ],
                    ),
                  ),
                  if (resolution == 'compensation' || resolution == 'points')
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: resolution == 'points' ? 'Jumlah poin (1 poin = Rp 1)' : 'Nominal Ganti Rugi',
                        prefixText: resolution == 'points' ? null : 'Rp ',
                        helperText: resolution == 'compensation' && cap != null
                            ? 'Maksimal Rp ${cap.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} (10x harga layanan item terdampak)'
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: approve ? 'Catatan untuk pelanggan (opsional)' : 'Alasan penolakan (wajib)',
                    hintText: approve ? null : 'Mis. kerusakan sudah tercatat di foto penerimaan',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626))),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: approve ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: busy
                        ? null
                        : () async {
                            final amount = int.tryParse(amountCtrl.text) ?? 0;
                            if (approve && (resolution == 'compensation' || resolution == 'points') && amount <= 0) {
                              setSheet(() => error = resolution == 'points' ? 'Isi jumlah poin.' : 'Isi nominal ganti rugi.');
                              return;
                            }
                            if (approve && resolution == 'compensation' && cap != null && amount > cap) {
                              setSheet(() => error = 'Melebihi batas ganti rugi (10x harga layanan item terdampak).');
                              return;
                            }
                            if (!approve && noteCtrl.text.trim().length < 5) {
                              setSheet(() => error = 'Tulis alasan penolakan (min. 5 karakter).');
                              return;
                            }
                            setSheet(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              final res = await _evidence.decideClaim(
                                claimId: _claim.id,
                                approve: approve,
                                resolution: approve ? resolution : null,
                                amount: approve && (resolution == 'compensation' || resolution == 'points') ? amount : null,
                                note: noteCtrl.text,
                              );
                              if (res == 'OK') {
                                if (ctx.mounted) Navigator.pop(ctx, true);
                                return;
                              }
                              setSheet(() {
                                busy = false;
                                error = switch (res) {
                                  'NOT_PENDING' => 'Klaim ini sudah diputuskan sebelumnya.',
                                  'NOT_ALLOWED' => 'Akun ini bukan pemilik outlet.',
                                  _ => 'Data keputusan belum lengkap.',
                                };
                              });
                            } catch (e) {
                              setSheet(() {
                                busy = false;
                                error = evidenceErrorMessage(e);
                              });
                            }
                          },
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(approve ? 'Setujui' : 'Tolak',
                            style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(content: Text(approve ? 'Klaim disetujui. Pelanggan sudah diberi tahu.' : 'Klaim ditolak. Pelanggan sudah diberi tahu.')),
      );
      _load();
    }
  }

  Future<void> _resolve() async {
    final noteCtrl = TextEditingController(
        text: _claim.resolution == 'rewash' ? 'Cuci ulang sudah selesai dan diserahkan.' : 'Ganti rugi sudah ditransfer.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai klaim selesai?'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Catatan untuk pelanggan'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Selesai')),
        ],
      ),
    );
    final note = noteCtrl.text;
    noteCtrl.dispose();
    if (ok != true) return;
    try {
      final res = await _evidence.resolveClaim(_claim.id, note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(
        content: Text(res == 'OK' ? 'Klaim ditandai selesai. Pelanggan sudah diberi tahu.' : 'Klaim belum bisa ditandai selesai ($res).'),
      ));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(evidenceErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = claimStatusColor(_claim.status);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text('Detail Klaim', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, color: _textDark)),
        iconTheme: const IconThemeData(color: _textDark),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(
                      title: 'Laporan Pelanggan',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_claim.statusLabel,
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                      ),
                      children: [
                        ClaimSummary(claim: _claim),
                        const SizedBox(height: 6),
                        Text(_claim.description, style: GoogleFonts.inter(fontSize: 14, color: _textDark, height: 1.5)),
                        const SizedBox(height: 6),
                        Text('Diajukan ${_formatDate(_claim.createdAt)}',
                            style: GoogleFonts.inter(fontSize: 11, color: _textLight)),
                        if (_order != null && _order!.userId.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => openChatForOrder(context, _claim.orderId),
                            icon: const Icon(Icons.forum_outlined, size: 18),
                            label: const Text('Diskusikan dengan pelanggan'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                          ),
                        ],
                      ],
                    ),
                    _section(
                      title: 'Bandingkan Bukti',
                      children: [
                        BeforeAfterCompare(before: _stage('intake'), after: _stage('claim')),
                      ],
                    ),
                    _section(
                      title: 'Perjalanan Klaim',
                      children: [ClaimTimeline(claim: _claim)],
                    ),
                    _section(
                      title: 'Foto Saat Diterima Outlet',
                      children: [
                        if (_order?.intakeItemCount != null)
                          Text('Jumlah item: ${_order!.intakeItemCount}',
                              style: GoogleFonts.inter(fontSize: 13, color: _textMid)),
                        if (_order?.intakeNote != null) ...[
                          const SizedBox(height: 4),
                          Text('Catatan: ${_order!.intakeNote}',
                              style: GoogleFonts.inter(fontSize: 13, color: _textMid)),
                        ],
                        const SizedBox(height: 10),
                        PhotoGallery(
                          photos: _stage('intake'),
                          size: 72,
                          emptyText: 'Tidak ada foto penerimaan untuk pesanan ini.',
                        ),
                      ],
                    ),
                    _section(
                      title: 'Foto Serah Terima',
                      children: [
                        PhotoGallery(photos: _stage('handover'), size: 96, emptyText: 'Tidak ada foto serah terima.'),
                      ],
                    ),
                    if (!_claim.isPending)
                      _section(
                        title: 'Keputusan',
                        children: [
                          if (_claim.isApproved || _claim.resolution != null)
                            Text('Resolusi: ${_claim.resolutionLabel}',
                                style: GoogleFonts.inter(fontSize: 13, color: _textDark, fontWeight: FontWeight.w600)),
                          if (_claim.ownerNote != null) ...[
                            const SizedBox(height: 4),
                            Text('Catatan outlet: ${_claim.ownerNote}', style: GoogleFonts.inter(fontSize: 13, color: _textMid)),
                          ],
                          if (_claim.appealReason != null) ...[
                            const SizedBox(height: 8),
                            Text('Alasan banding pelanggan: ${_claim.appealReason}',
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF7C3AED))),
                          ],
                          if (_claim.adminNote != null) ...[
                            const SizedBox(height: 4),
                            Text('Keputusan Washora: ${_claim.adminNote}', style: GoogleFonts.inter(fontSize: 13, color: _textMid)),
                          ],
                        ],
                      ),
                    if (_claim.awaitingSettlement) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _resolve,
                          icon: const Icon(Icons.task_alt_rounded),
                          label: Text(_claim.resolution == 'rewash' ? 'Cuci ulang selesai — tandai selesai' : 'Ganti rugi sudah dibayar — tandai selesai'),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_claim.isPending) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFDC2626)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _showDecision(approve: false),
                              child: const Text('Tolak'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _showDecision(approve: true),
                              child: const Text('Setujui'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Jika ditolak, pelanggan dapat mengajukan banding ke tim Washora.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 11, color: _textLight),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _section({required String title, Widget? trailing, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: _primary)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
