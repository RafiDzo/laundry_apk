import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/shop_model.dart';
import '../models/order_model.dart';

class SupabaseService {
  final SupabaseClient _db = Supabase.instance.client;

  // ================= USERS =================

  Future<void> createUser({
    required String uid,
    required String name,
    required String email,
    String role = 'customer',
  }) async {
    final user = UserModel(
      uid: uid,
      name: name,
      email: email,
      role: role,
      createdAt: DateTime.now(),
    );
    await _db.from('users').upsert({'id': uid, ...user.toMap()});
  }

  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final data = await _db.from('users').select().eq('id', uid).maybeSingle();
      if (data != null) {
        return UserModel.fromMap(data, uid);
      }
    } catch (e) {
      print('Error getUserProfile: $e');
    }
    return null;
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> updates) async {
    await _db.from('users').update(updates).eq('id', uid);
  }

  // ================= SHOPS & SERVICES =================

  Future<List<ShopModel>> getShops() async {
    try {
      final data = await _db.from('shops').select();
      return data.map<ShopModel>((row) => ShopModel.fromMap(row, row['id'])).toList();
    } catch (e) {
      print('Error getShops: $e');
      return [];
    }
  }

  Future<ShopModel?> getShopById(String id) async {
    try {
      final data = await _db.from('shops').select().eq('id', id).maybeSingle();
      if (data != null) {
        return ShopModel.fromMap(data, data['id']);
      }
    } catch (e) {
      print('Error getShopById: $e');
    }
    return null;
  }

  // ================= ORDERS =================

  Future<String> createOrder(OrderModel order) async {
    try {
      print('createOrder payload: ${order.toMap()}');
      final data = await _db
          .from('orders')
          .insert(order.toMap())
          .select('id')
          .single();
      return data['id'];
    } catch (e) {
      print('Error createOrder: $e');
      // Re-throw with the real error detail so UI can display it
      throw Exception(e.toString());
    }
  }

  /// Stream realtime pesanan user (menggunakan Supabase Realtime)
  Stream<List<OrderModel>> getUserOrders(String userId) {
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map<OrderModel>((row) => OrderModel.fromMap(row, row['id']))
            .toList());
  }
}
