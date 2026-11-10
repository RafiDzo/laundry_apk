import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/evidence_models.dart';
import '../utils/format_id.dart';

const _ink = Color(0xFF0F172A);
const _body = Color(0xFF334155);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _green = Color(0xFF15803D);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _purple = Color(0xFF6D28D9);

TextStyle _t(double s, {Color c = _body, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: s, fontWeight: w, color: c);

/// Sisa waktu "2 hari 3 jam" / "5 jam" / "20 menit"
String claimTimeLeft(Duration d) {
  if (d.isNegative) return 'lewat batas';
  if (d.inHours >= 24) return '${d.inDays} hari ${d.inHours % 24} jam';
  if (d.inHours >= 1) return '${d.inHours} jam';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} menit';
}

/// Ringkasan isi klaim: jenis kerusakan, item terdampak, penyelesaian yang diminta
class ClaimSummary extends StatelessWidget {
  final DamageClaim claim;
  const ClaimSummary({super.key, required this.claim});

  @override
  Widget build(BuildContext context) {
    final c = claim;
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: _muted),
              const SizedBox(width: 8),
              SizedBox(width: 108, child: Text(label, style: _t(12, c: _muted))),
              Expanded(child: Text(value, style: _t(12.5, c: _ink, w: FontWeight.w600))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.categoryLabel != null) row(Icons.report_problem_outlined, 'Jenis kerusakan', c.categoryLabel!),
        if (c.affectedItems.isNotEmpty) row(Icons.checkroom_outlined, 'Item terdampak', c.affectedItems.join(', ')),
        if (c.requestedResolution != null) row(Icons.handshake_outlined, 'Diminta', c.requestedLabel),
      ],
    );
  }
}

/// Timeline status klaim dengan waktu tiap tahap & batas respons outlet
class ClaimTimeline extends StatelessWidget {
  final DamageClaim claim;
  const ClaimTimeline({super.key, required this.claim});

  @override
  Widget build(BuildContext context) {
    final c = claim;
    final rejected = c.status == 'rejected' || c.status == 'appeal_rejected';
    final steps = <(String, String?, Color, bool)>[
      ('Klaim diajukan', tanggalJam(c.createdAt), _green, true),
    ];

    if (c.isPending) {
      final left = c.responseDeadline.difference(DateTime.now());
      steps.add((
        c.isOverdue ? 'Outlet belum merespons (lewat 2×24 jam)' : 'Menunggu respons outlet',
        c.isOverdue ? 'Batas ${tanggalJam(c.responseDeadline)}' : 'Sisa ${claimTimeLeft(left)} · batas ${tanggalJam(c.responseDeadline)}',
        c.isOverdue ? _red : _amber,
        false,
      ));
    } else if (c.decidedAt != null) {
      steps.add((
        c.resolution != null ? 'Disetujui outlet: ${c.resolutionLabel}' : 'Ditolak outlet',
        tanggalJam(c.decidedAt!),
        c.resolution != null ? _green : _red,
        true,
      ));
    }

    if (c.appealedAt != null || c.status.startsWith('appeal')) {
      steps.add((
        c.escalated ? 'Dinaikkan ke Washora' : 'Banding ke Washora',
        c.appealedAt == null ? null : tanggalJam(c.appealedAt!),
        _purple,
        c.status != 'appealed',
      ));
      if (c.status == 'appealed') {
        steps.add(('Tim Washora meninjau bukti kedua pihak', null, _amber, false));
      } else if (c.status == 'appeal_approved' || c.status == 'appeal_rejected') {
        steps.add((c.status == 'appeal_approved' ? 'Banding disetujui' : 'Banding ditolak', null,
            c.status == 'appeal_approved' ? _green : _red, true));
      }
    }

    if (c.awaitingSettlement) {
      steps.add((c.resolution == 'rewash' ? 'Menunggu cuci ulang selesai' : 'Menunggu ganti rugi dibayarkan', null, _amber, false));
    }
    if (c.isResolved) {
      steps.add(('Selesai', c.resolvedAt == null ? c.resolvedNote : '${tanggalJam(c.resolvedAt!)}${c.resolvedNote != null ? ' · ${c.resolvedNote}' : ''}', _green, true));
    } else if (rejected && c.status == 'appeal_rejected') {
      steps.add(('Klaim ditutup', null, _faint, true));
    }

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: steps[i].$4 ? steps[i].$3 : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: steps[i].$3, width: 2),
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(child: Container(width: 2, color: _border)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(steps[i].$1, style: _t(13, c: _ink, w: FontWeight.w700)),
                        if (steps[i].$2 != null) Text(steps[i].$2!, style: _t(11.5, c: _muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bandingkan foto saat cucian diterima outlet dengan foto bukti klaim, berdampingan
class BeforeAfterCompare extends StatefulWidget {
  final List<OrderPhoto> before; // intake
  final List<OrderPhoto> after; // claim
  const BeforeAfterCompare({super.key, required this.before, required this.after});

  @override
  State<BeforeAfterCompare> createState() => _BeforeAfterCompareState();
}

class _BeforeAfterCompareState extends State<BeforeAfterCompare> {
  int _b = 0;
  int _a = 0;

  Widget _side(String label, List<OrderPhoto> photos, int index, ValueChanged<int> onChange, Color tone) {
    final photo = photos.isEmpty ? null : photos[index.clamp(0, photos.length - 1)];
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: _t(12, c: _ink, w: FontWeight.w700))),
              if (photos.length > 1) Text('${index + 1}/${photos.length}', style: _t(11, c: _muted)),
            ],
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: photo?.url == null
                  ? Container(
                      color: const Color(0xFFF8FAFC),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: Text(photos.isEmpty ? 'Tidak ada foto' : 'Foto gagal dimuat',
                          textAlign: TextAlign.center, style: _t(11.5, c: _faint)),
                    )
                  : GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _FullPhoto(url: photo.url!))),
                      child: Image.network(photo!.url!, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFF8FAFC), child: Icon(Icons.broken_image_outlined, color: _faint))),
                    ),
            ),
          ),
          if (photos.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Foto sebelumnya',
                  onPressed: index > 0 ? () => onChange(index - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Foto berikutnya',
                  onPressed: index < photos.length - 1 ? () => onChange(index + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          if (photo != null) Text(tanggalJam(photo.createdAt), style: _t(10.5, c: _faint)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _side('Saat diterima outlet', widget.before, _b, (i) => setState(() => _b = i), const Color(0xFF0077B6)),
        const SizedBox(width: 10),
        _side('Bukti klaim', widget.after, _a, (i) => setState(() => _a = i), _red),
      ],
    );
  }
}

class _FullPhoto extends StatelessWidget {
  final String url;
  const _FullPhoto({required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url))),
      );
}
