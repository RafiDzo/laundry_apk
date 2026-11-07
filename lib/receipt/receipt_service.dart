import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import '../models/shop_model.dart';
import 'receipt_builder.dart';

class ReceiptException implements Exception {
  final String message;
  ReceiptException(this.message);
  @override
  String toString() => message;
}

/// Mengambil data struk dari server: pesanan, outlet, kasir, tingkat member.
/// RLS orders memastikan hanya pemilik outlet (atau pelanggannya) yang bisa membaca.
class ReceiptService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<ReceiptData> load(String orderId, {bool isCopy = false}) async {
    final Map<String, dynamic>? row;
    try {
      row = await _db.from('orders').select().eq('id', orderId).maybeSingle();
    } catch (_) {
      throw ReceiptException('Data pesanan gagal dimuat. Periksa koneksi lalu coba lagi.');
    }
    if (row == null) {
      throw ReceiptException('Pesanan tidak ditemukan, atau akun ini bukan pemilik outlet pesanan tersebut.');
    }
    final order = OrderModel.fromMap(row, row['id'] as String);

    ShopModel? shop;
    try {
      final s = await _db.from('shops').select().eq('id', order.shopId).maybeSingle();
      if (s != null) shop = ShopModel.fromMap(s, s['id'].toString());
    } catch (_) {}

    var cashier = '';
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        final u = await _db.from('users').select('name').eq('id', uid).maybeSingle();
        cashier = (u?['name'] as String?) ?? '';
      } catch (_) {}
    }

    // Tingkat member & batas klaim (supabase_langganan.sql); tanpa SQL → standar 48 jam
    String? tier;
    var claimHours = 48;
    try {
      final planId = await _db.rpc('member_tier_for_order', params: {'p_order_id': order.id});
      if (planId is String && planId.isNotEmpty) {
        final p = await _db.from('membership_plans').select('name, claim_window_hours').eq('id', planId).maybeSingle();
        tier = (p?['name'] as String?) ?? planId;
        claimHours = (p?['claim_window_hours'] as num?)?.toInt() ?? 48;
      }
    } catch (_) {}

    // Estimasi dari durasi layanan outlet yang namanya cocok dengan item pertama
    String? estimate;
    if (shop != null && order.items.isNotEmpty) {
      final name = order.items.first.name.trim().toLowerCase();
      final svc = shop.services.where((s) => s.name.trim().toLowerCase() == name).firstOrNull;
      if (svc != null && svc.duration.trim().isNotEmpty) estimate = svc.duration.trim();
    }

    DateTime? paidAt;
    if (row['paid_at'] != null) paidAt = DateTime.tryParse('${row['paid_at']}')?.toLocal();

    return ReceiptData(
      order: order,
      shopName: shop?.name ?? order.shopName,
      shopAddress: shop?.address ?? '',
      shopPhone: shop?.phone ?? '',
      cashierName: cashier,
      memberTier: tier,
      claimWindowHours: claimHours,
      estimate: estimate,
      paidAt: paidAt,
      cashReceived: (row['cash_received'] as num?)?.toInt(),
      isCopy: isCopy,
      printedAt: DateTime.now(),
    );
  }

  /// Tandai pesanan lunas (mitra). [cashReceived] diisi untuk pembayaran tunai.
  Future<void> markPaid(String orderId, {int? cashReceived}) async {
    try {
      final res = await _db
          .from('orders')
          .update({
            'paid_at': DateTime.now().toUtc().toIso8601String(),
            'cash_received': cashReceived,
          })
          .eq('id', orderId)
          .select('id');
      if (res.isEmpty) throw ReceiptException('Gagal menyimpan: akun ini bukan pemilik outlet pesanan ini.');
    } on PostgrestException catch (e) {
      if (e.code == '42703' || e.code == 'PGRST204') {
        throw ReceiptException('Kolom status bayar belum ada. Jalankan supabase_langganan.sql di Supabase.');
      }
      throw ReceiptException('Gagal menyimpan status bayar (${e.code}).');
    }
  }
}
