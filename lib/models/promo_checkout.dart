import 'order_model.dart';
import 'shop_promo_model.dart';

/// Hasil perhitungan satu promo untuk keranjang tertentu.
class PromoQuote {
  final ShopPromoModel promo;
  final int discount;

  /// null = promo bisa dipakai; selain itu alasan tidak bisa dipakai (untuk ditampilkan)
  final String? blockedReason;

  const PromoQuote(this.promo, this.discount, this.blockedReason);

  bool get usable => blockedReason == null && discount > 0;
}

String _rp(int v) =>
    'Rp ${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

/// Hitung potongan promo outlet. Aturan yang sama divalidasi ulang di server
/// (trigger orders_apply_promo), jadi angka di sini hanya pratinjau yang jujur.
PromoQuote quotePromo(
  ShopPromoModel p, {
  required List<OrderItem> items,
  required List<dynamic> shopServices,
  required int deliveryFee,
  required bool isDropoff,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  PromoQuote no(String reason) => PromoQuote(p, 0, reason);

  if (p.type == ShopPromoType.cashback) return no('Cashback belum bisa dipakai saat checkout');
  if (!p.isActive) return no('Promo sedang dinonaktifkan outlet');
  if (t.isBefore(p.startAt)) return no('Promo belum dimulai');
  if (p.endAt != null && t.isAfter(p.endAt!)) return no('Promo sudah berakhir');
  if (p.isQuotaExhausted) return no('Kuota promo sudah habis');
  if (p.activeDays.isNotEmpty && !p.activeDays.contains(t.weekday)) return no('Tidak berlaku hari ini');

  final subtotal = items.fold<num>(0, (s, i) => s + i.price * i.qty).round();
  if (subtotal < p.minOrder) return no('Minimal belanja ${_rp(p.minOrder)}');

  // Promo khusus layanan tertentu: cocokkan nama item dengan id layanan outlet
  var eligible = subtotal;
  if (p.serviceIds.isNotEmpty) {
    final idByName = <String, String>{};
    for (final s in shopServices) {
      if (s is Map && s['name'] != null && s['id'] != null) {
        idByName['${s['name']}'.trim().toLowerCase()] = '${s['id']}';
      }
    }
    eligible = items
        .where((i) => p.serviceIds.contains(idByName[i.name.trim().toLowerCase()]))
        .fold<num>(0, (s, i) => s + i.price * i.qty)
        .round();
    if (eligible <= 0) return no('Tidak berlaku untuk layanan yang dipilih');
  }

  switch (p.type) {
    case ShopPromoType.discountPct:
      var d = (eligible * p.value / 100).floor();
      if (p.maxSaving > 0 && d > p.maxSaving) d = p.maxSaving;
      return PromoQuote(p, d, d > 0 ? null : 'Potongan Rp 0');
    case ShopPromoType.discountFlat:
      final d = p.value < eligible ? p.value : eligible;
      return PromoQuote(p, d, d > 0 ? null : 'Potongan Rp 0');
    case ShopPromoType.freeDelivery:
      if (isDropoff) return no('Hanya untuk antar-jemput kurir');
      if (deliveryFee <= 0) return no('Ongkir pesanan ini sudah gratis');
      return PromoQuote(p, deliveryFee, null);
    case ShopPromoType.cashback:
      return no('Cashback belum bisa dipakai saat checkout');
  }
}

/// Promo otomatis (tanpa kode) dengan potongan terbesar, atau null.
PromoQuote? bestAutoPromo(List<PromoQuote> quotes) {
  PromoQuote? best;
  for (final q in quotes) {
    if (!q.usable || (q.promo.code ?? '').isNotEmpty) continue;
    if (best == null || q.discount > best.discount) best = q;
  }
  return best;
}
