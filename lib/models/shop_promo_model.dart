import 'package:flutter/material.dart';

enum ShopPromoType {
  discountPct('discount_pct', 'Diskon Persen', 'Diskon %', Icons.percent_rounded),
  discountFlat('discount_flat', 'Potongan Harga', 'Potongan Rp', Icons.local_offer_rounded),
  freeDelivery('free_delivery', 'Gratis Ongkir', 'Gratis Ongkir', Icons.local_shipping_rounded),
  cashback('cashback', 'Cashback Poin', 'Cashback', Icons.savings_rounded);

  final String key;
  final String label;
  final String shortLabel;
  final IconData icon;

  const ShopPromoType(this.key, this.label, this.shortLabel, this.icon);

  static ShopPromoType fromKey(String? key) {
    return ShopPromoType.values.firstWhere(
      (e) => e.key == key,
      orElse: () => ShopPromoType.discountPct,
    );
  }

  Color get color {
    switch (this) {
      case ShopPromoType.discountPct:
        return const Color(0xFF0077E6);
      case ShopPromoType.discountFlat:
        return const Color(0xFF0284C7);
      case ShopPromoType.freeDelivery:
        return const Color(0xFF10B981);
      case ShopPromoType.cashback:
        return const Color(0xFFF59E0B);
    }
  }

  Color get lightColor {
    switch (this) {
      case ShopPromoType.discountPct:
        return const Color(0xFFEFF6FF);
      case ShopPromoType.discountFlat:
        return const Color(0xFFE0F2FE);
      case ShopPromoType.freeDelivery:
        return const Color(0xFFECFDF5);
      case ShopPromoType.cashback:
        return const Color(0xFFFEF3C7);
    }
  }
}

class ShopPromoModel {
  final String id;
  final String shopId;
  final String title;
  final ShopPromoType type;
  final int value; // mis. 20 untuk 20%, atau 10000 untuk Rp 10.000
  final int maxSaving; // batas potongan maksimal dalam rupiah (0 = tanpa batas)
  final int minOrder; // minimal transaksi dalam rupiah
  final String? code; // kode voucher, misal "HEMAT20" (null = otomatis)
  final int? quota; // kuota pemakaian (null = tidak terbatas)
  final int usedCount; // jumlah sudah diklaim / dipakai
  final DateTime startAt; // tanggal mulai
  final DateTime? endAt; // tanggal berakhir (null = berlaku terus)
  final List<int> activeDays; // 1 = Senin, ..., 7 = Minggu
  final List<String> serviceIds; // daftar ID layanan (kosong = semua layanan)
  final bool isActive;
  final DateTime? createdAt;

  const ShopPromoModel({
    required this.id,
    required this.shopId,
    required this.title,
    required this.type,
    required this.value,
    this.maxSaving = 0,
    this.minOrder = 0,
    this.code,
    this.quota,
    this.usedCount = 0,
    required this.startAt,
    this.endAt,
    this.activeDays = const [1, 2, 3, 4, 5, 6, 7],
    this.serviceIds = const [],
    this.isActive = true,
    this.createdAt,
  });

  bool get isUnlimitedQuota => quota == null || quota! <= 0;

  int get remainingQuota {
    if (isUnlimitedQuota) return 999999;
    final left = quota! - usedCount;
    return left < 0 ? 0 : left;
  }

  bool get isQuotaExhausted => !isUnlimitedQuota && usedCount >= quota!;

  bool get isExpired => endAt != null && DateTime.now().isAfter(endAt!);

  bool get isUpcoming => DateTime.now().isBefore(startAt);

  bool get isRunningNow => isActive && !isExpired && !isUpcoming && !isQuotaExhausted;

  double get quotaProgress {
    if (isUnlimitedQuota || quota == 0) return 0.0;
    return (usedCount / quota!).clamp(0.0, 1.0);
  }

  String get valueDisplay {
    switch (type) {
      case ShopPromoType.discountPct:
        return '$value%';
      case ShopPromoType.discountFlat:
        return 'Rp ${_formatNum(value)}';
      case ShopPromoType.freeDelivery:
        return 'Gratis Ongkir';
      case ShopPromoType.cashback:
        return '$value% Poin';
    }
  }

  String get summaryDescription {
    final parts = <String>[];
    if (minOrder > 0) parts.add('Min. Rp ${_formatNum(minOrder)}');
    if (type == ShopPromoType.discountPct && maxSaving > 0) {
      parts.add('Maks. Rp ${_formatNum(maxSaving)}');
    }
    if (serviceIds.isNotEmpty) {
      parts.add('${serviceIds.length} Layanan');
    } else {
      parts.add('Semua Layanan');
    }
    return parts.join(' • ');
  }

  static String _formatNum(num n) {
    final s = n.toInt().toString();
    return s.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  factory ShopPromoModel.fromMap(Map<String, dynamic> map, [String? fallbackId]) {
    final daysRaw = map['active_days'];
    List<int> parsedDays = [1, 2, 3, 4, 5, 6, 7];
    if (daysRaw is List) {
      parsedDays = daysRaw.map((e) => (e as num).toInt()).toList();
    }

    final servicesRaw = map['service_ids'];
    List<String> parsedServices = [];
    if (servicesRaw is List) {
      parsedServices = servicesRaw.map((e) => e.toString()).toList();
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return ShopPromoModel(
      id: map['id']?.toString() ?? fallbackId ?? '',
      shopId: map['shop_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      type: ShopPromoType.fromKey(map['type']?.toString()),
      value: (map['value'] as num?)?.toInt() ?? 0,
      maxSaving: (map['max_saving'] as num?)?.toInt() ?? 0,
      minOrder: (map['min_order'] as num?)?.toInt() ?? 0,
      code: map['code']?.toString().trim().isEmpty == true ? null : map['code']?.toString(),
      quota: (map['quota'] as num?)?.toInt(),
      usedCount: (map['used_count'] as num?)?.toInt() ?? 0,
      startAt: parseDate(map['start_at']) ?? DateTime.now(),
      endAt: parseDate(map['end_at']),
      activeDays: parsedDays,
      serviceIds: parsedServices,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shop_id': shopId,
      'title': title,
      'type': type.key,
      'value': value,
      'max_saving': maxSaving,
      'min_order': minOrder,
      'code': (code == null || code!.trim().isEmpty) ? null : code!.trim().toUpperCase(),
      'quota': quota,
      'used_count': usedCount,
      'start_at': startAt.toIso8601String(),
      'end_at': endAt?.toIso8601String(),
      'active_days': activeDays,
      'service_ids': serviceIds,
      'is_active': isActive,
    };
  }

  ShopPromoModel copyWith({
    String? id,
    String? shopId,
    String? title,
    ShopPromoType? type,
    int? value,
    int? maxSaving,
    int? minOrder,
    String? code,
    int? quota,
    int? usedCount,
    DateTime? startAt,
    DateTime? endAt,
    List<int>? activeDays,
    List<String>? serviceIds,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return ShopPromoModel(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      title: title ?? this.title,
      type: type ?? this.type,
      value: value ?? this.value,
      maxSaving: maxSaving ?? this.maxSaving,
      minOrder: minOrder ?? this.minOrder,
      code: code ?? this.code,
      quota: quota ?? this.quota,
      usedCount: usedCount ?? this.usedCount,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      activeDays: activeDays ?? this.activeDays,
      serviceIds: serviceIds ?? this.serviceIds,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
