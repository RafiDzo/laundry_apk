import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/chat_room_screen.dart';
import '../screens/membership_screen.dart';
import '../screens/order_history_screen.dart' show openOrderTracking;
import 'notification_service.dart';
import 'supabase_service.dart';

/// Arahkan pengguna ke halaman yang sesuai saat notifikasi push diketuk.
/// Data dikirim Edge Function send-push: { type, order_id, notification_id }.
class PushRouter {
  PushRouter._();

  static GlobalKey<NavigatorState>? _navKey;
  static Map<String, dynamic>? _pending;

  static void attach(GlobalKey<NavigatorState> key) => _navKey = key;

  /// Dipanggil NotificationService. Jika aplikasi baru dibuka dari keadaan
  /// tertutup, navigator belum siap → dicoba ulang sebentar lagi.
  static Future<void> handle(Map<String, dynamic> data, {int attempt = 0}) async {
    final ctx = _navKey?.currentContext;
    if (ctx == null || Supabase.instance.client.auth.currentUser == null) {
      _pending = data;
      if (attempt < 10) {
        await Future.delayed(const Duration(milliseconds: 800));
        return handle(data, attempt: attempt + 1);
      }
      return;
    }
    _pending = null;
    final type = '${data['type'] ?? ''}';
    final orderId = '${data['order_id'] ?? ''}';

    if (type == 'chat' || type == 'owner_chat') {
      if (orderId.isNotEmpty) await openChatForOrder(ctx, orderId);
      return;
    }
    if (type.startsWith('membership_')) {
      await Navigator.push(ctx, MaterialPageRoute(builder: (_) => const MembershipScreen()));
      return;
    }
    // Notifikasi mitra lain (pesanan baru, klaim, ulasan, saldo) → dashboard sudah jadi
    // halaman utama mitra; cukup membuka aplikasi.
    if (type.startsWith('owner_') || type.startsWith('wallet_')) return;

    // Pelanggan: status pesanan, klaim, poin, balasan ulasan → halaman lacak pesanan
    if (orderId.isNotEmpty) {
      final order = await SupabaseService().getOrderById(orderId);
      final c = _navKey?.currentContext;
      if (order != null && c != null && c.mounted) await openOrderTracking(c, order);
    }
  }

  /// Daftarkan token FCM setiap kali sesi aktif (login email, Google, atau
  /// sesi tersimpan saat aplikasi dibuka ulang).
  static void listenAuth() {
    Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      if (state.event != AuthChangeEvent.signedIn && state.event != AuthChangeEvent.initialSession) return;
      final user = state.session?.user;
      if (user == null) return;
      try {
        final profile = await SupabaseService().getUserProfile(user.id);
        await NotificationService().registerUserToken(profile?.role ?? 'customer');
      } catch (_) {}
      final p = _pending;
      if (p != null) handle(p);
    });
  }
}
