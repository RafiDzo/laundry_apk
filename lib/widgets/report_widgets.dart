import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/order_model.dart';
import '../models/revenue_report.dart';
import '../utils/format_id.dart';

/// Token warna halaman laporan, sama dengan dashboard mitra.
class RC {
  static const brand = Color(0xFF0077B6);
  static const brandSoft = Color(0xFFE0F2FE);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const bg = Color(0xFFF1F5F9);
  static const surface = Colors.white;

  // Warna status dipakai konsisten: hijau selesai, kuning proses, merah batal
  static const good = Color(0xFF15803D);
  static const goodBg = Color(0xFFDCFCE7);
  static const warn = Color(0xFFB45309);
  static const warnBg = Color(0xFFFEF3C7);
  static const bad = Color(0xFFB91C1C);
  static const badBg = Color(0xFFFEE2E2);
}

TextStyle rTitle(double size) =>
    GoogleFonts.quicksand(fontSize: size, fontWeight: FontWeight.w700, color: RC.ink);
TextStyle rText(double size, {Color color = RC.body, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

/// Kartu putih dasar: border tipis, tanpa bayangan (laporan duduk rata di halaman)
class ReportCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const ReportCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: RC.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RC.border),
      ),
      child: child,
    );
  }
}

// ======================================================================
// STATUS BADGE
// ======================================================================

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final g = statusGroup(status);
    final (label, fg, bg, icon) = switch (g) {
      StatusGroup.selesai => ('Selesai', RC.good, RC.goodBg, Icons.check_circle_rounded),
      StatusGroup.diproses => ('Diproses', RC.warn, RC.warnBg, Icons.autorenew_rounded),
      StatusGroup.dibatalkan => ('Dibatalkan', RC.bad, RC.badBg, Icons.cancel_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label, style: rText(11, color: fg, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ======================================================================
// SUMMARY CARD & DELTA
// ======================================================================

/// Perubahan dibanding periode sebelumnya. [change] null = tidak ada pembanding.
class DeltaText extends StatelessWidget {
  final double? change;
  final String suffix;
  const DeltaText({super.key, required this.change, this.suffix = 'vs periode sebelumnya'});

  @override
  Widget build(BuildContext context) {
    final c = change;
    if (c == null) {
      return Text('Belum ada data periode sebelumnya', style: rText(11, color: RC.faint));
    }
    final flat = c.abs() < 0.5;
    final up = c > 0;
    final color = flat ? RC.muted : (up ? RC.good : RC.bad);
    final icon = flat
        ? Icons.trending_flat_rounded
        : (up ? Icons.trending_up_rounded : Icons.trending_down_rounded);
    final pct = c.abs() >= 100 ? c.abs().toStringAsFixed(0) : c.abs().toStringAsFixed(1).replaceAll('.', ',');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            flat ? 'Sama $suffix' : '${up ? 'Naik' : 'Turun'} $pct% $suffix',
            style: rText(11, color: color, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Kartu ringkasan. [hero] = angka paling penting (omzet), tampil paling besar.
class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final double? change;
  final String? caption;
  final bool hero;
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.change,
    this.caption,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: rText(hero ? 13 : 12, color: hero ? Colors.white.withValues(alpha: 0.85) : RC.muted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: GoogleFonts.quicksand(
              fontSize: hero ? 30 : 19,
              fontWeight: FontWeight.w800,
              color: hero ? Colors.white : RC.ink,
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!, style: rText(11, color: hero ? Colors.white.withValues(alpha: 0.8) : RC.faint)),
        ],
        if (change != null || !hero) ...[
          const SizedBox(height: 6),
          hero ? _HeroDelta(change: change) : DeltaText(change: change, suffix: ''),
        ],
      ],
    );

    if (hero) {
      // Satu-satunya permukaan berwarna di halaman: angka yang paling menentukan
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0077B6), Color(0xFF005A8C)],
          ),
        ),
        child: content,
      );
    }
    return ReportCard(padding: const EdgeInsets.all(14), child: content);
  }
}

class _HeroDelta extends StatelessWidget {
  final double? change;
  const _HeroDelta({required this.change});

  @override
  Widget build(BuildContext context) {
    final c = change;
    if (c == null) {
      return Text('Belum ada data periode sebelumnya',
          style: rText(11, color: Colors.white.withValues(alpha: 0.8)));
    }
    final up = c >= 0;
    final pct = c.abs() >= 100 ? c.abs().toStringAsFixed(0) : c.abs().toStringAsFixed(1).replaceAll('.', ',');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 4),
          Text('${up ? 'Naik' : 'Turun'} $pct% vs periode sebelumnya',
              style: rText(11, color: Colors.white, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ======================================================================
// FILTER BAR
// ======================================================================

/// Deretan pilihan filter yang bisa digeser; tinggi tap target 44px
class FilterBar extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;
  const FilterBar({super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = i == selected;
          return Material(
            color: sel ? RC.ink : RC.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? RC.ink : RC.border),
                ),
                child: Text(
                  options[i],
                  style: rText(12.5, color: sel ? Colors.white : RC.body, weight: FontWeight.w600),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ======================================================================
// LOADING / EMPTY / ERROR
// ======================================================================

class StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;
  final bool error;

  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    this.error = false,
  });

  const StateView.loading(String what, {super.key})
      : icon = Icons.hourglass_empty_rounded,
        title = what,
        message = '',
        actionLabel = null,
        onAction = null,
        loading = true,
        error = false;

  const StateView.error(this.message, {super.key, VoidCallback? onRetry})
      : icon = Icons.wifi_off_rounded,
        title = 'Data gagal dimuat',
        actionLabel = onRetry == null ? null : 'Coba lagi',
        onAction = onRetry,
        loading = false,
        error = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: RC.brand),
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: error ? RC.badBg : RC.brandSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: error ? RC.bad : RC.brand, size: 26),
            ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: rTitle(15)),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: rText(12.5, color: RC.muted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(error ? Icons.refresh_rounded : Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RC.brand,
                  side: const BorderSide(color: RC.brand),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ======================================================================
// GRAFIK OMZET PER HARI (satu seri → satu warna, tanpa legenda)
// ======================================================================

class DailyRevenueChart extends StatefulWidget {
  final List<DailyRevenue> days;
  const DailyRevenueChart({super.key, required this.days});

  @override
  State<DailyRevenueChart> createState() => _DailyRevenueChartState();
}

class _DailyRevenueChartState extends State<DailyRevenueChart> {
  int? _selected;
  bool _showTable = false;

  @override
  void didUpdateWidget(covariant DailyRevenueChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days.length != widget.days.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final maxVal = days.fold<int>(0, (m, d) => d.total > m ? d.total : m);
    final sel = _selected != null && _selected! < days.length ? days[_selected!] : null;
    final best = maxVal == 0 ? null : days.firstWhere((d) => d.total == maxVal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Baris pembacaan: hari yang diketuk, atau hari tertinggi
        SizedBox(
          height: 36,
          child: sel != null
              ? _readout('${kHariSingkat[sel.day.weekday - 1]}, ${tanggalPendek(sel.day)}', sel.total, sel.count)
              : best != null
                  ? _readout('Tertinggi ${tanggalPendek(best.day)}', best.total, best.count)
                  : Text('Belum ada omzet di periode ini', style: rText(12, color: RC.muted)),
        ),
        const SizedBox(height: 6),
        if (_showTable)
          _table(days)
        else
          SizedBox(
            height: 170,
            child: LayoutBuilder(builder: (context, c) {
              const axisW = 46.0;
              final plotW = c.maxWidth - axisW;
              final n = days.isEmpty ? 1 : days.length;
              final slot = plotW / n;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: axisW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rupiahRingkas(maxVal), style: rText(10, color: RC.faint)),
                        Text(rupiahRingkas(maxVal / 2), style: rText(10, color: RC.faint)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Text('0', style: rText(10, color: RC.faint)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _pick(d.localPosition.dx, slot, n),
                      onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, slot, n),
                      child: CustomPaint(
                        painter: _BarPainter(days: days, maxVal: maxVal, selected: _selected),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _showTable = !_showTable),
            icon: Icon(_showTable ? Icons.bar_chart_rounded : Icons.table_rows_outlined, size: 16),
            label: Text(_showTable ? 'Lihat grafik' : 'Lihat tabel'),
            style: TextButton.styleFrom(foregroundColor: RC.brand, minimumSize: const Size(44, 44)),
          ),
        ),
      ],
    );
  }

  void _pick(double dx, double slot, int n) {
    final i = (dx / slot).floor().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  Widget _readout(String label, int total, int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(child: Text(label, style: rText(12, color: RC.muted), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(rupiah(total), style: rTitle(16)),
        const SizedBox(width: 6),
        Text('· $count transaksi', style: rText(11.5, color: RC.muted)),
      ],
    );
  }

  Widget _table(List<DailyRevenue> days) {
    final rows = days.reversed.toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: RC.border),
        itemBuilder: (_, i) {
          final d = rows[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text('${kHariSingkat[d.day.weekday - 1]}, ${tanggal(d.day)}', style: rText(12.5))),
                Text('${d.count} trx', style: rText(12, color: RC.muted)),
                const SizedBox(width: 14),
                SizedBox(
                  width: 110,
                  child: Text(rupiah(d.total),
                      textAlign: TextAlign.right, style: rText(12.5, color: RC.ink, weight: FontWeight.w700)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<DailyRevenue> days;
  final int maxVal;
  final int? selected;
  _BarPainter({required this.days, required this.maxVal, required this.selected});

  static const labelH = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - labelH;
    final grid = Paint()
      ..color = RC.border
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = plotH * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (days.isEmpty) return;

    final n = days.length;
    final slot = size.width / n;
    final gap = n > 20 ? 2.0 : 6.0;
    final barW = (slot - gap).clamp(2.0, 36.0);

    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = slot * i + slot / 2;
      if (d.total > 0 && maxVal > 0) {
        final h = (d.total / maxVal * plotH).clamp(2.0, plotH);
        final isSel = selected == i;
        final paint = Paint()
          ..color = selected == null || isSel ? RC.brand : RC.brand.withValues(alpha: 0.35);
        final r = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, plotH - h, barW, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        canvas.drawRRect(r, paint);
      }
    }

    // Label tanggal: awal, tengah, akhir (hindari tabrakan)
    final idx = n == 1 ? [0] : (n == 2 ? [0, 1] : [0, n ~/ 2, n - 1]);
    for (final i in idx) {
      final tp = TextPainter(
        text: TextSpan(text: tanggalPendek(days[i].day), style: rText(10, color: RC.faint)),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = slot * i + slot / 2 - tp.width / 2;
      x = x.clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, plotH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.days != days || old.maxVal != maxVal || old.selected != selected;
}

// ======================================================================
// BATANG HORIZONTAL BERPERINGKAT (per layanan / per metode pembayaran)
// ======================================================================

class RankedBars extends StatelessWidget {
  final List<NamedAmount> items;
  final String countUnit;
  final IconData Function(String name)? iconFor;
  final int maxItems;
  const RankedBars({
    super.key,
    required this.items,
    this.countUnit = 'transaksi',
    this.iconFor,
    this.maxItems = 6,
  });

  @override
  Widget build(BuildContext context) {
    // Lebih dari [maxItems] dilipat ke "Lainnya" agar tetap terbaca
    var list = items;
    if (items.length > maxItems) {
      final rest = items.sublist(maxItems - 1);
      list = [
        ...items.take(maxItems - 1),
        NamedAmount('Lainnya (${rest.length})', rest.fold(0, (s, e) => s + e.total),
            rest.fold(0, (s, e) => s + e.count)),
      ];
    }
    final total = list.fold<int>(0, (s, e) => s + e.total);
    final maxVal = list.fold<int>(0, (m, e) => e.total > m ? e.total : m);

    return Column(
      children: [
        for (final e in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (iconFor != null) ...[
                      Icon(iconFor!(e.name), size: 16, color: RC.muted),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(e.name,
                          style: rText(12.5, color: RC.ink, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(rupiah(e.total), style: rText(12.5, color: RC.ink, weight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxVal == 0 ? 0 : e.total / maxVal,
                          minHeight: 8,
                          backgroundColor: RC.bg,
                          color: RC.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 118,
                      child: Text(
                        '${total == 0 ? 0 : (e.total / total * 100).round()}% · ${e.count} $countUnit',
                        textAlign: TextAlign.right,
                        style: rText(11, color: RC.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ======================================================================
// BARIS TRANSAKSI & DETAIL
// ======================================================================

String customerNameOf(OrderModel o) =>
    (o.customerName ?? '').trim().isNotEmpty ? o.customerName!.trim() : 'Pelanggan';

String servicesOf(OrderModel o) {
  if (o.items.isEmpty) return 'Layanan tidak dicatat';
  final first = o.items.first.name;
  return o.items.length > 1 ? '$first +${o.items.length - 1} lainnya' : first;
}

class TransactionTile extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;
  final bool showDate;
  const TransactionTile({super.key, required this.order, required this.onTap, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final cancelled = o.status == 'cancelled';
    return Material(
      color: RC.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jam(o.createdAt), style: rText(13, color: RC.ink, weight: FontWeight.w700)),
                    if (showDate)
                      Text(tanggalPendek(o.createdAt), style: rText(10.5, color: RC.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customerNameOf(o),
                        style: rText(13.5, color: RC.ink, weight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(servicesOf(o), style: rText(12, color: RC.body), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('#${nomorTransaksi(o.id)} · ${paymentGroup(o.paymentMethod)}',
                        style: rText(11, color: RC.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rupiah(o.totalPrice),
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: cancelled ? RC.faint : RC.ink,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(status: o.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail transaksi: item layanan, harga, biaya tambahan, pembayaran, waktu.
Future<void> showTransactionDetail(BuildContext context, OrderModel o, {VoidCallback? onOpenCustomer}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: RC.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final subtotal = o.items.fold<num>(0, (s, i) => s + i.price * i.qty).round();
      // Selisih total dengan harga item = biaya layanan/ongkir/penyesuaian kasir
      final extra = o.totalPrice + o.discountAmount + o.pointsUsed - subtotal;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: RC.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Transaksi #${nomorTransaksi(o.id)}', style: rTitle(18))),
                StatusBadge(status: o.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('${tanggalJam(o.createdAt)} · ${OrderModel.statusLabels[o.status] ?? o.status}',
                style: rText(12, color: RC.muted)),
            const SizedBox(height: 18),
            _detailRow('Pelanggan', customerNameOf(o)),
            if ((o.customerPhone ?? '').isNotEmpty) _detailRow('No. HP', o.customerPhone!),
            _detailRow('Pembayaran', paymentLabel(o.paymentMethod)),
            _detailRow('Pengambilan', o.isDropoff ? 'Antar sendiri ke outlet' : 'Dijemput kurir'),
            if (o.receivedAt != null)
              _detailRow('Diterima pelanggan', tanggalJam(o.receivedAt!)),
            const SizedBox(height: 14),
            Text('Item layanan', style: rTitle(14)),
            const SizedBox(height: 8),
            if (o.items.isEmpty)
              Text('Item tidak dicatat pada pesanan ini.', style: rText(12.5, color: RC.muted)),
            for (final i in o.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name, style: rText(13, color: RC.ink, weight: FontWeight.w600)),
                          Text('${angka(i.qty)} ${i.unit.replaceAll('/', '').trim()} × ${rupiah(i.price)}',
                              style: rText(11.5, color: RC.muted)),
                        ],
                      ),
                    ),
                    Text(rupiah((i.price * i.qty).round()), style: rText(13, color: RC.ink, weight: FontWeight.w600)),
                  ],
                ),
              ),
            const Divider(height: 24, color: RC.border),
            _amountRow('Subtotal layanan', subtotal),
            if (extra != 0)
              _amountRow(extra > 0 ? 'Biaya layanan & ongkir' : 'Potongan / penyesuaian', extra),
            if (o.discountAmount > 0)
              _amountRow('Promo ${o.promoTitle ?? 'outlet'}', -o.discountAmount),
            if (o.pointsUsed > 0) _amountRow('Poin member', -o.pointsUsed),
            if (o.memberFreeDelivery) _amountRow('Ongkir (gratis member)', 0),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text('Total', style: rTitle(15))),
                Text(rupiah(o.totalPrice), style: rTitle(18)),
              ],
            ),
            if ((o.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: RC.bg, borderRadius: BorderRadius.circular(12)),
                child: Text('Catatan: ${o.notes!.trim()}', style: rText(12.5)),
              ),
            ],
            if (onOpenCustomer != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onOpenCustomer();
                  },
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: Text('Riwayat ${customerNameOf(o)}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RC.brand,
                    side: const BorderSide(color: RC.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: rText(12.5, color: RC.muted))),
          Expanded(child: Text(value, style: rText(12.5, color: RC.ink, weight: FontWeight.w600))),
        ],
      ),
    );

Widget _amountRow(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: rText(12.5, color: RC.muted))),
          Text(rupiah(value), style: rText(12.5, color: RC.body, weight: FontWeight.w600)),
        ],
      ),
    );
