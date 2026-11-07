import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shop_promo_model.dart';

class PromoService {
  final SupabaseClient _db = Supabase.instance.client;

  /// Stream realtime semua promo milik outlet tertentu (untuk dashboard mitra)
  Stream<List<ShopPromoModel>> streamShopPromos(String shopId) {
    try {
      return _db
          .from('shop_promos')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .map((list) => list.map((m) => ShopPromoModel.fromMap(m)).toList());
    } catch (e) {
      print('Error streamShopPromos: $e');
      return const Stream.empty();
    }
  }

  /// Ambil daftar promo sekali panggil (fallback jika realtime tidak aktif)
  Future<List<ShopPromoModel>> getShopPromos(String shopId) async {
    try {
      final res = await _db
          .from('shop_promos')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      return (res as List).map((m) => ShopPromoModel.fromMap(m)).toList();
    } catch (e) {
      print('Error getShopPromos: $e');
      return [];
    }
  }

  /// Buat promo baru untuk outlet
  Future<ShopPromoModel?> createPromo(ShopPromoModel promo) async {
    try {
      final res = await _db.from('shop_promos').insert(promo.toMap()).select().single();
      return ShopPromoModel.fromMap(res);
    } catch (e) {
      print('Error createPromo: $e');
      rethrow;
    }
  }

  /// Perbarui data promo
  Future<void> updatePromo(ShopPromoModel promo) async {
    try {
      final data = promo.toMap();
      data['updated_at'] = DateTime.now().toIso8601String();
      await _db.from('shop_promos').update(data).eq('id', promo.id);
    } catch (e) {
      print('Error updatePromo: $e');
      rethrow;
    }
  }

  /// Aktifkan / nonaktifkan promo secara instan
  Future<void> togglePromoStatus(String promoId, bool isActive) async {
    try {
      await _db.from('shop_promos').update({
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', promoId);
    } catch (e) {
      print('Error togglePromoStatus: $e');
      rethrow;
    }
  }

  /// Hapus promo
  Future<void> deletePromo(String promoId) async {
    try {
      await _db.from('shop_promos').delete().eq('id', promoId);
    } catch (e) {
      print('Error deletePromo: $e');
      rethrow;
    }
  }

  /// Ambil promo aktif untuk sisi pelanggan (checkout / detail outlet)
  Future<List<ShopPromoModel>> getActiveCustomerPromos(String shopId) async {
    try {
      final now = DateTime.now().toIso8601String();
      final res = await _db
          .from('shop_promos')
          .select()
          .eq('shop_id', shopId)
          .eq('is_active', true)
          .lte('start_at', now)
          .order('created_at', ascending: false);

      final list = (res as List).map((m) => ShopPromoModel.fromMap(m)).toList();
      // Filter expired di sisi client untuk tanggal end_at
      return list.where((p) => !p.isExpired && !p.isQuotaExhausted).toList();
    } catch (e) {
      print('Error getActiveCustomerPromos: $e');
      return [];
    }
  }
}
