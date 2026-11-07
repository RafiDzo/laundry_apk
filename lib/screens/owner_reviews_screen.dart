import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/review_model.dart';
import '../models/shop_model.dart';
import '../services/review_service.dart';
import '../widgets/quick_snackbar.dart';
import '../widgets/review_widgets.dart';

const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// Rating & ulasan untuk mitra: ringkasan, tren per bulan, aspek,
/// daftar ulasan yang belum dibalas, balas (sekali) & laporkan.
class OwnerReviewsScreen extends StatefulWidget {
  final ShopModel shop;
  const OwnerReviewsScreen({super.key, required this.shop});

  @override
  State<OwnerReviewsScreen> createState() => _OwnerReviewsScreenState();
}

class _OwnerReviewsScreenState extends State<OwnerReviewsScreen> {
  final _service = ReviewService();
  final _scroll = ScrollController();

  ReviewSummary? _summary;
  String? _summaryError;
  bool _unrepliedOnly = true;
  final List<ReviewModel> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _loadSummary();
    await _reload();
  }

  Future<void> _loadSummary() async {
    try {
      final s = await _service.fetchSummary(widget.shop.id);
      if (mounted) {
        setState(() {
          _summary = s;
          _summaryError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _summaryError = e.toString());
    }
  }

  Future<void> _reload() async {
    _req++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final req = _req;
    setState(() => _loading = true);
    try {
      final rows = await _service.fetchPage(widget.shop.id, page: _page, unrepliedOnly: _unrepliedOnly);
      if (!mounted || req != _req) return;
      setState(() {
        _items.addAll(rows);
        _page++;
        _hasMore = rows.length == ReviewService.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _reply(ReviewModel r) async {
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Balas ulasan ${r.userName}', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: RvC.ink)),
            const SizedBox(height: 4),
            Text('Balasan hanya bisa dikirim sekali dan tampil di halaman outlet.', style: rvText(12, color: RvC.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: r.rating >= 4 ? 'Terima kasih sudah mempercayakan cucian ke kami…' : 'Mohon maaf atas pengalamannya, kami akan…',
                hintStyle: rvText(12.5, color: RvC.faint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                style: FilledButton.styleFrom(backgroundColor: RvC.brand),
                child: const Text('Kirim balasan'),
              ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;
    try {
      final updated = await _service.reply(r.id, text);
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == r.id);
        if (i >= 0) {
          if (_unrepliedOnly) {
            _items.removeAt(i);
          } else {
            _items[i] = updated;
          }
        }
      });
      _loadSummary();
      _snack('Balasan terkirim. Pelanggan mendapat notifikasi.', color: const Color(0xFF15803D));
    } catch (e) {
      _snack(e.toString(), color: const Color(0xFFB91C1C));
    }
  }

  Future<void> _report(ReviewModel r) async {
    const reasons = ['Kata-kata kasar atau menghina', 'Bukan pelanggan / ulasan palsu', 'Berisi data pribadi', 'Spam atau promosi'];
    String? picked;
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Laporkan ulasan', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: RvC.ink)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Text('Tim Washora meninjau laporan. Ulasan tetap tampil selama ditinjau.', style: rvText(12, color: RvC.muted)),
                ),
                RadioGroup<String>(
                  groupValue: picked,
                  onChanged: (v) => setSheet(() => picked = v),
                  child: Column(
                    children: [for (final x in reasons) RadioListTile<String>(value: x, title: Text(x, style: rvText(13.5, color: RvC.ink)))],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: picked == null ? null : () => Navigator.pop(ctx, picked),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
                      child: const Text('Kirim laporan'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (reason == null) return;
    try {
      await _service.report(r.id, reason);
      _snack('Laporan terkirim untuk ditinjau.', color: const Color(0xFF15803D));
    } catch (e) {
      _snack(e.toString(), color: const Color(0xFFB91C1C));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RvC.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: RvC.ink,
        elevation: 0,
        title: Text('Rating & Ulasan', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: RvC.ink)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ..._overview(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _tab('Belum dibalas${_summary != null ? ' (${_summary!.unreplied})' : ''}', true),
                    const SizedBox(width: 8),
                    _tab('Semua ulasan', false),
                  ],
                ),
                const SizedBox(height: 12),
                ..._list(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool unreplied) {
    final sel = _unrepliedOnly == unreplied;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      showCheckmark: false,
      onSelected: (_) {
        if (sel) return;
        setState(() => _unrepliedOnly = unreplied);
        _reload();
      },
      labelStyle: rvText(12.5, color: sel ? Colors.white : RvC.body, weight: FontWeight.w600),
      selectedColor: RvC.ink,
      backgroundColor: Colors.white,
      side: BorderSide(color: sel ? RvC.ink : RvC.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  List<Widget> _overview() {
    final s = _summary;
    if (s == null) {
      return [
        if (_summaryError != null)
          Text(_summaryError!, style: rvText(12, color: const Color(0xFFB91C1C)))
        else
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ];
    }
    if (s.count == 0) return const [];

    // Aspek tertinggi & terendah (hanya yang pernah dinilai)
    final aspects = s.aspects.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      RatingSummaryCard(summary: s),
      if (s.monthly.isNotEmpty) ...[
        const SizedBox(height: 12),
        _card(
          title: 'Rata-rata rating per bulan',
          subtitle: '6 bulan terakhir · angka di atas batang = rata-rata',
          child: _MonthlyBars(points: s.monthly),
        ),
      ],
      if (aspects.isNotEmpty) ...[
        const SizedBox(height: 12),
        _card(
          title: 'Penilaian per aspek',
          subtitle: aspects.length > 1
              ? 'Terbaik: ${ReviewAspect.byKey(aspects.first.key)?.label} · Perlu perhatian: ${ReviewAspect.byKey(aspects.last.key)?.label}'
              : 'Dari pelanggan yang mengisi penilaian aspek',
          child: Column(
            children: [
              for (final e in aspects)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(width: 120, child: Text(ReviewAspect.byKey(e.key)?.label ?? e.key, style: rvText(12.5, color: RvC.ink))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: e.value / 5,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: RvC.star,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 30,
                        child: Text(formatRating(e.value), textAlign: TextAlign.right, style: rvText(12.5, color: RvC.ink, weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _card({required String title, required String subtitle, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: RvC.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: rvText(14, color: RvC.ink, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle, style: rvText(11.5, color: RvC.muted)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  List<Widget> _list() {
    if (_items.isEmpty) {
      if (_error != null) {
        return [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(_error!, textAlign: TextAlign.center, style: rvText(12.5, color: const Color(0xFFB91C1C))),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _reload, child: const Text('Coba lagi')),
            ]),
          ),
        ];
      }
      if (_loading || _hasMore) {
        return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
      }
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Column(children: [
            Icon(_unrepliedOnly ? Icons.mark_chat_read_outlined : Icons.rate_review_outlined, size: 38, color: RvC.faint),
            const SizedBox(height: 10),
            Text(_unrepliedOnly ? 'Semua ulasan sudah dibalas' : 'Belum ada ulasan',
                style: rvText(14, color: RvC.ink, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              _unrepliedOnly ? 'Ulasan baru dari pelanggan akan muncul di sini.' : 'Ulasan muncul setelah pelanggan menerima cuciannya.',
              textAlign: TextAlign.center,
              style: rvText(12, color: RvC.muted),
            ),
          ]),
        ),
      ];
    }
    return [
      for (final r in _items) ...[
        ReviewCard(
          review: r,
          shopName: widget.shop.name,
          footer: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                if (!r.hasReply)
                  FilledButton.icon(
                    onPressed: () => _reply(r),
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: const Text('Balas'),
                    style: FilledButton.styleFrom(backgroundColor: RvC.brand, minimumSize: const Size(44, 44)),
                  )
                else
                  Text('Sudah dibalas', style: rvText(12, color: const Color(0xFF15803D), weight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _report(r),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Laporkan'),
                  style: TextButton.styleFrom(foregroundColor: RvC.muted, minimumSize: const Size(44, 44)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (_hasMore)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
    ];
  }
}

/// Batang rata-rata rating per bulan (satu seri, skala 0-5, label angka di atas batang)
class _MonthlyBars extends StatelessWidget {
  final List<(DateTime, double, int)> points;
  const _MonthlyBars({required this.points});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (month, avg, count) in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(formatRating(avg), style: rvText(11, color: RvC.ink, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Container(
                      height: 90 * (avg / 5),
                      constraints: const BoxConstraints(maxWidth: 36),
                      decoration: const BoxDecoration(
                        color: RvC.star,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_kMonths[month.month - 1], style: rvText(10.5, color: RvC.muted)),
                    Text('$count ulasan', style: rvText(9.5, color: RvC.faint)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
