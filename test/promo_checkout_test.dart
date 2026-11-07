import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/order_model.dart';
import 'package:laundry_apk/models/promo_checkout.dart';
import 'package:laundry_apk/models/shop_promo_model.dart';

void main() {
  // Sabtu, 7 Nov 2026 (weekday 6)
  final now = DateTime(2026, 11, 7, 10);
  final items = [
    OrderItem(name: 'Cuci Kiloan', qty: 4, price: 8000, unit: '/ kg'), // 32.000
    OrderItem(name: 'Setrika', qty: 2, price: 5000, unit: '/ pcs'), // 10.000
  ];
  final services = [
    {'id': 's1', 'name': 'Cuci Kiloan'},
    {'id': 's2', 'name': 'Setrika'},
  ];

  ShopPromoModel promo(ShopPromoType type, int value,
          {int max = 0, int min = 0, String? code, List<String> svc = const [], List<int> days = const [1, 2, 3, 4, 5, 6, 7], int? quota, int used = 0}) =>
      ShopPromoModel(
        id: '${type.key}$value',
        shopId: 'shop',
        title: 'Promo',
        type: type,
        value: value,
        maxSaving: max,
        minOrder: min,
        code: code,
        quota: quota,
        usedCount: used,
        startAt: DateTime(2026, 11, 1),
        activeDays: days,
        serviceIds: svc,
      );

  PromoQuote q(ShopPromoModel p, {int fee = 6000, bool dropoff = false}) =>
      quotePromo(p, items: items, shopServices: services, deliveryFee: fee, isDropoff: dropoff, now: now);

  test('diskon persen dengan batas maksimal', () {
    expect(q(promo(ShopPromoType.discountPct, 20)).discount, 8400);
    expect(q(promo(ShopPromoType.discountPct, 20, max: 5000)).discount, 5000);
  });

  test('potongan harga tidak melebihi subtotal', () {
    expect(q(promo(ShopPromoType.discountFlat, 10000)).discount, 10000);
    expect(q(promo(ShopPromoType.discountFlat, 99000)).discount, 42000);
  });

  test('gratis ongkir hanya untuk antar-jemput', () {
    expect(q(promo(ShopPromoType.freeDelivery, 0)).discount, 6000);
    expect(q(promo(ShopPromoType.freeDelivery, 0), dropoff: true).usable, isFalse);
  });

  test('syarat: minimal belanja, hari, kuota, layanan', () {
    expect(q(promo(ShopPromoType.discountFlat, 5000, min: 50000)).blockedReason, contains('Minimal'));
    expect(q(promo(ShopPromoType.discountFlat, 5000, days: [1, 2])).blockedReason, 'Tidak berlaku hari ini');
    expect(q(promo(ShopPromoType.discountFlat, 5000, quota: 3, used: 3)).blockedReason, contains('Kuota'));
    // 50% hanya untuk Setrika (10.000)
    expect(q(promo(ShopPromoType.discountPct, 50, svc: ['s2'])).discount, 5000);
  });

  test('promo otomatis terbaik mengabaikan promo berkode', () {
    final quotes = [
      q(promo(ShopPromoType.discountFlat, 3000)),
      q(promo(ShopPromoType.discountFlat, 20000, code: 'HEMAT')),
      q(promo(ShopPromoType.discountPct, 10)),
    ];
    expect(bestAutoPromo(quotes)!.discount, 4200);
  });
}
