import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../models/revenue_report.dart';
import '../models/shop_model.dart';
import '../services/report_service.dart';
import '../utils/format_id.dart';
import '../widgets/report_widgets.dart';

/// Riwayat satu pelanggan di outlet ini: total belanja & layanan yang pernah diambil.
class CustomerHistoryScreen extends StatefulWidget {
  final ShopModel shop;

  /// Salah satu pesanan pelanggan, dipakai untuk mengenali pelanggannya
  final OrderModel sample;
  const CustomerHistoryScreen({super.key, required this.shop, required this.sample});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _service = ReportService();
  List<OrderModel>? _orders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await _service.fetchCustomerOrders(widget.shop.id, widget.sample);
      if (mounted) setState(() => _orders = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sample;
    final isApp = s.userId.isNotEmpty;
    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.surface,
        surfaceTintColor: RC.surface,
        foregroundColor: RC.ink,
        elevation: 0,
        title: Text('Riwayat Pelanggan', style: rTitle(18)),
      ),
      body: RefreshIndicator(
        color: RC.brand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: RC.brandSoft, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          customerNameOf(s).characters.first.toUpperCase(),
                          style: rTitle(20).copyWith(color: RC.brand),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customerNameOf(s), style: rTitle(17), overflow: TextOverflow.ellipsis),
                            Text(
                              [
                                isApp ? 'Pelanggan aplikasi' : 'Pelanggan walk-in',
                                if ((s.customerPhone ?? '').isNotEmpty) s.customerPhone!,
                              ].join(' · '),
                              style: rText(12, color: RC.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ..._content(),
          ],
        ),
      ),
    );
  }

  List<Widget> _content() {
    Widget boxed(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
          ),
        );

    if (_error != null) return [boxed(StateView.error(_error!, onRetry: _load))];
    final orders = _orders;
    if (orders == null) return [boxed(const StateView.loading('Memuat riwayat pelanggan…'))];
    if (orders.isEmpty) {
      return [
        boxed(const StateView(
          icon: Icons.person_off_outlined,
          title: 'Riwayat tidak ditemukan',
          message: 'Pesanan pelanggan ini tidak bisa dicocokkan. Walk-in tanpa nomor HP dicocokkan dari nama saja.',
        )),
      ];
    }

    final valid = orders.where((o) => o.status != 'cancelled').toList();
    final spent = valid.fold<int>(0, (s, o) => s + o.totalPrice);
    final first = orders.last.createdAt;
    final last = orders.first.createdAt;

    // Layanan yang pernah diambil: berapa kali & nilainya
    final svc = <String, List<int>>{};
    for (final o in valid) {
      for (final i in o.items) {
        final e = svc.putIfAbsent(i.name.trim().isEmpty ? 'Tanpa nama' : i.name.trim(), () => [0, 0]);
        e[0] += (i.price * i.qty).round();
        e[1]++;
      }
    }
    final services = svc.entries.map((e) => NamedAmount(e.key, e.value[0], e.value[1])).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return [
      boxed(SummaryCard(
        hero: true,
        label: 'Total belanja di ${widget.shop.name}',
        value: rupiah(spent),
        caption: '${valid.length} pesanan · pertama ${tanggal(first)}, terakhir ${tanggal(last)}',
      )),
      const SizedBox(height: 12),
      if (services.isNotEmpty)
        boxed(ReportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Layanan yang pernah diambil', style: rTitle(15)),
              const SizedBox(height: 8),
              RankedBars(items: services, countUnit: 'kali'),
            ],
          ),
        )),
      const SizedBox(height: 16),
      boxed(Text('Semua pesanan (${orders.length})', style: rText(12, color: RC.muted, weight: FontWeight.w600))),
      const SizedBox(height: 8),
      for (var i = 0; i < orders.length; i++) ...[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: TransactionTile(
              order: orders[i],
              showDate: true,
              onTap: () => showTransactionDetail(context, orders[i]),
            ),
          ),
        ),
        if (i < orders.length - 1) const Divider(height: 1, color: RC.border),
      ],
    ];
  }
}
