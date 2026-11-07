import 'package:flutter/material.dart';

/// Paket langganan (tabel membership_plans)
class MembershipPlan {
  final String id; // bronze | silver | gold
  final String name;
  final int priceMonthly;
  final int priceYearly;
  final int? freeDeliveryQuota; // per bulan; null = tanpa batas
  final double pointsPct;
  final int memberDiscountPct;
  final int claimWindowHours;
  final int expressQuota;
  final bool priorityQueue;
  final bool birthdayVoucher;

  const MembershipPlan({
    required this.id,
    required this.name,
    required this.priceMonthly,
    required this.priceYearly,
    required this.freeDeliveryQuota,
    required this.pointsPct,
    required this.memberDiscountPct,
    required this.claimWindowHours,
    required this.expressQuota,
    required this.priorityQueue,
    required this.birthdayVoucher,
  });

  factory MembershipPlan.fromMap(Map<String, dynamic> m) => MembershipPlan(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        priceMonthly: (m['price_monthly'] as num?)?.toInt() ?? 0,
        priceYearly: (m['price_yearly'] as num?)?.toInt() ?? 0,
        freeDeliveryQuota: (m['free_delivery_quota'] as num?)?.toInt(),
        pointsPct: (m['points_pct'] as num?)?.toDouble() ?? 0,
        memberDiscountPct: (m['member_discount_pct'] as num?)?.toInt() ?? 0,
        claimWindowHours: (m['claim_window_hours'] as num?)?.toInt() ?? 48,
        expressQuota: (m['express_quota'] as num?)?.toInt() ?? 0,
        priorityQueue: m['priority_queue'] == true,
        birthdayVoucher: m['birthday_voucher'] == true,
      );

  int priceFor(String period) => period == 'yearly' ? priceYearly : priceMonthly;

  /// Warna tingkat: perunggu, perak, emas (dipakai badge & kartu)
  Color get color => switch (id) {
        'gold' => const Color(0xFFB7791F),
        'silver' => const Color(0xFF64748B),
        _ => const Color(0xFF9A5B2E),
      };
  Color get softColor => switch (id) {
        'gold' => const Color(0xFFFEF3C7),
        'silver' => const Color(0xFFF1F5F9),
        _ => const Color(0xFFFBEAD9),
      };

  String get claimWindowLabel =>
      claimWindowHours % 24 == 0 && claimWindowHours >= 168 ? '${claimWindowHours ~/ 24} hari' : '$claimWindowHours jam';

  /// Daftar benefit untuk ditampilkan (urut dari yang paling terasa)
  List<String> get benefits => [
        freeDeliveryQuota == null ? 'Gratis ongkir antar-jemput tanpa batas (wajar pakai)' : 'Gratis ongkir $freeDeliveryQuota× per bulan',
        'Poin ${pointsPct.toStringAsFixed(pointsPct == pointsPct.roundToDouble() ? 0 : 1)}% dari setiap transaksi',
        if (memberDiscountPct > 0) 'Diskon $memberDiscountPct% di outlet Mitra Member',
        'Batas klaim kerusakan $claimWindowLabel',
        if (priorityQueue) 'Prioritas antrean di outlet',
        if (expressQuota > 0) 'Gratis upgrade Express $expressQuota× per bulan',
        if (birthdayVoucher) 'Voucher ulang tahun',
      ];
}

/// Langganan milik pelanggan (tabel memberships)
class Membership {
  final String id;
  final String planId;
  final String period; // monthly | yearly
  final String status; // pending | active | rejected | cancelled
  final int amount;
  final String paymentMethod;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int freeDeliveryUsed;
  final int expressUsed;
  final bool cancelAtPeriodEnd;
  final String? adminNote;
  final DateTime createdAt;

  const Membership({
    required this.id,
    required this.planId,
    required this.period,
    required this.status,
    required this.amount,
    required this.paymentMethod,
    required this.startsAt,
    required this.endsAt,
    required this.freeDeliveryUsed,
    required this.expressUsed,
    required this.cancelAtPeriodEnd,
    required this.adminNote,
    required this.createdAt,
  });

  factory Membership.fromMap(Map<String, dynamic> m) {
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return Membership(
      id: m['id'] as String,
      planId: m['plan_id'] as String,
      period: (m['period'] as String?) ?? 'monthly',
      status: (m['status'] as String?) ?? 'pending',
      amount: (m['amount'] as num?)?.toInt() ?? 0,
      paymentMethod: (m['payment_method'] as String?) ?? 'transfer',
      startsAt: d(m['starts_at']),
      endsAt: d(m['ends_at']),
      freeDeliveryUsed: (m['free_delivery_used'] as num?)?.toInt() ?? 0,
      expressUsed: (m['express_used'] as num?)?.toInt() ?? 0,
      cancelAtPeriodEnd: m['cancel_at_period_end'] == true,
      adminNote: m['admin_note'] as String?,
      createdAt: d(m['created_at']) ?? DateTime.now(),
    );
  }

  bool isActiveAt(DateTime t) =>
      status == 'active' && startsAt != null && endsAt != null && !t.isBefore(startsAt!) && t.isBefore(endsAt!);
  bool get isActiveNow => isActiveAt(DateTime.now());
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  int get daysLeft => endsAt == null ? 0 : endsAt!.difference(DateTime.now()).inDays;
}

/// Ringkasan status langganan pelanggan saat ini
class MembershipState {
  final List<MembershipPlan> plans;
  final Membership? active;
  final Membership? pending;
  final Membership? lastRejected;

  const MembershipState({required this.plans, this.active, this.pending, this.lastRejected});

  MembershipPlan? planOf(Membership? m) => m == null ? null : plans.where((p) => p.id == m.planId).firstOrNull;

  static MembershipState fromRows(List<MembershipPlan> plans, List<Membership> rows) {
    final now = DateTime.now();
    final active = rows.where((m) => m.isActiveAt(now)).toList()..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
    final pending = rows.where((m) => m.isPending).firstOrNull;
    final rejected = rows.where((m) => m.isRejected).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Penolakan hanya relevan jika belum ada pengajuan yang lebih baru
    final lastRejected = rejected.isNotEmpty &&
            pending == null &&
            (active.isEmpty || rejected.first.createdAt.isAfter(active.first.createdAt))
        ? rejected.first
        : null;
    return MembershipState(
      plans: plans,
      active: active.firstOrNull,
      pending: pending,
      lastRejected: lastRejected,
    );
  }
}

/// Benefit yang bisa dipakai saat checkout (RPC my_member_benefits)
class MemberBenefits {
  final bool active;
  final String? planId;
  final String? planName;
  final int? freeDeliveryQuota; // null = tanpa batas
  final int freeDeliveryUsed;
  final double pointsPct;
  final int pointsBalance;
  final int claimHours;

  const MemberBenefits({
    required this.active,
    this.planId,
    this.planName,
    this.freeDeliveryQuota,
    this.freeDeliveryUsed = 0,
    this.pointsPct = 0,
    this.pointsBalance = 0,
    this.claimHours = 48,
  });

  static const none = MemberBenefits(active: false);

  factory MemberBenefits.fromJson(Map<String, dynamic> j) => MemberBenefits(
        active: j['active'] == true,
        planId: j['plan_id'] as String?,
        planName: j['plan_name'] as String?,
        freeDeliveryQuota: (j['free_delivery_quota'] as num?)?.toInt(),
        freeDeliveryUsed: (j['free_delivery_used'] as num?)?.toInt() ?? 0,
        pointsPct: (j['points_pct'] as num?)?.toDouble() ?? 0,
        pointsBalance: (j['points_balance'] as num?)?.toInt() ?? 0,
        claimHours: (j['claim_hours'] as num?)?.toInt() ?? 48,
      );

  /// Sisa gratis ongkir bulan ini; null = tanpa batas
  int? get freeDeliveryLeft {
    final q = freeDeliveryQuota;
    if (q == null) return null;
    return (q - freeDeliveryUsed).clamp(0, q);
  }

  bool get canUseFreeDelivery => active && (freeDeliveryLeft == null || freeDeliveryLeft! > 0);
}

class PaymentInfo {
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String qrisImageUrl;
  final String note;

  const PaymentInfo({
    this.bankName = '',
    this.accountNumber = '',
    this.accountName = '',
    this.qrisImageUrl = '',
    this.note = '',
  });

  factory PaymentInfo.fromMap(Map<String, dynamic> m) => PaymentInfo(
        bankName: (m['bank_name'] as String?) ?? '',
        accountNumber: (m['account_number'] as String?) ?? '',
        accountName: (m['account_name'] as String?) ?? '',
        qrisImageUrl: (m['qris_image_url'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
      );

  bool get hasTransfer => bankName.trim().isNotEmpty && accountNumber.trim().isNotEmpty;
  bool get hasQris => qrisImageUrl.trim().isNotEmpty;
}
