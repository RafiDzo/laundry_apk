import 'order_model.dart';

/// Kelompok metode pembayaran untuk laporan. Nilai mentah di kolom
/// orders.payment_method berasal dari halaman pembayaran (qris, dana, bca, cod, ...)
/// dan kasir walk-in ('cash').
String paymentGroup(String raw) {
  final m = raw.trim().toLowerCase();
  if (m.isEmpty) return 'Tidak dicatat';
  if (const {'cash', 'cod', 'tunai'}.contains(m)) return 'Tunai';
  if (m == 'qris') return 'QRIS';
  if (const {'dana', 'gopay', 'ovo', 'shopeepay', 'linkaja'}.contains(m)) return 'E-Wallet';
  if (const {'bca', 'mandiri', 'bri', 'bni', 'transfer', 'va'}.contains(m)) return 'Transfer Bank';
  return raw.trim();
}

/// Nama metode spesifik untuk detail transaksi (mis. "Transfer Bank · BCA")
String paymentLabel(String raw) {
  final group = paymentGroup(raw);
  final m = raw.trim().toLowerCase();
  const names = {
    'dana': 'DANA', 'gopay': 'GoPay', 'ovo': 'OVO', 'shopeepay': 'ShopeePay',
    'bca': 'BCA', 'mandiri': 'Mandiri', 'bri': 'BRI', 'bni': 'BNI',
  };
  return names.containsKey(m) ? '$group · ${names[m]}' : group;
}

/// Kelompok status untuk laporan: Selesai / Diproses / Dibatalkan
enum StatusGroup { selesai, diproses, dibatalkan }

StatusGroup statusGroup(String status) {
  if (status == 'cancelled') return StatusGroup.dibatalkan;
  if (status == 'done' || status == 'delivered') return StatusGroup.selesai;
  return StatusGroup.diproses;
}

class DailyRevenue {
  final DateTime day;
  final int total;
  final int count;
  const DailyRevenue(this.day, this.total, this.count);
}

class NamedAmount {
  final String name;
  final int total;
  final int count;
  const NamedAmount(this.name, this.total, this.count);
}

class RevenueReport {
  /// Awal periode (inklusif) dan akhir periode (eksklusif), waktu lokal
  final DateTime from;
  final DateTime to;
  final int total;
  final int count;
  final int prevTotal;
  final int prevCount;

  /// Satu entri per hari dalam periode, hari tanpa transaksi bernilai 0
  final List<DailyRevenue> daily;

  /// Omzet per layanan dari harga item (belum termasuk biaya layanan/ongkir)
  final List<NamedAmount> services;

  /// Omzet per kelompok metode pembayaran
  final List<NamedAmount> payments;

  /// true jika dihitung di perangkat karena fungsi SQL belum dipasang
  final bool computedOnDevice;

  const RevenueReport({
    required this.from,
    required this.to,
    required this.total,
    required this.count,
    required this.prevTotal,
    required this.prevCount,
    required this.daily,
    required this.services,
    required this.payments,
    this.computedOnDevice = false,
  });

  int get average => count == 0 ? 0 : (total / count).round();
  int get prevAverage => prevCount == 0 ? 0 : (prevTotal / prevCount).round();

  /// Persentase perubahan dibanding periode sebelumnya; null jika periode
  /// sebelumnya kosong (tidak ada pembanding yang jujur).
  static double? change(num current, num previous) =>
      previous == 0 ? null : (current - previous) / previous * 100;

  bool get isEmpty => count == 0;

  static List<DailyRevenue> _fillDays(DateTime from, DateTime to, Map<DateTime, DailyRevenue> byDay) {
    final days = <DailyRevenue>[];
    for (var d = DateTime(from.year, from.month, from.day); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(byDay[d] ?? DailyRevenue(d, 0, 0));
    }
    return days;
  }

  static List<NamedAmount> _groupPayments(Iterable<NamedAmount> raw) {
    final map = <String, List<int>>{};
    for (final p in raw) {
      final g = paymentGroup(p.name);
      final cur = map.putIfAbsent(g, () => [0, 0]);
      cur[0] += p.total;
      cur[1] += p.count;
    }
    final list = map.entries.map((e) => NamedAmount(e.key, e.value[0], e.value[1])).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  static int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

  /// Dari hasil RPC washora_revenue_report
  factory RevenueReport.fromJson(Map<String, dynamic> json, DateTime from, DateTime to) {
    final byDay = <DateTime, DailyRevenue>{};
    for (final row in (json['daily'] as List? ?? const [])) {
      final m = row as Map<String, dynamic>;
      final d = DateTime.parse(m['day'] as String);
      final day = DateTime(d.year, d.month, d.day);
      byDay[day] = DailyRevenue(day, _int(m['total']), _int(m['count']));
    }
    final services = (json['services'] as List? ?? const [])
        .map((r) => NamedAmount('${r['name']}', _int(r['total']), _int(r['count'])))
        .toList();
    final payments = (json['payments'] as List? ?? const [])
        .map((r) => NamedAmount('${r['method'] ?? ''}', _int(r['total']), _int(r['count'])));
    return RevenueReport(
      from: from,
      to: to,
      total: _int(json['total']),
      count: _int(json['count']),
      prevTotal: _int(json['prev_total']),
      prevCount: _int(json['prev_count']),
      daily: _fillDays(from, to, byDay),
      services: services,
      payments: _groupPayments(payments),
    );
  }

  /// Cadangan jika fungsi SQL belum dijalankan: hitung dari daftar pesanan.
  /// [orders] boleh berisi periode sebelumnya juga; pesanan batal diabaikan.
  factory RevenueReport.fromOrders(List<OrderModel> orders, DateTime from, DateTime to) {
    final prevFrom = from.subtract(to.difference(from));
    var total = 0, count = 0, prevTotal = 0, prevCount = 0;
    final byDay = <DateTime, DailyRevenue>{};
    final svc = <String, List<int>>{};
    final svcOrders = <String, Set<String>>{};
    final pay = <String, List<int>>{};

    for (final o in orders) {
      if (o.status == 'cancelled') continue;
      final t = o.createdAt;
      if (!t.isBefore(prevFrom) && t.isBefore(from)) {
        prevTotal += o.totalPrice;
        prevCount++;
        continue;
      }
      if (t.isBefore(from) || !t.isBefore(to)) continue;
      total += o.totalPrice;
      count++;
      final day = DateTime(t.year, t.month, t.day);
      final d = byDay[day];
      byDay[day] = DailyRevenue(day, (d?.total ?? 0) + o.totalPrice, (d?.count ?? 0) + 1);
      for (final i in o.items) {
        final name = i.name.trim().isEmpty ? 'Tanpa nama' : i.name.trim();
        final s = svc.putIfAbsent(name, () => [0, 0]);
        s[0] += (i.price * i.qty).round();
        svcOrders.putIfAbsent(name, () => {}).add(o.id);
      }
      final p = pay.putIfAbsent(o.paymentMethod.toLowerCase(), () => [0, 0]);
      p[0] += o.totalPrice;
      p[1]++;
    }

    final services = svc.entries
        .map((e) => NamedAmount(e.key, e.value[0], svcOrders[e.key]!.length))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return RevenueReport(
      from: from,
      to: to,
      total: total,
      count: count,
      prevTotal: prevTotal,
      prevCount: prevCount,
      daily: _fillDays(from, to, byDay),
      services: services,
      payments: _groupPayments(pay.entries.map((e) => NamedAmount(e.key, e.value[0], e.value[1]))),
      computedOnDevice: true,
    );
  }
}
