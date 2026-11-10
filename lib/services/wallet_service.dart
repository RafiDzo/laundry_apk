import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class WalletException implements Exception {
  final String message;
  WalletException(this.message);
  @override
  String toString() => message;
}

/// Ringkasan saldo komisi outlet (RPC my_wallet)
class WalletSummary {
  final int balance;
  final int creditLimit;
  final int commissionAmount;
  final bool commissionActive; // false = masa pengenalan (gratis)
  final bool acceptingOrders;
  final int waivedOrders;
  final int waivedAmount;
  final int ordersThisMonth;

  const WalletSummary({
    required this.balance,
    required this.creditLimit,
    required this.commissionAmount,
    required this.commissionActive,
    required this.acceptingOrders,
    required this.waivedOrders,
    required this.waivedAmount,
    required this.ordersThisMonth,
  });

  factory WalletSummary.fromJson(Map<String, dynamic> j) {
    int i(String k) => (j[k] as num?)?.toInt() ?? 0;
    return WalletSummary(
      balance: i('balance'),
      creditLimit: i('credit_limit'),
      commissionAmount: i('commission_amount'),
      commissionActive: j['commission_active'] == true,
      acceptingOrders: j['accepting_orders'] != false,
      waivedOrders: i('waived_orders'),
      waivedAmount: i('waived_amount'),
      ordersThisMonth: i('orders_this_month'),
    );
  }

  /// Sisa ruang sebelum batas kredit (bisa dipakai untuk N pesanan lagi)
  int get headroom => balance + creditLimit;
  int get ordersLeft => commissionAmount <= 0 ? 0 : (headroom ~/ commissionAmount).clamp(0, 99999);

  WalletState get state {
    if (!commissionActive) return WalletState.intro;
    if (!acceptingOrders) return WalletState.blocked;
    if (balance < 0) return WalletState.owing;
    if (commissionAmount > 0 && balance < commissionAmount * 5) return WalletState.low;
    return WalletState.ok;
  }
}

enum WalletState { intro, ok, low, owing, blocked }

class WalletEntry {
  final String id;
  final String? orderId;
  final String type; // welcome | topup | commission | commission_waived | refund | adjust
  final int amount;
  final int balanceAfter;
  final String note;
  final DateTime createdAt;

  const WalletEntry({
    required this.id,
    required this.orderId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.note,
    required this.createdAt,
  });

  factory WalletEntry.fromMap(Map<String, dynamic> m) => WalletEntry(
        id: m['id'] as String,
        orderId: m['order_id'] as String?,
        type: (m['type'] as String?) ?? 'adjust',
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        balanceAfter: (m['balance_after'] as num?)?.toInt() ?? 0,
        note: (m['note'] as String?) ?? '',
        createdAt: DateTime.parse(m['created_at']).toLocal(),
      );

  String get label => switch (type) {
        'welcome' => 'Saldo awal gratis',
        'topup' => 'Isi saldo',
        'commission' => 'Komisi pesanan',
        'commission_waived' => 'Komisi digratiskan',
        'refund' => 'Pengembalian komisi',
        _ => 'Penyesuaian',
      };
}

class WalletTopup {
  final String id;
  final int amount;
  final int uniqueCode;
  final int payable;
  final String status; // pending | approved | rejected
  final String? adminNote;
  final DateTime createdAt;

  const WalletTopup({
    required this.id,
    required this.amount,
    required this.uniqueCode,
    required this.payable,
    required this.status,
    required this.adminNote,
    required this.createdAt,
  });

  factory WalletTopup.fromMap(Map<String, dynamic> m) => WalletTopup(
        id: m['id'] as String,
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        uniqueCode: (m['unique_code'] as num?)?.toInt() ?? 0,
        payable: (m['payable'] as num?)?.toInt() ?? 0,
        status: (m['status'] as String?) ?? 'pending',
        adminNote: m['admin_note'] as String?,
        createdAt: DateTime.parse(m['created_at']).toLocal(),
      );
}

/// Saldo komisi mitra (supabase_saldo_komisi.sql). Potongan & persetujuan isi
/// saldo dilakukan server; aplikasi hanya membaca dan mengajukan isi saldo.
class WalletService {
  final SupabaseClient _db = Supabase.instance.client;

  WalletException _wrap(Object e, String fallback) {
    if (e is WalletException) return e;
    if (e is PostgrestException) {
      if (e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42P01' || e.code == '42883') {
        return WalletException('Saldo komisi belum aktif. Jalankan supabase_saldo_komisi.sql di Supabase.');
      }
      if (e.code == '23505') return WalletException('Masih ada pengajuan isi saldo yang menunggu konfirmasi.');
      if (e.code == '22023') return WalletException(e.message);
      if (e.code == '42501') return WalletException('Akses ditolak: akun ini bukan pemilik outlet.');
      return WalletException('$fallback (${e.code ?? 'error'}).');
    }
    if (e is StorageException) {
      final m = e.message.toLowerCase();
      if (m.contains('bucket') && m.contains('not found')) {
        return WalletException('Penyimpanan bukti belum dibuat. Jalankan supabase_saldo_komisi.sql.');
      }
      return WalletException('Bukti gagal diunggah: ${e.message}');
    }
    return WalletException('$fallback. Periksa koneksi internet.');
  }

  Future<WalletSummary> summary(String shopId) async {
    try {
      final r = await _db.rpc('my_wallet', params: {'p_shop_id': shopId});
      return WalletSummary.fromJson(Map<String, dynamic>.from(r as Map));
    } catch (e) {
      throw _wrap(e, 'Saldo gagal dimuat');
    }
  }

  Future<List<WalletEntry>> ledger(String shopId, {int limit = 50}) async {
    try {
      final rows = await _db.from('wallet_ledger').select().eq('shop_id', shopId).order('created_at', ascending: false).limit(limit);
      return rows.map<WalletEntry>(WalletEntry.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Riwayat saldo gagal dimuat');
    }
  }

  Future<List<WalletTopup>> topups(String shopId) async {
    try {
      final rows = await _db.from('wallet_topups').select().eq('shop_id', shopId).order('created_at', ascending: false).limit(10);
      return rows.map<WalletTopup>(WalletTopup.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Pengajuan isi saldo gagal dimuat');
    }
  }

  /// Teks QRIS statis Washora (platform_settings.qris_payload); kosong jika belum diatur
  Future<String> platformQris() async {
    try {
      final r = await _db.from('platform_settings').select('qris_payload').maybeSingle();
      return (r?['qris_payload'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Ajukan isi saldo. [uniqueCode] (100-999) ditambahkan ke nominal QR agar
  /// admin mudah mencocokkan dana masuk; bukti diunggah lebih dulu.
  Future<WalletTopup> requestTopup(String shopId, int amount, int uniqueCode, Uint8List proof, {String mime = 'image/jpeg'}) async {
    final ext = switch (mime) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$shopId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _db.storage.from('wallet-proofs').uploadBinary(path, proof, fileOptions: FileOptions(contentType: mime));
      final row = await _db
          .from('wallet_topups')
          .insert({'shop_id': shopId, 'amount': amount, 'unique_code': uniqueCode, 'proof_path': path})
          .select()
          .single();
      return WalletTopup.fromMap(row);
    } catch (e) {
      throw _wrap(e, 'Pengajuan isi saldo gagal');
    }
  }

  Future<bool> shopAcceptingOrders(String shopId) async {
    try {
      final r = await _db.rpc('shop_accepting_orders', params: {'p_shop_id': shopId});
      return r != false;
    } catch (_) {
      return true; // tanpa SQL saldo: tidak membatasi
    }
  }
}
