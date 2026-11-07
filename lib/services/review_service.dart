import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import '../models/review_model.dart';

class ReviewException implements Exception {
  final String message;
  ReviewException(this.message);
  @override
  String toString() => message;
}

enum ReviewSort { newest, highest, lowest }

/// Rating & ulasan pelanggan untuk outlet (tabel reviews + supabase_ulasan_lanjutan.sql).
/// Validasi hak akses (pesanan milik pelanggan & sudah diterima, satu ulasan per
/// pesanan, batas edit 7 hari) dilakukan RLS & trigger di database.
class ReviewService {
  final SupabaseClient _db = Supabase.instance.client;
  static const int pageSize = 10;
  static const int maxPhotos = 3;
  static const int maxPhotoBytes = 2 * 1024 * 1024;
  static const String bucket = 'review-photos';

  ReviewException _wrap(Object e, String fallback) {
    if (e is ReviewException) return e;
    if (e is PostgrestException) {
      final m = e.message;
      if (e.code == '42703' || e.code == 'PGRST204' || e.code == 'PGRST202') {
        return ReviewException('Fitur ulasan lanjutan belum aktif. Jalankan supabase_ulasan_lanjutan.sql di Supabase.');
      }
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return ReviewException('Fitur ulasan belum aktif. Jalankan supabase_ulasan_lokasi.sql di Supabase.');
      }
      if (e.code == '22023') return ReviewException(m);
      // GRANT tabel belum diberikan (bukan masalah akun/RLS)
      if (e.code == '42501' && m.contains('permission denied for table')) {
        return ReviewException('Izin database untuk ulasan belum diberikan. Jalankan supabase_ulasan_lanjutan.sql di Supabase SQL Editor.');
      }
      if (e.code == '23505') return ReviewException('Kamu sudah melaporkan ulasan ini.');
      if (e.code == '42501' || m.contains('row-level security')) {
        return ReviewException(m.contains('row-level security')
            ? 'Ulasan hanya bisa dikirim untuk pesananmu yang sudah diterima.'
            : m);
      }
      return ReviewException('$fallback (${e.code ?? 'error'}).');
    }
    if (e is StorageException) {
      final m = e.message.toLowerCase();
      if (m.contains('bucket') && m.contains('not found')) {
        return ReviewException('Penyimpanan foto ulasan belum dibuat. Jalankan supabase_ulasan_lanjutan.sql.');
      }
      if (m.contains('size') || e.statusCode == '413') return ReviewException('Ukuran foto melebihi 2 MB.');
      return ReviewException('Foto gagal diunggah: ${e.message}');
    }
    return ReviewException('$fallback. Periksa koneksi internet lalu coba lagi.');
  }

  // ======================= BACA =======================

  Future<ReviewSummary> fetchSummary(String shopId) async {
    try {
      final res = await _db.rpc('review_summary', params: {'p_shop_id': shopId});
      return ReviewSummary.fromJson(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      // Fungsi ringkasan belum dipasang: hitung dari daftar ulasan
      if (e.code == 'PGRST202' || e.code == '42883') {
        final rows = await _db.from('reviews').select().eq('shop_id', shopId).limit(1000);
        return ReviewSummary.fromReviews(rows.map<ReviewModel>(ReviewModel.fromMap).toList());
      }
      throw _wrap(e, 'Ringkasan rating gagal dimuat');
    } catch (e) {
      throw _wrap(e, 'Ringkasan rating gagal dimuat');
    }
  }

  /// Satu halaman ulasan outlet dengan urutan & filter
  Future<List<ReviewModel>> fetchPage(
    String shopId, {
    required int page,
    ReviewSort sort = ReviewSort.newest,
    bool withPhotosOnly = false,
    bool unrepliedOnly = false,
  }) async {
    try {
      var q = _db.from('reviews').select().eq('shop_id', shopId);
      if (withPhotosOnly) q = q.neq('photo_urls', '{}');
      if (unrepliedOnly) q = q.isFilter('reply', null);
      final ordered = switch (sort) {
        ReviewSort.newest => q.order('created_at', ascending: false),
        ReviewSort.highest => q.order('rating', ascending: false).order('created_at', ascending: false),
        ReviewSort.lowest => q.order('rating', ascending: true).order('created_at', ascending: false),
      };
      final start = page * pageSize;
      final rows = await ordered.range(start, start + pageSize - 1);
      return rows.map<ReviewModel>(ReviewModel.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Ulasan gagal dimuat');
    }
  }

  Future<ReviewModel?> fetchMine(String orderId) async {
    try {
      final row = await _db.from('reviews').select().eq('order_id', orderId).maybeSingle();
      return row == null ? null : ReviewModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ======================= TULIS =======================

  /// Kirim ulasan baru atau ubah ulasan (dalam 7 hari). [keptPhotoUrls] = foto lama
  /// yang dipertahankan, [newPhotos] = foto baru (sudah dikompres) yang diunggah.
  Future<ReviewModel> submit({
    required OrderModel order,
    required int rating,
    required String comment,
    required List<String> tags,
    required Map<ReviewAspect, int> aspects,
    required bool anonymous,
    List<String> keptPhotoUrls = const [],
    List<(Uint8List bytes, String mime)> newPhotos = const [],
  }) async {
    if (rating < 1 || rating > 5) throw ReviewException('Pilih jumlah bintang dulu ya.');
    final text = comment.trim();
    if (text.length > 500) throw ReviewException('Ulasan maksimal 500 karakter.');
    if (keptPhotoUrls.length + newPhotos.length > maxPhotos) {
      throw ReviewException('Maksimal $maxPhotos foto.');
    }
    final user = _db.auth.currentUser;
    if (user == null) throw ReviewException('Sesi login berakhir. Silakan login ulang.');

    final urls = [...keptPhotoUrls];
    try {
      for (var i = 0; i < newPhotos.length; i++) {
        final (bytes, mime) = newPhotos[i];
        if (bytes.lengthInBytes > maxPhotoBytes) throw ReviewException('Ukuran foto ke-${i + 1} melebihi 2 MB.');
        final ext = switch (mime) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
        final path = '${order.id}/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await _db.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
        urls.add(_db.storage.from(bucket).getPublicUrl(path));
      }

      final items = order.items;
      final summary = items.isEmpty
          ? 'Layanan laundry'
          : (items.length > 1 ? '${items.first.name} +${items.length - 1}' : items.first.name);
      final row = await _db
          .from('reviews')
          .upsert({
            'order_id': order.id,
            'shop_id': order.shopId,
            'user_id': user.id,
            'user_name': '', // diisi server dari profil / "Anonim"
            'rating': rating,
            'comment': text,
            'tags': tags,
            'service_summary': summary,
            'is_anonymous': anonymous,
            'photo_urls': urls,
            for (final a in ReviewAspect.values) a.column: aspects[a],
          }, onConflict: 'order_id')
          .select()
          .single();
      return ReviewModel.fromMap(row);
    } catch (e) {
      throw _wrap(e, 'Ulasan gagal dikirim');
    }
  }

  /// Balasan mitra (sekali per ulasan)
  Future<ReviewModel> reply(String reviewId, String text) async {
    final t = text.trim();
    if (t.isEmpty) throw ReviewException('Tulis balasan dulu.');
    if (t.length > 500) throw ReviewException('Balasan maksimal 500 karakter.');
    try {
      final res = await _db.rpc('review_reply', params: {'p_review_id': reviewId, 'p_reply': t});
      return ReviewModel.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      throw _wrap(e, 'Balasan gagal dikirim');
    }
  }

  /// Laporkan ulasan (mitra) ke antrean tinjauan admin
  Future<void> report(String reviewId, String reason) async {
    try {
      await _db.from('review_reports').insert({'review_id': reviewId, 'reason': reason.trim()});
    } catch (e) {
      throw _wrap(e, 'Laporan gagal dikirim');
    }
  }
}
