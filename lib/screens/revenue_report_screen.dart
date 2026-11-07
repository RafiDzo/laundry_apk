import 'package:flutter/material.dart';

import '../models/revenue_report.dart';
import '../models/shop_model.dart';
import '../services/report_export.dart';
import '../services/report_service.dart';
import '../utils/format_id.dart';
import '../widgets/quick_snackbar.dart';
import '../widgets/report_widgets.dart';

/// Laporan Omzet mitra: ringkasan, tren harian, per layanan, per pembayaran.
class RevenueReportScreen extends StatefulWidget {
  final ShopModel shop;
  const RevenueReportScreen({super.key, required this.shop});

  @override
  State<RevenueReportScreen> createState() => _RevenueReportScreenState();
}

class _RevenueReportScreenState extends State<RevenueReportScreen> {
  final _service = ReportService();
  static const _periods = ['Hari Ini', '7 Hari', 'Bulan Ini', 'Pilih Tanggal'];

  int _period = 1;
  DateTimeRange? _custom;
  RevenueReport? _report;
  String? _error;
  bool _loading = true;
  bool _exporting = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [from] inklusif, [to] eksklusif
  (DateTime, DateTime) get _range {
    final today = awalHari(DateTime.now());
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    switch (_period) {
      case 0:
        return (today, tomorrow);
      case 2:
        return (DateTime(today.year, today.month, 1), tomorrow);
      case 3:
        final c = _custom!;
        final end = awalHari(c.end);
        return (awalHari(c.start), DateTime(end.year, end.month, end.day + 1));
      default:
        return (DateTime(today.year, today.month, today.day - 6), tomorrow);
    }
  }

  Future<void> _load() async {
    final req = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _range;
    try {
      final r = await _service.fetchRevenueReport(widget.shop.id, from, to);
      if (!mounted || req != _request) return;
      setState(() {
        _report = r;
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
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 13)), end: now),
        helpText: 'Pilih rentang laporan',
        saveText: 'Terapkan',
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: RC.brand)),
          child: child!,
        ),
      );
      if (picked == null) return;
      if (picked.end.difference(picked.start).inDays > 365) {
        _snack('Rentang laporan maksimal 1 tahun.');
        return;
      }
      _custom = picked;
    }
    setState(() => _period = i);
    _load();
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _export() async {
    final r = _report;
    if (r == null || _exporting) return;
    final format = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RC.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Ekspor laporan ${ReportExport.periodLabel(r)}', style: rTitle(16)),
              ),
              const SizedBox(height: 8),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.picture_as_pdf_outlined, color: RC.bad),
                title: Text('PDF', style: rText(14, color: RC.ink, weight: FontWeight.w600)),
                subtitle: Text('Siap dicetak atau dikirim', style: rText(12, color: RC.muted)),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.grid_on_rounded, color: RC.good),
                title: Text('Excel (.xlsx)', style: rText(14, color: RC.ink, weight: FontWeight.w600)),
                subtitle: Text('Ringkasan + daftar semua transaksi', style: rText(12, color: RC.muted)),
                onTap: () => Navigator.pop(ctx, 'xlsx'),
              ),
            ],
          ),
        ),
      ),
    );
    if (format == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final orders = await _service.fetchOrdersInRange(widget.shop.id, r.from, r.to);
      final path = format == 'pdf'
          ? await ReportExport.savePdf(shopName: widget.shop.name, report: r, orders: orders)
          : await ReportExport.saveExcel(shopName: widget.shop.name, report: r, orders: orders);
      if (!mounted) return;
      _snack(path.isEmpty || path.startsWith('Downloads') ? 'Laporan terunduh.' : 'Laporan tersimpan: $path',
          color: RC.good);
    } catch (e) {
      if (mounted) _snack('Ekspor gagal: $e', color: RC.bad);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      backgroundColor: RC.bg,
      appBar: AppBar(
        backgroundColor: RC.surface,
        surfaceTintColor: RC.surface,
        foregroundColor: RC.ink,
        elevation: 0,
        title: Text('Laporan Omzet', style: rTitle(18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _exporting
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(
                    onPressed: r == null || _loading ? null : _export,
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    label: const Text('Ekspor'),
                    style: TextButton.styleFrom(foregroundColor: RC.brand, minimumSize: const Size(44, 44)),
                  ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: RC.brand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          children: [
            FilterBar(options: _periods, selected: _period, onSelected: _selectPeriod),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                r != null && !_loading ? 'Periode ${ReportExport.periodLabel(r)}' : 'Memuat periode…',
                style: rText(12, color: RC.muted),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _body(r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(RevenueReport? r) {
    if (_loading && r == null) return const StateView.loading('Menghitung omzet…');
    if (_error != null) return StateView.error(_error!, onRetry: _load);
    if (r == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: _loading ? 0.5 : 1,
      duration: const Duration(milliseconds: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryCard(
            hero: true,
            label: 'Total Omzet',
            value: rupiah(r.total),
            change: RevenueReport.change(r.total, r.prevTotal),
            caption: 'Dari pesanan yang tidak dibatalkan',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, c) {
            final cards = [
              SummaryCard(
                label: 'Jumlah Transaksi',
                value: '${r.count}',
                change: RevenueReport.change(r.count, r.prevCount),
              ),
              SummaryCard(
                label: 'Rata-rata / Transaksi',
                value: rupiah(r.average),
                change: RevenueReport.change(r.average, r.prevAverage),
              ),
            ];
            if (c.maxWidth < 340) {
              return Column(children: [cards[0], const SizedBox(height: 10), cards[1]]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])],
              ),
            );
          }),
          const SizedBox(height: 16),
          if (r.isEmpty)
            ReportCard(
              child: StateView(
                icon: Icons.receipt_long_outlined,
                title: 'Belum ada transaksi di periode ini',
                message: _period == 0
                    ? 'Pesanan yang masuk hari ini akan langsung dihitung di sini.'
                    : 'Coba pilih periode lain, atau catat pesanan walk-in dari tombol Order di dashboard.',
              ),
            )
          else ...[
            ReportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Omzet per hari', style: rTitle(15)),
                  const SizedBox(height: 2),
                  Text(
                    r.daily.length > 1
                        ? 'Ketuk batang untuk melihat angka harian'
                        : 'Pilih 7 Hari atau Bulan Ini untuk melihat tren harian',
                    style: rText(11.5, color: RC.muted),
                  ),
                  const SizedBox(height: 12),
                  if (r.daily.length > 1) DailyRevenueChart(days: r.daily) else _todayBreakdown(r),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ReportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Layanan penyumbang omzet', style: rTitle(15)),
                  const SizedBox(height: 2),
                  Text('Dari harga item layanan, belum termasuk biaya layanan & ongkir',
                      style: rText(11.5, color: RC.muted)),
                  const SizedBox(height: 8),
                  if (r.services.isEmpty)
                    Text('Item layanan tidak dicatat pada pesanan periode ini.', style: rText(12.5, color: RC.muted))
                  else
                    RankedBars(items: r.services, countUnit: 'pesanan'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ReportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metode pembayaran', style: rTitle(15)),
                  const SizedBox(height: 8),
                  RankedBars(items: r.payments, iconFor: _paymentIcon),
                ],
              ),
            ),
          ],
          if (r.computedOnDevice) ...[
            const SizedBox(height: 12),
            Text(
              'Laporan dihitung di perangkat. Jalankan supabase_laporan.sql di Supabase agar perhitungan dilakukan di server dan lebih cepat.',
              style: rText(11, color: RC.faint),
            ),
          ],
        ],
      ),
    );
  }

  /// Untuk periode satu hari, tampilkan kalimat alih-alih grafik satu batang
  Widget _todayBreakdown(RevenueReport r) {
    final d = r.daily.isNotEmpty ? r.daily.first : null;
    return Text(
      d == null
          ? 'Belum ada transaksi.'
          : '${r.count} transaksi dengan total ${rupiah(r.total)} pada ${tanggal(d.day)}.',
      style: rText(13, color: RC.body),
    );
  }

  static IconData _paymentIcon(String group) => switch (group) {
        'Tunai' => Icons.payments_outlined,
        'QRIS' => Icons.qr_code_2_rounded,
        'E-Wallet' => Icons.account_balance_wallet_outlined,
        'Transfer Bank' => Icons.account_balance_outlined,
        _ => Icons.help_outline_rounded,
      };
}
