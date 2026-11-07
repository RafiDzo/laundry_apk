import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../models/revenue_report.dart';
import '../models/shop_model.dart';
import '../services/report_service.dart';
import '../utils/format_id.dart';
import '../widgets/report_widgets.dart';
import 'customer_history_screen.dart';

/// Semua transaksi hari ini (realtime), terbaru di atas.
class TodayTransactionsScreen extends StatefulWidget {
  final ShopModel shop;
  const TodayTransactionsScreen({super.key, required this.shop});

  @override
  State<TodayTransactionsScreen> createState() => _TodayTransactionsScreenState();
}

class _TodayTransactionsScreenState extends State<TodayTransactionsScreen> {
  final _service = ReportService();
  final _search = TextEditingController();

  static const _statusOptions = ['Semua', 'Diproses', 'Selesai', 'Dibatalkan'];

  StreamSubscription<List<OrderModel>>? _sub;
  Timer? _retry;
  Timer? _midnight;
  List<OrderModel> _orders = [];
  bool _loading = true;
  String? _error;
  int _status = 0;
  String? _payment; // null = semua metode
  String _query = '';

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _retry?.cancel();
    final today = awalHari(DateTime.now());
    // Ganti hari otomatis saat lewat tengah malam
    _midnight?.cancel();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    _midnight = Timer(tomorrow.difference(DateTime.now()) + const Duration(seconds: 1), _listen);

    setState(() {
      _loading = _orders.isEmpty;
      _error = null;
    });
    _sub = _service.watchOrdersSince(widget.shop.id, today).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _orders = list;
          _loading = false;
          _error = null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Koneksi realtime terputus. Menyambung ulang…';
        });
        _retry = Timer(const Duration(seconds: 4), () {
          if (mounted) _listen();
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    _midnight?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<OrderModel> get _filtered {
    final q = _query.trim().toLowerCase();
    return _orders.where((o) {
      final g = statusGroup(o.status);
      if (_status == 1 && g != StatusGroup.diproses) return false;
      if (_status == 2 && g != StatusGroup.selesai) return false;
      if (_status == 3 && g != StatusGroup.dibatalkan) return false;
      if (_payment != null && paymentGroup(o.paymentMethod) != _payment) return false;
      if (q.isEmpty) return true;
      return customerNameOf(o).toLowerCase().contains(q) ||
          nomorTransaksi(o.id).toLowerCase().contains(q) ||
          (o.customerPhone ?? '').contains(q) ||
          o.items.any((i) => i.name.toLowerCase().contains(q));
    }).toList();
  }

  void _openDetail(OrderModel o) {
    showTransactionDetail(
      context,
      o,
      onOpenCustomer: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CustomerHistoryScreen(shop: widget.shop, sample: o)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = _orders.where((o) => o.status != 'cancelled');
    final omzet = valid.fold<int>(0, (s, o) => s + o.totalPrice);
    final counts = {
      for (final g in StatusGroup.values) g: _orders.where((o) => statusGroup(o.status) == g).length,
    };
    final methods = _orders.map((o) => paymentGroup(o.paymentMethod)).toSet().toList()..sort();
    final list = _filtered;

    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.surface,
        surfaceTintColor: RC.surface,
        foregroundColor: RC.ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transaksi Hari Ini', style: rTitle(18)),
            Text(tanggal(DateTime.now()), style: rText(11.5, color: RC.muted)),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: RC.brand,
        onRefresh: () async => _listen(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SummaryCard(
                          hero: true,
                          label: 'Omzet hari ini',
                          value: rupiah(omzet),
                          caption: '${valid.length} transaksi tercatat · diperbarui otomatis',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _countPill('Diproses', counts[StatusGroup.diproses]!, RC.warn, RC.warnBg),
                            const SizedBox(width: 8),
                            _countPill('Selesai', counts[StatusGroup.selesai]!, RC.good, RC.goodBg),
                            const SizedBox(width: 8),
                            _countPill('Batal', counts[StatusGroup.dibatalkan]!, RC.bad, RC.badBg),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: RC.warnBg, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                const Icon(Icons.sync_problem_rounded, size: 18, color: RC.warn),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: rText(12, color: RC.warn))),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: _search,
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Cari nama, no. transaksi, atau layanan',
                            hintStyle: rText(13, color: RC.faint),
                            prefixIcon: const Icon(Icons.search_rounded, color: RC.muted),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Hapus pencarian',
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                            filled: true,
                            fillColor: RC.surface,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: RC.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: RC.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: RC.brand),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FilterBar(
                options: _statusOptions,
                selected: _status,
                onSelected: (i) => setState(() => _status = i),
              ),
            ),
            if (methods.length > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilterBar(
                    options: ['Semua metode', ...methods],
                    selected: _payment == null ? 0 : methods.indexOf(_payment!) + 1,
                    onSelected: (i) => setState(() => _payment = i == 0 ? null : methods[i - 1]),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ..._listSlivers(list),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _listSlivers(List<OrderModel> list) {
    Widget boxed(Widget child) => SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
          ),
        );

    if (_loading) return [boxed(const StateView.loading('Memuat transaksi hari ini…'))];
    if (_orders.isEmpty) {
      return [
        boxed(const StateView(
          icon: Icons.receipt_long_outlined,
          title: 'Belum ada transaksi hari ini',
          message: 'Pesanan dari aplikasi dan kasir walk-in akan muncul di sini begitu masuk.',
        )),
      ];
    }
    if (list.isEmpty) {
      return [
        boxed(StateView(
          icon: Icons.filter_alt_off_outlined,
          title: 'Tidak ada transaksi yang cocok',
          message: 'Ada ${_orders.length} transaksi hari ini, tapi tidak ada yang sesuai filter atau pencarian.',
          actionLabel: 'Reset filter',
          onAction: () {
            _search.clear();
            setState(() {
              _query = '';
              _status = 0;
              _payment = null;
            });
          },
        )),
      ];
    }
    return [
      boxed(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('${list.length} transaksi', style: rText(12, color: RC.muted, weight: FontWeight.w600)),
      )),
      SliverList.separated(
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: RC.border),
        itemBuilder: (_, i) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: TransactionTile(order: list[i], onTap: () => _openDetail(list[i])),
          ),
        ),
      ),
    ];
  }

  Widget _countPill(String label, int count, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: RC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: RC.border)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
              child: Text('$count', style: rText(12.5, color: fg, weight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: rText(12, color: RC.body), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
