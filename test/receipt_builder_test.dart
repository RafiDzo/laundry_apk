import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/order_model.dart';
import 'package:laundry_apk/receipt/receipt_builder.dart';

OrderModel _order({
  List<OrderItem>? items,
  int total = 30000,
  int serviceFee = 2000,
  int discount = 0,
  String? promoTitle,
  String delivery = 'pickup',
  String name = 'Budi Santoso',
  String pay = 'cash',
}) =>
    OrderModel(
      id: 'abcdef12-3456-7890-abcd-ef1234567890',
      userId: 'u1',
      shopId: 's1',
      shopName: 'Laundry Bersih',
      items: items ?? [OrderItem(name: 'Cuci Kiloan', qty: 3, price: 8000, unit: '/ kg')],
      totalPrice: total,
      serviceFee: serviceFee,
      paymentMethod: pay,
      createdAt: DateTime(2026, 11, 7, 21, 10),
      customerName: name,
      customerPhone: '081298765432',
      deliveryType: delivery,
      promoId: discount > 0 ? 'p1' : null,
      promoTitle: promoTitle,
      discountAmount: discount,
    );

ReceiptData _data(OrderModel o, {bool copy = false, String? tier, int? cash, DateTime? paid}) => ReceiptData(
      order: o,
      shopName: 'Laundry Bersih',
      shopAddress: 'Jl. Mawar No. 12, Kemang, Jakarta Selatan',
      shopPhone: '0812-1111-2222',
      cashierName: 'Rafi',
      memberTier: tier,
      claimWindowHours: tier == 'Silver' ? 72 : 48,
      estimate: '1-2 Hari',
      isCopy: copy,
      cashReceived: cash,
      paidAt: paid,
      printedAt: DateTime(2026, 11, 7, 21, 15),
    );

List<String> _render(OrderModel o, {PaperWidth w = PaperWidth.mm58, bool copy = false, String? tier, int? cash, DateTime? paid}) {
  final b = ReceiptBuilder(ReceiptSettings(width: w));
  return b.toText(b.build(_data(o, copy: copy, tier: tier, cash: cash, paid: paid)));
}

void expectFits(List<String> lines, int width) {
  for (final l in lines) {
    if (l.startsWith('[QR')) continue;
    expect(l.length, lessThanOrEqualTo(width), reason: 'Baris melebihi $width kolom: "$l"');
  }
}

void main() {
  test('struk standar 58mm: setiap baris ≤ 32 kolom & angka benar', () {
    // 3 kg × 8.000 = 24.000 + layanan 2.000 + ongkir 4.000 = 30.000
    final lines = _render(_order());
    expectFits(lines, 32);
    final text = lines.join('\n');
    expect(text, contains('#ABCDEF12'));
    expect(text, contains('07 Nov 2026 21:10'));
    expect(text, contains('Rp 24.000'));
    expect(text, contains('Ongkir'));
    expect(text, contains('Rp 4.000'));
    expect(text, contains('TOTAL'));
    expect(text, contains('Rp 30.000'));
    expect(text, contains('0812****432')); // nomor HP disamarkan
    expect(text, contains('BELUM LUNAS'));
  });

  test('nama layanan sangat panjang dibungkus tanpa merusak kolom', () {
    final long = 'Cuci Kering Setrika Premium Super Wangi Lavender Extra Lembut Khusus Bahan Sutra';
    final lines = _render(_order(items: [OrderItem(name: long, qty: 2, price: 15000, unit: '/ pcs')], total: 34000));
    expectFits(lines, 32);
    expect(lines.join('\n'), contains('2 pcs x Rp 15.000'));
    expect(lines.where((l) => l.startsWith('Cuci Kering')).length, 1); // nama dibungkus, bukan diulang
  });

  test('banyak item muat di 58 & 80 mm', () {
    final items = List.generate(15, (i) => OrderItem(name: 'Layanan nomor ${i + 1}', qty: 1.5, price: 7000, unit: '/ kg'));
    expectFits(_render(_order(items: items, total: 159500)), 32);
    expectFits(_render(_order(items: items, total: 159500), w: PaperWidth.mm80), 48);
  });

  test('promo + gratis ongkir + member', () {
    // subtotal 24.000 + layanan 2.000 + ongkir 0 - promo 5.000 = 21.000
    // Teks ketentuan dibungkus beberapa baris: gabungkan dulu untuk dicek
    final text = _render(_order(total: 21000, discount: 5000, promoTitle: 'HEMAT'), tier: 'Silver')
        .join(' ')
        .replaceAll(RegExp(r' +'), ' ');
    expect(text, contains('Promo HEMAT'));
    expect(text, contains('-Rp 5.000'));
    expect(text, contains('Gratis'));
    expect(text, contains('Silver'));
    expect(text, contains('72 jam (3 hari)'));
  });

  test('tunai lunas menampilkan kembalian', () {
    final text = _render(_order(), cash: 50000, paid: DateTime(2026, 11, 7)).join('\n');
    expect(text, contains('LUNAS'));
    expect(text, isNot(contains('BELUM LUNAS')));
    expect(text, contains('Rp 20.000')); // kembali 50.000 - 30.000
  });

  test('cetak ulang ditandai SALINAN', () {
    final lines = _render(_order(), copy: true);
    expect(lines.where((l) => l.contains('SALINAN')).length, 2);
  });

  test('karakter khusus & emoji tidak menggeser kolom', () {
    final lines = _render(_order(name: 'José Ñuñez 🧺 李'));
    expectFits(lines, 32);
    expect(lines.join('\n'), contains('Jose Nunez ? ?'));
  });

  test('antar sendiri tidak menampilkan ongkir', () {
    final text = _render(_order(delivery: 'dropoff', total: 26000)).join('\n');
    expect(text, isNot(contains('Ongkir')));
  });

  test('wrap & twoColumns', () {
    expect(wrap('abc defgh ij', 5), ['abc', 'defgh', 'ij']);
    expect(wrap('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
    expect(twoColumns('Subtotal', 'Rp 9.000', 20), ['Subtotal    Rp 9.000']);
  });

  test('gratis ongkir member & poin tercetak, total sesuai pesanan', () {
    // subtotal 24.000 + layanan 2.000 + ongkir 0 (member) - poin 1.500 = 24.500
    final o = OrderModel(
      id: 'abcdef12-0000',
      userId: 'u1',
      shopId: 's1',
      shopName: 'Laundry Bersih',
      items: [OrderItem(name: 'Cuci Kiloan', qty: 3, price: 8000, unit: '/ kg')],
      totalPrice: 24500,
      serviceFee: 2000,
      paymentMethod: 'qris',
      createdAt: DateTime(2026, 11, 7, 21, 10),
      memberFreeDelivery: true,
      pointsUsed: 1500,
    );
    final text = _render(o, tier: 'Gold').join('\n');
    expect(text, contains('Gratis (member)'));
    expect(text, contains('-Rp 1.500'));
    expect(text, contains('Rp 24.500'));
    final a = ReceiptBuilder.amounts(o);
    expect(a.delivery, 0);
    expect(a.points, 1500);
  });

  test('pesanan dengan benefit hanya mengirim kolom yang dipakai', () {
    final m = _order().toMap();
    expect(m.containsKey('member_free_delivery'), isFalse);
    expect(m.containsKey('points_used'), isFalse);
  });
}
