import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/shop_model.dart';
import '../models/order_model.dart';
import '../models/notification_model.dart';

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
    try {
      await _db.from('users').update(updates).eq('id', uid);
    } catch (e) {
      print('Error updateUserProfile: $e');
    }
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

  /// Toko milik owner yang sedang login (null jika akun belum dihubungkan ke toko)
  Future<ShopModel?> getMyShop() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final data = await _db
          .from('shops')
          .select()
          .eq('owner_id', uid)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        return ShopModel.fromMap(data, data['id']);
      }
    } catch (e) {
      print('Error getMyShop: $e');
    }
    return null;
  }

  /// Daftarkan outlet baru milik owner yang sedang login (form "Daftarkan Outlet")
  Future<ShopModel> createMyShop({
    required String name,
    required String address,
    required String openHours,
    required int pricePerKg,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Sesi login berakhir. Silakan login ulang.');

    final data = await _db
        .from('shops')
        .insert({
          'name': name,
          'address': address,
          'open_hours': openHours,
          'price_per_kg': pricePerKg,
          'queue_text': 'ANTRIAN: 0 (LANCAR)',
          'owner_id': uid,
          // Layanan awal agar outlet langsung bisa dipesan pelanggan
          'services': [
            {
              'id': 's1',
              'name': 'Cuci Kiloan',
              'description': 'Cuci, kering & lipat reguler',
              'price': pricePerKg,
              'unit': '/ kg',
              'iconName': 'local_laundry_service',
            },
          ],
        })
        .select()
        .single();
    return ShopModel.fromMap(data, data['id']);
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

  /// Ambil sekali semua pesanan milik user (untuk tombol Lacak)
  Future<List<OrderModel>> fetchUserOrders(String userId) async {
    try {
      final data = await _db
          .from('orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return data
          .map<OrderModel>((row) => OrderModel.fromMap(row, row['id']))
          .toList();
    } catch (e) {
      print('Error fetchUserOrders: $e');
      return [];
    }
  }

  /// Stream realtime satu pesanan (halaman pelacakan pelanggan).
  /// Menghasilkan null jika pesanan tidak ditemukan / tidak boleh diakses.
  Stream<OrderModel?> watchOrder(String orderId) {
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? null : OrderModel.fromMap(rows.first, rows.first['id']));
  }

  /// Stream realtime semua pesanan di satu toko (untuk dashboard Mitra / Owner)
  Stream<List<OrderModel>> getShopOrders(String shopId) {
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map<OrderModel>((row) => OrderModel.fromMap(row, row['id']))
            .toList());
  }

  /// Update status pesanan (misal: 'washing', 'drying', 'done', 'delivered').
  /// Mengembalikan false jika tidak ada baris yang berubah — misalnya karena
  /// diblokir RLS, yang oleh Supabase tidak dilaporkan sebagai error.
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final updated = await _db
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId)
          .select('id');
      if (updated.isEmpty) {
        print('Error updateOrderStatus: 0 baris berubah '
            '(login sebagai ${_db.auth.currentUser?.email ?? 'TIDAK ADA SESI'})');
      }
      return updated.isNotEmpty;
    } catch (e) {
      print('Error updateOrderStatus: $e');
      return false;
    }
  }

  /// Hapus pesanan permanen (misalnya yang berstatus 'cancelled')
  Future<bool> deleteOrder(String orderId) async {
    try {
      final res = await _db
          .from('orders')
          .delete()
          .eq('id', orderId)
          .select('id');
      if (res.isEmpty) {
        // Supabase tidak melempar error saat RLS menolak DELETE — hanya 0 baris terhapus
        print('Error deleteOrder: 0 baris terhapus (kemungkinan policy DELETE belum ada)');
      }
      return res.isNotEmpty;
    } catch (e) {
      print('Error deleteOrder: $e');
      return false;
    }
  }

  /// Hapus semua pesanan yang dibatalkan untuk outlet tertentu
  Future<int> deleteCancelledOrders(String shopId) async {
    try {
      final res = await _db
          .from('orders')
          .delete()
          .eq('shop_id', shopId)
          .eq('status', 'cancelled')
          .select('id');
      if (res.isEmpty) {
        print('Error deleteCancelledOrders: 0 baris terhapus (tidak ada pesanan batal, atau policy DELETE belum ada)');
      }
      return res.length;
    } catch (e) {
      print('Error deleteCancelledOrders: $e');
      return 0;
    }
  }

  /// Ambil satu pesanan (mis. saat notifikasi diketuk)
  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      final data = await _db.from('orders').select().eq('id', orderId).maybeSingle();
      if (data != null) return OrderModel.fromMap(data, data['id']);
    } catch (e) {
      print('Error getOrderById: $e');
    }
    return null;
  }

  // ================= NOTIFICATIONS =================

  /// Stream realtime notifikasi milik user (terbaru di atas).
  /// Notifikasi dibuat oleh trigger database saat status pesanan berubah.
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) => rows.map(NotificationModel.fromMap).toList());
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _db.from('notifications').update({'is_read': true}).eq('id', notificationId);
    } catch (e) {
      print('Error markNotificationRead: $e');
    }
  }

  Future<void> markAllNotificationsRead(String userId) async {
    try {
      await _db
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      print('Error markAllNotificationsRead: $e');
    }
  }

  // ================= PETTY CASH =================

  Future<List<Map<String, dynamic>>> getPettyCash(String shopId) async {
    try {
      final data = await _db
          .from('petty_cash')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      print('Error getPettyCash: $e');
      return [];
    }
  }

  Future<void> addPettyCash({
    required String shopId,
    required String title,
    required String type,
    required int amount,
  }) async {
    await _db.from('petty_cash').insert({
      'shop_id': shopId,
      'title': title,
      'type': type,
      'amount': amount,
    });
  }
}
