import 'dart:async';

import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../services/report_service.dart';
import '../utils/format_id.dart';
import '../widgets/report_widgets.dart';
import 'customer_history_screen.dart';

/// Riwayat pesanan yang sudah selesai dilayani (status Selesai / Diserahkan),
/// dimuat per halaman saat digulir.
class ServiceHistoryScreen extends StatefulWidget {
  final ShopModel shop;
  const ServiceHistoryScreen({super.key, required this.shop});

  @override
  State<ServiceHistoryScreen> createState() => _ServiceHistoryScreenState();
}

class _ServiceHistoryScreenState extends State<ServiceHistoryScreen> {
  final _service = ReportService();
  final _scroll = ScrollController();
  final _customerCtrl = TextEditingController();
  Timer? _debounce;

  static const _periods = ['Semua', '7 Hari', '30 Hari', 'Pilih Tanggal'];
  int _period = 0;
  DateTimeRange? _custom;
  String? _serviceName; // null = semua layanan
  String _customer = '';

  final List<OrderModel> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _customerCtrl.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _range {
    final today = awalHari(DateTime.now());
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    switch (_period) {
      case 1:
        return (DateTime(today.year, today.month, today.day - 6), tomorrow);
      case 2:
        return (DateTime(today.year, today.month, today.day - 29), tomorrow);
      case 3:
        final end = awalHari(_custom!.end);
        return (awalHari(_custom!.start), DateTime(end.year, end.month, end.day + 1));
      default:
        return (null, null);
    }
  }

  /// Nama layanan untuk filter: dari daftar layanan outlet
  List<String> get _serviceNames {
    final names = widget.shop.services.map((s) => s.name.trim()).where((n) => n.isNotEmpty).toSet().toList();
    names.sort();
    return names;
  }

  Future<void> _reload() async {
    _request++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final req = _request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _range;
    try {
      final rows = await _service.fetchServiceHistory(
        shopId: widget.shop.id,
        page: _page,
        from: from,
        to: to,
        service: _serviceName,
        customer: _customer,
      );
      if (!mounted || req != _request) return;
      setState(() {
        _items.addAll(rows);
        _page++;
        _hasMore = rows.length == ReportService.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _request) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectPeriod(int i) async {
    if (i == 3) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: _custom,
        helpText: 'Pilih rentang riwayat',
        saveText: 'Terapkan',
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: RC.brand)),
          child: child!,
        ),
      );
      if (picked == null) return;
      _custom = picked;
    }
    setState(() => _period = i);
    _reload();
  }

  void _onCustomerChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (v.trim() == _customer) return;
      _customer = v.trim();
      _reload();
    });
  }

  void _openDetail(OrderModel o) {
    showTransactionDetail(context, o, onOpenCustomer: () => _openCustomer(o));
  }

  void _openCustomer(OrderModel o) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CustomerHistoryScreen(shop: widget.shop, sample: o)),
    );
  }

  bool get _filtered => _period != 0 || _serviceName != null || _customer.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.surface,
        surfaceTintColor: RC.surface,
        foregroundColor: RC.ink,
        elevation: 0,
        title: Text('Riwayat Layanan', style: rTitle(18)),
      ),
      body: RefreshIndicator(
        color: RC.brand,
        onRefresh: _reload,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _filters()),
            ..._list(),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    final services = _serviceNames;
    return Container(
      color: RC.surface,
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterBar(options: _periods, selected: _period, onSelected: _selectPeriod),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(builder: (context, c) {
                  final search = TextField(
                    controller: _customerCtrl,
                    onChanged: _onCustomerChanged,
                    decoration: _inputDeco('Cari pelanggan / no. HP', Icons.person_search_outlined),
                  );
                  final service = DropdownButtonFormField<String?>(
                    key: ValueKey(_serviceName),
                    initialValue: _serviceName,
                    isExpanded: true,
                    decoration: _inputDeco('Layanan', Icons.local_laundry_service_outlined),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Semua layanan')),
                      for (final s in services)
                        DropdownMenuItem<String?>(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setState(() => _serviceName = v);
                      _reload();
                    },
                  );
                  if (c.maxWidth < 520) {
                    return Column(children: [search, const SizedBox(height: 10), service]);
                  }
                  return Row(children: [
                    Expanded(flex: 3, child: search),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: service),
                  ]);
                }),
              ),
              if (_period == 3 && _custom != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text('${tanggal(_custom!.start)} - ${tanggal(_custom!.end)}',
                      style: rText(12, color: RC.muted)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        labelText: null,
        hintStyle: rText(13, color: RC.faint),
        prefixIcon: Icon(icon, color: RC.muted, size: 20),
        filled: true,
        fillColor: RC.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RC.brand),
        ),
      );

  List<Widget> _list() {
    Widget boxed(Widget child) => SliverToBoxAdapter(
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child)),
        );

    if (_items.isEmpty) {
      if (_error != null) return [boxed(StateView.error(_error!, onRetry: _reload))];
      if (_loading || _hasMore) return [boxed(const StateView.loading('Memuat riwayat layanan…'))];
      return [
        boxed(_filtered
            ? StateView(
                icon: Icons.filter_alt_off_outlined,
                title: 'Tidak ada riwayat yang cocok',
                message: 'Coba ubah periode, layanan, atau kata pencarian.',
                actionLabel: 'Reset filter',
                onAction: () {
                  _customerCtrl.clear();
                  _customer = '';
                  _serviceName = null;
                  _period = 0;
                  _reload();
                },
              )
            : const StateView(
                icon: Icons.history_rounded,
                title: 'Belum ada layanan yang selesai',
                message: 'Pesanan masuk ke riwayat setelah statusnya diubah menjadi Selesai di dashboard.',
              )),
      ];
    }

    // Kelompokkan per tanggal (timeline)
    final children = <Widget>[];
    DateTime? currentDay;
    for (var i = 0; i < _items.length; i++) {
      final o = _items[i];
      final day = awalHari(o.createdAt);
      if (day != currentDay) {
        currentDay = day;
        final dayOrders = _items.where((x) => awalHari(x.createdAt) == day);
        final dayTotal = dayOrders.fold<int>(0, (s, x) => s + x.totalPrice);
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(16, children.isEmpty ? 4 : 18, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('${kHariSingkat[day.weekday - 1]}, ${tanggal(day)}',
                    style: rText(12.5, color: RC.ink, weight: FontWeight.w700)),
              ),
              Text('${dayOrders.length} layanan · ${rupiah(dayTotal)}', style: rText(11.5, color: RC.muted)),
            ],
          ),
        ));
      } else {
        children.add(const Divider(height: 1, color: RC.border));
      }
      children.add(_HistoryRow(order: o, onTap: () => _openDetail(o), onCustomer: () => _openCustomer(o)));
    }

    return [
      SliverList.list(
        children: [
          for (final c in children)
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: c)),
        ],
      ),
      boxed(Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: _error != null
              ? TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Gagal memuat lanjutan. Coba lagi'),
                  style: TextButton.styleFrom(foregroundColor: RC.bad, minimumSize: const Size(44, 44)),
                )
              : _hasMore
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Semua riwayat sudah ditampilkan (${_items.length})', style: rText(11.5, color: RC.faint)),
        ),
      )),
    ];
  }
}

class _HistoryRow extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;
  final VoidCallback onCustomer;
  const _HistoryRow({required this.order, required this.onTap, required this.onCustomer});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final delivered = o.status == 'delivered' && o.receivedAt != null;
    final duration = delivered ? durasi(o.receivedAt!.difference(o.createdAt)) : null;
    return Material(
      color: RC.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(jam(o.createdAt), style: rText(12.5, color: RC.ink, weight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(servicesOf(o), style: rText(13.5, color: RC.ink, weight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(customerNameOf(o), style: rText(12, color: RC.body), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(delivered ? Icons.timer_outlined : Icons.inventory_2_outlined, size: 13, color: RC.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            delivered ? 'Selesai dalam $duration' : 'Siap diambil, belum diserahkan',
                            style: rText(11, color: RC.muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rupiah(o.totalPrice), style: rText(13.5, color: RC.ink, weight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  StatusBadge(status: o.status),
                ],
              ),
              IconButton(
                tooltip: 'Riwayat ${customerNameOf(o)}',
                onPressed: onCustomer,
                icon: const Icon(Icons.chevron_right_rounded, color: RC.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
