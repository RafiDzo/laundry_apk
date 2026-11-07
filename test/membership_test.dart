import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/membership_models.dart';

void main() {
  final plans = [
    MembershipPlan.fromMap({'id': 'bronze', 'name': 'Bronze', 'price_monthly': 19000, 'price_yearly': 190000, 'free_delivery_quota': 4, 'points_pct': 1, 'claim_window_hours': 48}),
    MembershipPlan.fromMap({'id': 'gold', 'name': 'Gold', 'price_monthly': 99000, 'price_yearly': 990000, 'free_delivery_quota': null, 'points_pct': 3, 'claim_window_hours': 168, 'express_quota': 3, 'priority_queue': true}),
  ];

  Map<String, dynamic> row(String status, {DateTime? starts, DateTime? ends, DateTime? created, String plan = 'bronze'}) => {
        'id': '$status${created?.millisecondsSinceEpoch ?? 0}',
        'plan_id': plan,
        'status': status,
        'amount': 19000,
        'starts_at': starts?.toUtc().toIso8601String(),
        'ends_at': ends?.toUtc().toIso8601String(),
        'created_at': (created ?? DateTime.now()).toUtc().toIso8601String(),
      };

  test('benefit Gold: ongkir tanpa batas & klaim 7 hari', () {
    final g = plans[1];
    expect(g.benefits.first, contains('tanpa batas'));
    expect(g.claimWindowLabel, '7 hari');
    expect(g.priceFor('yearly'), 990000);
  });

  test('status aktif hanya dalam masa berlaku', () {
    final now = DateTime.now();
    final active = Membership.fromMap(row('active', starts: now.subtract(const Duration(days: 1)), ends: now.add(const Duration(days: 29))));
    final expired = Membership.fromMap(row('active', starts: now.subtract(const Duration(days: 40)), ends: now.subtract(const Duration(days: 10))));
    expect(active.isActiveNow, isTrue);
    expect(expired.isActiveNow, isFalse);
  });

  test('ringkasan: aktif, menunggu, penolakan terbaru', () {
    final now = DateTime.now();
    final s = MembershipState.fromRows(plans, [
      Membership.fromMap(row('rejected', created: now.subtract(const Duration(days: 2)))),
      Membership.fromMap(row('pending', created: now, plan: 'gold')),
    ]);
    expect(s.active, isNull);
    expect(s.pending?.planId, 'gold');
    expect(s.lastRejected, isNull); // sudah ada pengajuan baru
    expect(s.planOf(s.pending)?.name, 'Gold');
  });

  test('benefit checkout: sisa kuota gratis ongkir & tanpa batas', () {
    final b = MemberBenefits.fromJson({'active': true, 'plan_name': 'Bronze', 'free_delivery_quota': 4, 'free_delivery_used': 4, 'points_balance': 1200});
    expect(b.freeDeliveryLeft, 0);
    expect(b.canUseFreeDelivery, isFalse);
    final g = MemberBenefits.fromJson({'active': true, 'free_delivery_quota': null, 'free_delivery_used': 30});
    expect(g.freeDeliveryLeft, isNull);
    expect(g.canUseFreeDelivery, isTrue);
    expect(MemberBenefits.none.canUseFreeDelivery, isFalse);
  });
}
