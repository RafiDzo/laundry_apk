import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/order_model.dart';
import 'package:laundry_apk/models/revenue_report.dart';
import 'package:laundry_apk/utils/format_id.dart';

OrderModel _order(String id, DateTime at, int total,
    {String status = 'done', String pay = 'cash', List<OrderItem>? items}) {
  return OrderModel(
    id: id,
    userId: '',
    shopId: 's1',
    shopName: 'Toko',
    items: items ?? [OrderItem(name: 'Cuci Kiloan', qty: 2, price: 7000, unit: '/ kg')],
    status: status,
    totalPrice: total,
    serviceFee: 0,
    paymentMethod: pay,
    createdAt: at,
  );
}

void main() {
  group('format', () {
    test('rupiah memakai titik ribuan', () {
      expect(rupiah(1250000), 'Rp 1.250.000');
      expect(rupiah(0), 'Rp 0');
      expect(rupiah(-5000), '-Rp 5.000');
    });
    test('tanggal Indonesia 2 digit', () {
      expect(tanggal(DateTime(2026, 11, 7)), '07 Nov 2026');
    });
    test('durasi', () {
      expect(durasi(const Duration(minutes: 135)), '2 jam 15 mnt');
      expect(durasi(const Duration(hours: 76)), '3 hari 4 jam');
    });
  });

  group('RevenueReport.fromOrders', () {
    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 11, 8); // 7 hari
    final orders = [
      _order('a', DateTime(2026, 11, 2, 9), 14000),
      _order('b', DateTime(2026, 11, 2, 15), 20000, pay: 'qris'),
      _order('c', DateTime(2026, 11, 5, 10), 30000, pay: 'gopay'),
      _order('x', DateTime(2026, 11, 6), 99000, status: 'cancelled'),
      // periode sebelumnya (25-31 Okt)
      _order('p', DateTime(2026, 10, 28), 32000),
      // di luar kedua periode
      _order('old', DateTime(2026, 10, 1), 50000),
    ];
    final r = RevenueReport.fromOrders(orders, from, to);

    test('total, jumlah, rata-rata mengabaikan pesanan batal', () {
      expect(r.total, 64000);
      expect(r.count, 3);
      expect(r.average, 21333);
    });
    test('periode pembanding sama panjang', () {
      expect(r.prevTotal, 32000);
      expect(RevenueReport.change(r.total, r.prevTotal), 100);
    });
    test('harian terisi untuk setiap hari termasuk nol', () {
      expect(r.daily.length, 7);
      expect(r.daily[1].total, 34000);
      expect(r.daily[1].count, 2);
      expect(r.daily[0].total, 0);
    });
    test('metode pembayaran dikelompokkan', () {
      final names = {for (final p in r.payments) p.name: p.total};
      expect(names, {'E-Wallet': 30000, 'QRIS': 20000, 'Tunai': 14000});
    });
    test('tanpa periode sebelumnya, perubahan null', () {
      expect(RevenueReport.change(100, 0), isNull);
    });
  });
}
