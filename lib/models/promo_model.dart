import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PromoCategory { diskon, ongkir, cashback, member }

extension PromoCategoryLabel on PromoCategory {
  String get label => switch (this) {
    PromoCategory.diskon => 'Diskon',
    PromoCategory.ongkir => 'Gratis Ongkir',
    PromoCategory.cashback => 'Cashback',
    PromoCategory.member => 'Member',
  };

  IconData get icon => switch (this) {
    PromoCategory.diskon => Icons.percent_rounded,
    PromoCategory.ongkir => Icons.local_shipping_rounded,
    PromoCategory.cashback => Icons.savings_rounded,
    PromoCategory.member => Icons.workspace_premium_rounded,
  };
}

class Promo {
  final String id;
  final String code;
  final String title;
  final String subtitle;

  /// Teks besar di sisi kiri tiket, mis. "50%", "GRATIS", "15RB".
  final String valueLabel;

  /// Teks kecil di bawah nilai, mis. "DISKON", "ONGKIR".
  final String valueCaption;
  final PromoCategory category;
  final int minOrder;

  /// Perkiraan potongan maksimal (untuk hitung "potensi hemat").
  final int maxSaving;
  final int validDays;
  final double quotaUsed;
  final bool isFlash;
  final List<Color> colors;
  final List<String> terms;

  const Promo({
    required this.id,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.valueCaption,
    required this.category,
    required this.minOrder,
    required this.maxSaving,
    required this.validDays,
    required this.quotaUsed,
    required this.colors,
    required this.terms,
    this.isFlash = false,
  });

  DateTime get validUntil {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + validDays, 23, 59);
  }
}

class SubscriptionPlan {
  final String name;
  final String tagline;
  final int price;
  final int normalPrice;
  final String quota;
  final List<String> features;
  final List<Color> colors;
  final bool popular;

  const SubscriptionPlan({
    required this.name,
    required this.tagline,
    required this.price,
    required this.normalPrice,
    required this.quota,
    required this.features,
    required this.colors,
    this.popular = false,
  });
}

class PromoCatalog {
  PromoCatalog._();

  static const List<Promo> all = [
    Promo(
      id: 'first50',
      code: 'WASHBARU50',
      title: 'Diskon 50% Order Pertama',
      subtitle: 'Untuk cuci & dry clean pertama kamu',
      valueLabel: '50%',
      valueCaption: 'DISKON',
      category: PromoCategory.diskon,
      minOrder: 30000,
      maxSaving: 25000,
      validDays: 14,
      quotaUsed: 0.62,
      colors: [Color(0xFF0066CC), Color(0xFF0284C7)],
      terms: [
        'Hanya untuk pengguna yang belum pernah memesan.',
        'Potongan maksimal Rp 25.000.',
        'Berlaku untuk layanan Cuci Kiloan & Dry Clean.',
        'Tidak dapat digabung dengan voucher lain.',
      ],
    ),
    Promo(
      id: 'ongkir',
      code: 'ONGKIRFREE',
      title: 'Gratis Ongkir Antar Jemput',
      subtitle: 'Minimal pemesanan Rp 50.000 se-area',
      valueLabel: 'GRATIS',
      valueCaption: 'ONGKIR',
      category: PromoCategory.ongkir,
      minOrder: 50000,
      maxSaving: 15000,
      validDays: 30,
      quotaUsed: 0.41,
      colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
      terms: [
        'Berlaku untuk jarak antar jemput maksimal 5 km.',
        'Minimal transaksi Rp 50.000 sebelum ongkir.',
        'Berlaku 1x per hari per akun.',
      ],
    ),
    Promo(
      id: 'doublepoin',
      code: 'DOUBLEPOIN',
      title: 'Double Poin Setiap Weekend',
      subtitle: 'Kumpulkan poin 2x lebih cepat',
      valueLabel: '2X',
      valueCaption: 'POIN',
      category: PromoCategory.member,
      minOrder: 25000,
      maxSaving: 10000,
      validDays: 60,
      quotaUsed: 0.18,
      colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
      terms: [
        'Berlaku untuk pesanan hari Sabtu & Minggu.',
        'Poin dikreditkan setelah pesanan selesai.',
        'Poin dapat ditukar dengan voucher di menu Profil.',
      ],
    ),
    Promo(
      id: 'payday',
      code: 'PAYDAY30',
      title: 'Payday Sale 30%',
      subtitle: 'Gajian? Saatnya cucian beres semua',
      valueLabel: '30%',
      valueCaption: 'DISKON',
      category: PromoCategory.diskon,
      minOrder: 40000,
      maxSaving: 20000,
      validDays: 0,
      quotaUsed: 0.84,
      isFlash: true,
      colors: [Color(0xFFF97316), Color(0xFFEF4444)],
      terms: [
        'Hanya berlaku hari ini sampai pukul 23:59.',
        'Potongan maksimal Rp 20.000.',
        'Kuota terbatas, siapa cepat dia dapat.',
      ],
    ),
    Promo(
      id: 'malam',
      code: 'MALAMHEMAT',
      title: 'Cashback Malam 20%',
      subtitle: 'Pesan setelah jam 19:00',
      valueLabel: '20%',
      valueCaption: 'CASHBACK',
      category: PromoCategory.cashback,
      minOrder: 30000,
      maxSaving: 15000,
      validDays: 0,
      quotaUsed: 0.67,
      isFlash: true,
      colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
      terms: [
        'Berlaku untuk pesanan pukul 19:00 – 23:59.',
        'Cashback maksimal Rp 15.000 dalam bentuk poin.',
      ],
    ),
    Promo(
      id: 'kilat',
      code: 'KILAT10',
      title: 'Potongan Rp 10.000 Cuci Kilat',
      subtitle: 'Selesai 4 jam, tetap hemat',
      valueLabel: '10RB',
      valueCaption: 'POTONGAN',
      category: PromoCategory.diskon,
      minOrder: 35000,
      maxSaving: 10000,
      validDays: 7,
      quotaUsed: 0.93,
      isFlash: true,
      colors: [Color(0xFFDB2777), Color(0xFFF43F5E)],
      terms: [
        'Khusus layanan Cuci Kilat / Express.',
        'Minimal transaksi Rp 35.000.',
      ],
    ),
    Promo(
      id: 'cashback',
      code: 'CASHBACK15',
      title: 'Cashback 15% Pakai QRIS',
      subtitle: 'Bayar pakai QRIS, dapat poin balik',
      valueLabel: '15%',
      valueCaption: 'CASHBACK',
      category: PromoCategory.cashback,
      minOrder: 20000,
      maxSaving: 12000,
      validDays: 21,
      quotaUsed: 0.35,
      colors: [Color(0xFF059669), Color(0xFF10B981)],
      terms: [
        'Hanya untuk pembayaran via QRIS.',
        'Cashback maksimal Rp 12.000 dalam bentuk poin.',
      ],
    ),
    Promo(
      id: 'setrika',
      code: 'SETRIKA25',
      title: 'Diskon 25% Setrika Saja',
      subtitle: 'Baju licin tanpa ribet',
      valueLabel: '25%',
      valueCaption: 'DISKON',
      category: PromoCategory.diskon,
      minOrder: 20000,
      maxSaving: 10000,
      validDays: 10,
      quotaUsed: 0.27,
      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
      terms: ['Khusus layanan Setrika Saja.', 'Potongan maksimal Rp 10.000.'],
    ),
    Promo(
      id: 'member',
      code: 'SULTANWASH',
      title: 'Voucher Member Gold',
      subtitle: 'Hadiah untuk pelanggan setia',
      valueLabel: '20RB',
      valueCaption: 'POTONGAN',
      category: PromoCategory.member,
      minOrder: 60000,
      maxSaving: 20000,
      validDays: 30,
      quotaUsed: 0.12,
      colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
      terms: [
        'Khusus member dengan 10 pesanan selesai atau lebih.',
        'Minimal transaksi Rp 60.000.',
      ],
    ),
  ];

  static List<Promo> get flash => all.where((p) => p.isFlash).toList();
  static List<Promo> get regular => all.where((p) => !p.isFlash).toList();

  static Promo? byCode(String code) {
    final c = code.trim().toUpperCase();
    for (final p in all) {
      if (p.code == c) return p;
    }
    return null;
  }

  static const List<SubscriptionPlan> plans = [
    SubscriptionPlan(
      name: 'Hemat',
      tagline: 'Untuk anak kos',
      price: 99000,
      normalPrice: 130000,
      quota: '15 kg / bulan',
      features: ['Cuci + lipat', 'Antar jemput 2x', 'Selesai 2 hari'],
      colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
    ),
    SubscriptionPlan(
      name: 'Keluarga',
      tagline: 'Paling banyak dipilih',
      price: 249000,
      normalPrice: 380000,
      quota: '40 kg / bulan',
      features: [
        'Cuci + setrika',
        'Antar jemput gratis',
        'Prioritas antrian',
        'Hemat 35%',
      ],
      colors: [Color(0xFF0066CC), Color(0xFF6366F1)],
      popular: true,
    ),
    SubscriptionPlan(
      name: 'Premium',
      tagline: 'Semua beres tanpa mikir',
      price: 449000,
      normalPrice: 650000,
      quota: '80 kg / bulan',
      features: [
        'Cuci + setrika + parfum',
        'Dry clean 4 pcs',
        'Antar jemput sepuasnya',
        'Selesai 24 jam',
      ],
      colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
    ),
  ];
}

/// Voucher yang sudah diklaim pengguna (disimpan di perangkat).
class PromoWallet {
  PromoWallet._();
  static const _key = 'claimed_promo_ids';

  static Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> save(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ids.toList());
    } catch (_) {}
  }
}

String formatRupiah(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'Rp $buf';
}
