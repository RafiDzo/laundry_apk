import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import '../models/revenue_report.dart';

/// Kesalahan yang pesannya sudah siap ditampilkan ke mitra
class ReportException implements Exception {
  final String message;
  ReportException(this.message);
  @override
  String toString() => message;
}

/// Data untuk Laporan Omzet, Transaksi Hari Ini, dan Riwayat Layanan.
/// Semua query dibatasi RLS: mitra hanya melihat pesanan outlet miliknya.
class ReportService {
  final SupabaseClient _db = Supabase.instance.client;

  static const int pageSize = 20;

  // ================= LAPORAN OMZET =================

  /// [from] inklusif, [to] eksklusif (waktu lokal). Agregasi dilakukan oleh
  /// fungsi SQL washora_revenue_report; jika fungsinya belum dipasang,
  /// laporan dihitung di perangkat dari daftar pesanan.
  Future<RevenueReport> fetchRevenueReport(String shopId, DateTime from, DateTime to) async {
    _validateRange(from, to);
    try {
      final res = await _db.rpc('washora_revenue_report', params: {
        'p_shop_id': shopId,
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
        'p_tz': 'Asia/Jakarta',
      });
      return RevenueReport.fromJson(Map<String, dynamic>.from(res as Map), from, to);
    } on PostgrestException catch (e) {
      // PGRST202 / 42883 = fungsi belum ada → hitung di perangkat
      if (e.code == 'PGRST202' || e.code == '42883') {
        return _reportOnDevice(shopId, from, to);
      }
      throw ReportException(_message(e));
    } catch (e) {
      if (e is ReportException) rethrow;
      throw ReportException('Laporan gagal dimuat. Periksa koneksi internet lalu coba lagi.');
    }
  }

  Future<RevenueReport> _reportOnDevice(String shopId, DateTime from, DateTime to) async {
    final prevFrom = from.subtract(to.difference(from));
    final rows = await _db
        .from('orders')
        .select('id, status, total_price, items, payment_method, created_at')
        .eq('shop_id', shopId)
        .neq('status', 'cancelled')
        .gte('created_at', prevFrom.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String());
    final orders = rows.map<OrderModel>((r) => OrderModel.fromMap(r, r['id'])).toList();
    return RevenueReport.fromOrders(orders, from, to);
  }

  void _validateRange(DateTime from, DateTime to) {
    if (!to.isAfter(from)) throw ReportException('Tanggal akhir harus setelah tanggal awal.');
    if (to.difference(from).inDays > 366) {
      throw ReportException('Rentang laporan maksimal 1 tahun.');
    }
  }

  /// Pesanan dalam periode untuk ekspor (detail per transaksi)
  Future<List<OrderModel>> fetchOrdersInRange(String shopId, DateTime from, DateTime to) async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('shop_id', shopId)
          .gte('created_at', from.toUtc().toIso8601String())
          .lt('created_at', to.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(5000);
      return rows.map<OrderModel>((r) => OrderModel.fromMap(r, r['id'])).toList();
    } on PostgrestException catch (e) {
      throw ReportException(_message(e));
    } catch (_) {
      throw ReportException('Data transaksi gagal dimuat. Periksa koneksi internet.');
    }
  }

  // ================= TRANSAKSI HARI INI =================

  /// Stream realtime pesanan yang dibuat sejak [since] (biasanya awal hari ini),
  /// terbaru di atas.
  Stream<List<OrderModel>> watchOrdersSince(String shopId, DateTime since) {
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .limit(300)
        .map((rows) => rows
            .map<OrderModel>((r) => OrderModel.fromMap(r, r['id']))
            .where((o) => !o.createdAt.isBefore(since))
            .toList());
  }

  // ================= RIWAYAT LAYANAN =================

  /// Satu halaman riwayat pesanan yang sudah selesai dilayani
  /// (status done / delivered), terbaru di atas.
  Future<List<OrderModel>> fetchServiceHistory({
    required String shopId,
    required int page,
    DateTime? from,
    DateTime? to,
    String? service,
    String? customer,
  }) async {
    try {
      var q = _db
          .from('orders')
          .select()
          .eq('shop_id', shopId)
          .inFilter('status', ['done', 'delivered']);
      if (from != null) q = q.gte('created_at', from.toUtc().toIso8601String());
      if (to != null) q = q.lt('created_at', to.toUtc().toIso8601String());
      if (service != null && service.isNotEmpty) {
        q = q.contains('items', [
          {'name': service}
        ]);
      }
      final c = customer?.trim() ?? '';
      if (c.isNotEmpty) {
        final safe = c.replaceAll(RegExp(r'[%,()*]'), ' ');
        q = q.or('customer_name.ilike.%$safe%,customer_phone.ilike.%$safe%');
      }
      final start = page * pageSize;
      final rows = await q.order('created_at', ascending: false).range(start, start + pageSize - 1);
      return rows.map<OrderModel>((r) => OrderModel.fromMap(r, r['id'])).toList();
    } on PostgrestException catch (e) {
      throw ReportException(_message(e));
    } catch (_) {
      throw ReportException('Riwayat gagal dimuat. Periksa koneksi internet lalu coba lagi.');
    }
  }

  /// Semua pesanan satu pelanggan di outlet ini (aplikasi: user_id,
  /// walk-in: nomor HP, atau nama jika nomor HP tidak dicatat).
  Future<List<OrderModel>> fetchCustomerOrders(String shopId, OrderModel sample) async {
    try {
      var q = _db.from('orders').select().eq('shop_id', shopId);
      if (sample.userId.isNotEmpty) {
        q = q.eq('user_id', sample.userId);
      } else if ((sample.customerPhone ?? '').trim().isNotEmpty) {
        q = q.eq('customer_phone', sample.customerPhone!.trim());
      } else {
        q = q.isFilter('user_id', null).eq('customer_name', sample.customerName ?? '');
      }
      final rows = await q.order('created_at', ascending: false).limit(500);
      return rows.map<OrderModel>((r) => OrderModel.fromMap(r, r['id'])).toList();
    } on PostgrestException catch (e) {
      throw ReportException(_message(e));
    } catch (_) {
      throw ReportException('Riwayat pelanggan gagal dimuat. Periksa koneksi internet.');
    }
  }

  String _message(PostgrestException e) {
    if (e.code == '42501') {
      return 'Akses ditolak. Pastikan Anda login sebagai pemilik outlet ini.';
    }
    if (e.code == '22023') return e.message;
    return 'Gagal memuat data (${e.code ?? 'error'}). Coba lagi sebentar.';
  }
}
