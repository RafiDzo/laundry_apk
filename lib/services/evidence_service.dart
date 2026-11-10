import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/evidence_models.dart';

/// Foto bukti, serah terima, dan klaim kerusakan.
/// Aturan aksesnya dikunci di database (lihat supabase_bukti_klaim.sql).
class EvidenceService {
  final SupabaseClient _db = Supabase.instance.client;
  static const String _bucket = 'order-photos';

  // ================= FOTO BUKTI =================

  /// Unggah foto ke storage lalu catat di tabel order_photos.
  /// Path: {orderId}/{stage}/{timestamp}_{n}.{ext} — dipakai policy storage.
  Future<void> uploadPhotos({
    required String orderId,
    required String stage,
    required List<XFile> files,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? _guessMime(file.name);
      final ext = mime.split('/').last == 'jpeg' ? 'jpg' : mime.split('/').last;
      final path = '$orderId/$stage/${stamp}_$i.$ext';

      await _db.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      await _db.from('order_photos').insert({
        'order_id': orderId,
        'stage': stage,
        'storage_path': path,
        'uploaded_by': _db.auth.currentUser?.id,
      });
    }
  }

  /// Dipanggil saat database menolak akses: cari tahu penyebab sebenarnya.
  /// Mengembalikan pesan untuk mitra, atau null jika sesi & outlet sudah benar.
  Future<String?> diagnoseOwnerAccess(String shopId) async {
    final user = _db.auth.currentUser;
    if (user == null) return 'Sesi login habis. Silakan logout lalu login ulang.';
    try {
      final row = await _db
          .from('shops')
          .select('id')
          .eq('id', shopId)
          .eq('owner_id', user.id)
          .maybeSingle();
      if (row == null) {
        return 'Akses ditolak: akun yang sedang login (${user.email ?? user.id}) '
            'bukan pemilik outlet pesanan ini. Jika Anda login akun pelanggan di tab lain '
            'pada browser yang sama, sesi mitra ikut tertimpa — logout lalu login ulang '
            'sebagai mitra (pakai jendela Incognito untuk akun pelanggan).';
      }
      return null;
    } catch (e) {
      debugPrint('Error diagnoseOwnerAccess: $e');
      return null;
    }
  }

  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Semua foto bukti pesanan beserta URL sementara (berlaku 1 jam)
  Future<List<OrderPhoto>> getPhotos(String orderId) async {
    try {
      final rows = await _db
          .from('order_photos')
          .select()
          .eq('order_id', orderId)
          .order('created_at');
      if (rows.isEmpty) return [];

      final paths = rows.map<String>((r) => r['storage_path'] as String).toList();
      final signed = await _db.storage.from(_bucket).createSignedUrls(paths, 3600);
      final urlByPath = {for (final s in signed) s.path: s.signedUrl};

      return rows
          .map<OrderPhoto>((r) => OrderPhoto.fromMap(r, url: urlByPath[r['storage_path']]))
          .toList();
    } catch (e) {
      debugPrint('Error getPhotos: $e');
      return [];
    }
  }

  // ================= PENERIMAAN =================

  /// Catatan kondisi saat cucian diterima outlet (foto diunggah terpisah)
  Future<void> saveIntake({
    required String orderId,
    required int itemCount,
    required String note,
  }) async {
    await _db.from('orders').update({
      'intake_item_count': itemCount,
      'intake_note': note.trim().isEmpty ? null : note.trim(),
      'intake_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  // ================= SERAH TERIMA =================

  /// Kode 4 digit milik pelanggan (null jika bukan pemilik pesanan)
  Future<String?> getHandoverCode(String orderId) async {
    try {
      final row = await _db
          .from('order_handover_codes')
          .select('code')
          .eq('order_id', orderId)
          .maybeSingle();
      return row?['code'] as String?;
    } catch (e) {
      debugPrint('Error getHandoverCode: $e');
      return null;
    }
  }

  /// Mitra: konfirmasi serah terima dengan kode pelanggan.
  /// Hasil: OK | NOT_ALLOWED | NOT_READY | PHOTO_REQUIRED | NO_CODE | LOCKED | WRONG_CODE
  Future<String> confirmHandover(String orderId, String? code) async {
    final res = await _db.rpc('confirm_handover', params: {'p_order_id': orderId, 'p_code': code});
    return res as String;
  }

  /// Pelanggan: tekan "Sudah Diterima". Hasil: OK | NOT_ALLOWED | NOT_READY
  Future<String> confirmReceived(String orderId) async {
    final res = await _db.rpc('confirm_received', params: {'p_order_id': orderId});
    return res as String;
  }

  // ================= KLAIM KERUSAKAN =================

  Future<DamageClaim?> getClaimForOrder(String orderId) async {
    try {
      final row = await _db.from('damage_claims').select().eq('order_id', orderId).maybeSingle();
      return row == null ? null : DamageClaim.fromMap(row);
    } catch (e) {
      debugPrint('Error getClaimForOrder: $e');
      return null;
    }
  }

  /// Pelanggan: foto bukti diunggah dulu (wajib menurut policy), baru klaim dibuat
  Future<void> createClaim({
    required String orderId,
    required String shopId,
    required String description,
    required List<XFile> photos,
    String? category,
    List<String> affectedItems = const [],
    String? requestedResolution,
    int? requestedAmount,
  }) async {
    await uploadPhotos(orderId: orderId, stage: 'claim', files: photos);
    final base = {
      'order_id': orderId,
      'user_id': _db.auth.currentUser?.id,
      'shop_id': shopId,
      'description': description.trim(),
    };
    try {
      await _db.from('damage_claims').insert({
        ...base,
        'category': ?category,
        'affected_items': affectedItems,
        'requested_resolution': ?requestedResolution,
        'requested_amount': ?requestedAmount,
      });
    } on PostgrestException catch (e) {
      // Kolom lanjutan belum dibuat (SQL belum dijalankan): kirim klaim dasar
      if (e.code == '42703' || e.code == 'PGRST204') {
        await _db.from('damage_claims').insert(base);
        return;
      }
      rethrow;
    }
  }

  /// Batas ganti rugi (10x harga layanan item terdampak), dihitung server
  Future<int?> compensationCap(String orderId, List<String> items) async {
    try {
      final r = await _db.rpc('claim_compensation_cap', params: {'p_order_id': orderId, 'p_items': items});
      return r is num ? r.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Mitra: penyelesaian sudah dituntaskan. Hasil: OK | NOT_ALLOWED | NOT_APPROVED
  Future<String> resolveClaim(String claimId, String? note) async {
    final res = await _db.rpc('resolve_claim', params: {'p_claim_id': claimId, 'p_note': note});
    return res as String;
  }

  /// Pelanggan: naikkan ke Washora setelah 2x24 jam tanpa respons.
  /// Hasil: OK | NOT_ALLOWED | NOT_PENDING | TOO_EARLY
  Future<String> escalateClaim(String claimId) async {
    final res = await _db.rpc('escalate_claim', params: {'p_claim_id': claimId});
    return res as String;
  }

  Future<ClaimStats?> claimStats(String shopId) async {
    try {
      final r = await _db.rpc('claim_stats', params: {'p_shop_id': shopId});
      return r == null ? null : ClaimStats.fromJson(Map<String, dynamic>.from(r as Map));
    } catch (_) {
      return null;
    }
  }

  /// Stream realtime klaim di outlet mitra (terbaru di atas)
  Stream<List<DamageClaim>> getShopClaims(String shopId) {
    return _db
        .from('damage_claims')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(DamageClaim.fromMap).toList());
  }

  /// Mitra memutuskan klaim. Hasil: OK | NOT_ALLOWED | NOT_PENDING | INVALID
  Future<String> decideClaim({
    required String claimId,
    required bool approve,
    String? resolution,
    int? amount,
    String? note,
  }) async {
    final res = await _db.rpc('decide_claim', params: {
      'p_claim_id': claimId,
      'p_approve': approve,
      'p_resolution': resolution,
      'p_amount': amount,
      'p_note': note,
    });
    return res as String;
  }

  /// Pelanggan banding atas klaim yang ditolak. Hasil: OK | NOT_ALLOWED | NOT_REJECTED | INVALID
  Future<String> appealClaim(String claimId, String reason) async {
    final res = await _db.rpc('appeal_claim', params: {'p_claim_id': claimId, 'p_reason': reason});
    return res as String;
  }
}
