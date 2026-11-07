import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/membership_models.dart';
import '../models/order_model.dart';

class MembershipException implements Exception {
  final String message;
  MembershipException(this.message);
  @override
  String toString() => message;
}

/// Langganan member Bronze/Silver/Gold (supabase_langganan.sql).
/// Harga & status ditentukan server; aplikasi hanya mengajukan + mengunggah bukti bayar.
class MembershipService {
  final SupabaseClient _db = Supabase.instance.client;

  MembershipException _wrap(Object e, String fallback) {
    if (e is MembershipException) return e;
    if (e is PostgrestException) {
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return MembershipException('Fitur langganan belum aktif. Jalankan supabase_langganan.sql di Supabase.');
      }
      if (e.code == '23505') return MembershipException('Kamu masih punya pengajuan yang menunggu konfirmasi.');
      if (e.code == '22023') return MembershipException(e.message);
      return MembershipException('$fallback (${e.code ?? 'error'}).');
    }
    if (e is StorageException) {
      final m = e.message.toLowerCase();
      if (m.contains('bucket') && m.contains('not found')) {
        return MembershipException('Penyimpanan bukti bayar belum dibuat. Jalankan supabase_langganan.sql.');
      }
      return MembershipException('Bukti bayar gagal diunggah: ${e.message}');
    }
    return MembershipException('$fallback. Periksa koneksi internet lalu coba lagi.');
  }

  Future<List<MembershipPlan>> fetchPlans() async {
    try {
      final rows = await _db.from('membership_plans').select().order('sort_order');
      return rows.map<MembershipPlan>(MembershipPlan.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Paket gagal dimuat');
    }
  }

  Future<MembershipState> fetchState() async {
    final uid = _db.auth.currentUser?.id;
    final plans = await fetchPlans();
    if (uid == null) return MembershipState(plans: plans);
    try {
      final rows = await _db.from('memberships').select().eq('user_id', uid).order('created_at', ascending: false).limit(20);
      return MembershipState.fromRows(plans, rows.map<Membership>(Membership.fromMap).toList());
    } catch (e) {
      throw _wrap(e, 'Status langganan gagal dimuat');
    }
  }

  Future<PaymentInfo> fetchPaymentInfo() async {
    try {
      final row = await _db.from('membership_payment_info').select().maybeSingle();
      return row == null ? const PaymentInfo() : PaymentInfo.fromMap(row);
    } catch (e) {
      throw _wrap(e, 'Info pembayaran gagal dimuat');
    }
  }

  /// Ajukan langganan: unggah bukti bayar lalu buat baris 'pending'
  Future<Membership> submit({
    required String planId,
    required String period,
    required String paymentMethod,
    required Uint8List proof,
    String mime = 'image/jpeg',
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw MembershipException('Sesi login berakhir. Silakan login ulang.');
    if (proof.lengthInBytes > 3 * 1024 * 1024) throw MembershipException('Ukuran bukti bayar melebihi 3 MB.');
    final ext = switch (mime) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _db.storage.from('membership-proofs').uploadBinary(path, proof, fileOptions: FileOptions(contentType: mime));
      final row = await _db
          .from('memberships')
          .insert({
            'plan_id': planId,
            'period': period,
            'payment_method': paymentMethod,
            'proof_path': path,
          })
          .select()
          .single();
      return Membership.fromMap(row);
    } catch (e) {
      throw _wrap(e, 'Pengajuan langganan gagal dikirim');
    }
  }

  Future<void> setCancelAtPeriodEnd(String membershipId, bool cancel) async {
    try {
      await _db.from('memberships').update({'cancel_at_period_end': cancel}).eq('id', membershipId);
    } catch (e) {
      throw _wrap(e, 'Pengaturan langganan gagal disimpan');
    }
  }

  /// Benefit aktif pelanggan yang login (RPC my_member_benefits). Tanpa SQL tahap 2
  /// atau tanpa langganan → tidak aktif, poin 0, klaim 48 jam.
  Future<MemberBenefits> fetchBenefits() async {
    try {
      final res = await _db.rpc('my_member_benefits');
      return MemberBenefits.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return MemberBenefits.none;
    }
  }

  /// Batas klaim (jam) untuk pesanan ini, sesuai langganan saat cucian diterima.
  Future<int> claimHoursFor(OrderModel order) async {
    if (order.userId.isEmpty) return 48;
    try {
      final res = await _db.rpc('claim_window_hours', params: {
        'p_user': order.userId,
        'p_at': (order.receivedAt ?? DateTime.now()).toUtc().toIso8601String(),
      });
      return res is num ? res.toInt() : 48;
    } catch (_) {
      return 48;
    }
  }

  /// Ongkir yang benar-benar dibayar pelanggan 30 hari terakhir (pesanan antar-jemput):
  /// total + potongan - harga item - biaya layanan. Dipakai sebagai fakta pembanding, bukan janji.
  Future<(int amount, int orders)> deliverySpentLast30Days() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return (0, 0);
    try {
      final since = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
      final rows = await _db
          .from('orders')
          .select('total_price, service_fee, items, delivery_type, status')
          .eq('user_id', uid)
          .gte('created_at', since)
          .neq('status', 'cancelled');
      var total = 0, count = 0;
      for (final r in rows) {
        if ((r['delivery_type'] ?? 'pickup') == 'dropoff') continue;
        final items = (r['items'] as List?) ?? const [];
        final sub = items.fold<num>(0, (s, i) => s + ((i['price'] as num?) ?? 0) * ((i['qty'] as num?) ?? 0));
        final fee = ((r['total_price'] as num?) ?? 0) - sub - ((r['service_fee'] as num?) ?? 0);
        if (fee > 0) {
          total += fee.round();
          count++;
        }
      }
      return (total, count);
    } catch (_) {
      return (0, 0);
    }
  }
}
