import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/review_model.dart';
import '../services/review_service.dart';
import '../widgets/review_widgets.dart';

/// Semua ulasan satu outlet: ringkasan, filter/urutan, dimuat per halaman.
class ShopReviewsScreen extends StatefulWidget {
  final String shopId;
  final String shopName;
  final ReviewSummary? summary;
  const ShopReviewsScreen({super.key, required this.shopId, required this.shopName, this.summary});

  @override
  State<ShopReviewsScreen> createState() => _ShopReviewsScreenState();
}

class _ShopReviewsScreenState extends State<ShopReviewsScreen> {
  final _service = ReviewService();
  final _scroll = ScrollController();
  static const _filters = ['Terbaru', 'Rating tertinggi', 'Rating terendah', 'Dengan foto'];

  late ReviewSummary? _summary = widget.summary;
  int _filter = 0;
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
    if (_summary == null) {
      _service.fetchSummary(widget.shopId).then((s) {
        if (mounted) setState(() => _summary = s);
      }).catchError((_) {});
    }
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.fetchPage(
        widget.shopId,
        page: _page,
        sort: switch (_filter) { 1 => ReviewSort.highest, 2 => ReviewSort.lowest, _ => ReviewSort.newest },
        withPhotosOnly: _filter == 3,
      );
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

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      backgroundColor: RvC.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: RvC.ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ulasan Pelanggan', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: RvC.ink)),
            Text(widget.shopName, style: rvText(11.5, color: RvC.muted)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (s != null && s.count > 0) RatingSummaryCard(summary: s),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ChoiceChip(
                      label: Text(i == 3 && s != null ? '${_filters[i]} (${s.withPhotos})' : _filters[i]),
                      selected: _filter == i,
                      onSelected: (_) {
                        if (_filter == i) return;
                        setState(() => _filter = i);
                        _reload();
                      },
                      labelStyle: rvText(12.5, color: _filter == i ? Colors.white : RvC.body, weight: FontWeight.w600),
                      selectedColor: RvC.ink,
                      backgroundColor: Colors.white,
                      showCheckmark: false,
                      side: BorderSide(color: _filter == i ? RvC.ink : RvC.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
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

  List<Widget> _list() {
    if (_items.isEmpty) {
      if (_error != null) {
        return [
          _state(Icons.wifi_off_rounded, 'Ulasan gagal dimuat', _error!, action: ('Coba lagi', _reload)),
        ];
      }
      if (_loading || _hasMore) {
        return [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
      }
      return [
        _filter == 3
            ? _state(Icons.photo_library_outlined, 'Belum ada ulasan dengan foto', 'Coba filter lain untuk melihat semua ulasan.')
            : _state(Icons.rate_review_outlined, 'Belum ada ulasan', 'Ulasan muncul setelah pelanggan menerima cuciannya.'),
      ];
    }
    return [
      for (final r in _items) ...[
        ReviewCard(review: r, shopName: widget.shopName),
        const SizedBox(height: 10),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: _error != null
              ? TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Gagal memuat. Coba lagi'),
                )
              : _hasMore
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Semua ulasan sudah ditampilkan', style: rvText(11.5, color: RvC.faint)),
        ),
      ),
    ];
  }

  Widget _state(IconData icon, String title, String message, {(String, VoidCallback)? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 38, color: RvC.faint),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: rvText(14, color: RvC.ink, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: rvText(12, color: RvC.muted)),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action.$2, style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)), child: Text(action.$1)),
          ],
        ],
      ),
    );
  }
}
