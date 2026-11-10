import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_models.dart';

/// Kesalahan chat dengan pesan siap tampil
class ChatException implements Exception {
  final String message;
  ChatException(this.message);
  @override
  String toString() => message;
}

/// Chat internal mitra ↔ pelanggan di atas Supabase:
/// tabel chat_* + RPC (lihat supabase_chat.sql), Realtime untuk pesan baru,
/// status dibaca, dan indikator mengetik (broadcast).
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final SupabaseClient _db = Supabase.instance.client;
  static const String bucket = 'chat-images';
  static const int pageSize = 30;
  static const int maxImageBytes = 3 * 1024 * 1024;

  String? get uid => _db.auth.currentUser?.id;

  static String newClientId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  ChatException _wrap(Object e, String fallback) {
    if (e is ChatException) return e;
    if (e is PostgrestException) {
      // Tabel / fungsi belum dibuat
      if (e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42P01' || e.code == '42883') {
        return ChatException('Fitur chat belum aktif. Jalankan supabase_chat.sql di Supabase SQL Editor.');
      }
      if (e.code == '42501') {
        final m = e.message;
        return ChatException(m.contains('row-level security') || m.contains('permission')
            ? 'Akses ditolak. Percakapan mungkin diblokir, atau Anda tidak terlibat dalam pesanan ini.'
            : m);
      }
      if (e.code == '22023' || e.code == 'P0002') return ChatException(e.message);
      return ChatException('$fallback (${e.code ?? 'error'})');
    }
    if (e is StorageException) {
      if ((e.statusCode ?? '') == '413' || e.message.toLowerCase().contains('size')) {
        return ChatException('Ukuran foto melebihi 3 MB.');
      }
      if (e.message.toLowerCase().contains('bucket not found')) {
        return ChatException('Penyimpanan foto chat belum dibuat. Jalankan supabase_chat.sql.');
      }
      return ChatException('Foto gagal diunggah: ${e.message}');
    }
    return ChatException('$fallback. Periksa koneksi internet.');
  }

  // ======================= PERCAKAPAN =======================

  /// Buka atau buat percakapan untuk pesanan (validasi hak akses di server)
  Future<ChatConversation> openConversation(String orderId) async {
    try {
      final res = await _db.rpc('chat_open_conversation', params: {'p_order_id': orderId});
      return ChatConversation.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      throw _wrap(e, 'Percakapan gagal dibuka');
    }
  }

  Future<ChatConversation?> getConversation(String id) async {
    try {
      final row = await _db.from('chat_conversations').select().eq('id', id).maybeSingle();
      return row == null ? null : ChatConversation.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// Percakapan terbaru pelanggan dengan outlet tertentu (dari halaman profil outlet).
  /// Mengembalikan null jika pelanggan belum pernah memesan di outlet ini.
  Future<ChatConversation?> openLatestForShop(String shopId) async {
    final me = uid;
    if (me == null) throw ChatException('Silakan login terlebih dahulu.');
    try {
      final row = await _db
          .from('orders')
          .select('id')
          .eq('shop_id', shopId)
          .eq('user_id', me)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) return await openConversation(row['id'] as String);

      // Tidak ada pesanan di outlet ini: jelaskan penyebabnya, termasuk akun yang
      // sedang login (sesi browser bisa tertukar dengan akun mitra di tab lain).
      final email = _db.auth.currentUser?.email ?? 'tanpa email';
      final others = await _db.from('orders').select('id, shop_name').eq('user_id', me).limit(1);
      if (others.isEmpty) {
        throw ChatException(
          'Akun $email belum punya pesanan. Chat tersedia setelah Anda memesan di outlet ini. '
          'Jika Anda sudah memesan dengan akun lain, logout lalu login dengan akun tersebut.',
        );
      }
      throw ChatException(
        'Akun $email belum punya pesanan di outlet ini. '
        'Untuk pesanan di outlet lain, buka chat dari halaman Lacak Pesanan.',
      );
    } catch (e) {
      throw _wrap(e, 'Percakapan gagal dibuka');
    }
  }

  /// Realtime daftar percakapan milik user (sebagai mitra atau pelanggan), terbaru di atas
  Stream<List<ChatConversation>> watchConversations({required bool asOwner}) {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _db
        .from('chat_conversations')
        .stream(primaryKey: ['id'])
        .eq(asOwner ? 'owner_id' : 'user_id', me)
        .map((rows) {
      final list = rows.map(ChatConversation.fromMap).toList()
        ..sort((a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
      return list;
    });
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _db.rpc('chat_mark_read', params: {'p_conversation_id': conversationId});
    } catch (_) {
      // Tidak fatal: akan dicoba lagi saat pesan berikutnya masuk
    }
  }

  Future<void> markDelivered() async {
    try {
      await _db.rpc('chat_mark_delivered');
    } catch (_) {}
  }

  Future<ChatConversation> setBlocked(String conversationId, bool block) async {
    try {
      final res = await _db.rpc('chat_set_block', params: {'p_conversation_id': conversationId, 'p_block': block});
      return ChatConversation.fromMap(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      throw _wrap(e, block ? 'Gagal memblokir' : 'Gagal membuka blokir');
    }
  }

  Future<void> report({required String conversationId, String? messageId, required String reason}) async {
    try {
      await _db.from('chat_reports').insert({
        'conversation_id': conversationId,
        'message_id': ?messageId,
        'reason': reason,
      });
    } catch (e) {
      throw _wrap(e, 'Laporan gagal dikirim');
    }
  }

  // ===================== HAPUS PESAN / CHAT =====================

  /// [forEveryone] = tarik pesan (pengirim, ≤ 24 jam); selain itu sembunyikan untuk diri sendiri.
  Future<void> deleteMessage(ChatMessage m, {required bool forEveryone}) async {
    try {
      // Foto yang ditarik ikut dihapus dari penyimpanan
      if (forEveryone && m.type == 'image' && m.imagePath != null && m.imagePath!.contains('/')) {
        try {
          await _db.storage.from(bucket).remove([m.imagePath!]);
        } catch (_) {}
        _urlCache.remove(m.imagePath);
      }
      await _db.rpc('chat_delete_message', params: {'p_message_id': m.id, 'p_for_everyone': forEveryone});
    } catch (e) {
      throw _wrap(e, 'Pesan gagal dihapus');
    }
  }

  /// Hapus percakapan dari kotak masuk (hanya untuk akun sendiri)
  Future<void> clearConversation(String conversationId) async {
    try {
      await _db.rpc('chat_clear_conversation', params: {'p_conversation_id': conversationId});
    } catch (e) {
      throw _wrap(e, 'Percakapan gagal dihapus');
    }
  }

  /// Hapus semua percakapan yang tidak aktif lebih dari [days] hari. Mengembalikan jumlahnya.
  Future<int> clearOldConversations(int days) async {
    try {
      final n = await _db.rpc('chat_clear_old', params: {'p_days': days});
      return n is num ? n.toInt() : 0;
    } catch (e) {
      throw _wrap(e, 'Percakapan lama gagal dibersihkan');
    }
  }

  // ========================= PESAN =========================

  /// Satu halaman pesan, TERBARU lebih dulu. [before] = cursor (created_at pesan tertua yang sudah ada).
  Future<List<ChatMessage>> fetchMessages(String conversationId, {DateTime? before, int limit = pageSize}) async {
    try {
      var q = _db.from('chat_messages').select().eq('conversation_id', conversationId);
      if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
      final rows = await q.order('created_at', ascending: false).limit(limit);
      return rows.map<ChatMessage>(ChatMessage.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Pesan gagal dimuat');
    }
  }

  Future<ChatMessage> _insert(Map<String, dynamic> row) async {
    try {
      final res = await _db.from('chat_messages').insert(row).select().single();
      return ChatMessage.fromMap(res);
    } on PostgrestException catch (e) {
      // 23505: pesan dengan client_id ini ternyata sudah tersimpan (kirim ulang setelah timeout)
      if (e.code == '23505' && row['client_id'] != null) {
        final existing = await _db
            .from('chat_messages')
            .select()
            .eq('conversation_id', row['conversation_id'])
            .eq('client_id', row['client_id'])
            .maybeSingle();
        if (existing != null) return ChatMessage.fromMap(existing);
      }
      throw _wrap(e, 'Pesan gagal dikirim');
    } catch (e) {
      throw _wrap(e, 'Pesan gagal dikirim');
    }
  }

  Future<ChatMessage> sendText(String conversationId, String body, String clientId) {
    final text = body.trim();
    if (text.isEmpty) throw ChatException('Pesan kosong.');
    if (text.length > 2000) throw ChatException('Pesan maksimal 2000 karakter.');
    return _insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'text',
      'body': text,
      'client_id': clientId,
    });
  }

  /// Unggah foto (sudah dikompres oleh image_picker) lalu kirim sebagai pesan gambar
  Future<ChatMessage> sendImage(
    String conversationId,
    Uint8List bytes, {
    required String clientId,
    String caption = '',
    String mime = 'image/jpeg',
  }) async {
    if (bytes.lengthInBytes > maxImageBytes) {
      throw ChatException('Ukuran foto melebihi 3 MB setelah dikompres. Pilih foto lain.');
    }
    final ext = switch (mime) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$conversationId/${uid}_$clientId.$ext';
    try {
      await _db.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );
    } catch (e) {
      throw _wrap(e, 'Foto gagal diunggah');
    }
    return _insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'image',
      'body': caption.trim(),
      'image_path': path,
      'client_id': clientId,
    });
  }

  // URL gambar privat (signed URL 1 jam), di-cache selama 50 menit
  final Map<String, (String, DateTime)> _urlCache = {};

  Future<String?> imageUrl(String path) async {
    final cached = _urlCache[path];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;
    try {
      final url = await _db.storage.from(bucket).createSignedUrl(path, 3600);
      _urlCache[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
      return url;
    } catch (_) {
      return null;
    }
  }

  // ======================== REALTIME ========================

  /// Berlangganan pesan baru, perubahan status (dibaca), dan "sedang mengetik".
  /// [onStatus] menerima true saat tersambung, false saat terputus.
  RealtimeChannel subscribeRoom(
    String conversationId, {
    required void Function(ChatMessage) onUpsert,
    required void Function(String userId, bool typing) onTyping,
    required void Function(bool connected) onStatus,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    void handle(PostgresChangePayload p) {
      if (p.newRecord.isEmpty) return;
      try {
        onUpsert(ChatMessage.fromMap(p.newRecord));
      } catch (_) {}
    }

    final channel = _db
        .channel('chat-room:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: filter,
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: filter,
          callback: handle,
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final from = payload['user_id'] as String?;
            if (from == null || from == uid) return;
            onTyping(from, payload['typing'] == true);
          },
        );
    channel.subscribe((status, _) {
      onStatus(status == RealtimeSubscribeStatus.subscribed);
    });
    return channel;
  }

  Future<void> sendTyping(RealtimeChannel channel, bool typing) async {
    try {
      await channel.sendBroadcastMessage(event: 'typing', payload: {'user_id': uid, 'typing': typing});
    } catch (_) {}
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _db.removeChannel(channel);
    } catch (_) {}
  }

  // ==================== TEMPLATE BALASAN ====================

  static const List<String> defaultQuickReplies = [
    'Halo, terima kasih sudah menghubungi kami.',
    'Cucian Anda sedang diproses.',
    'Cucian Anda sudah selesai dan siap diambil.',
    'Mohon konfirmasi alamat penjemputan/pengantaran.',
    'Kurir kami sedang dalam perjalanan.',
  ];

  /// Template mitra; jika belum punya sama sekali, isi dengan template awal
  Future<List<QuickReply>> fetchQuickReplies({bool seedIfEmpty = true}) async {
    try {
      final rows = await _db.from('chat_quick_replies').select().order('sort_order').order('created_at');
      if (rows.isEmpty && seedIfEmpty) {
        await _db.from('chat_quick_replies').insert([
          for (var i = 0; i < defaultQuickReplies.length; i++) {'body': defaultQuickReplies[i], 'sort_order': i},
        ]);
        return fetchQuickReplies(seedIfEmpty: false);
      }
      return rows.map<QuickReply>(QuickReply.fromMap).toList();
    } catch (e) {
      throw _wrap(e, 'Template gagal dimuat');
    }
  }

  Future<void> saveQuickReply({String? id, required String body, int sortOrder = 0}) async {
    final text = body.trim();
    if (text.isEmpty) throw ChatException('Template tidak boleh kosong.');
    if (text.length > 300) throw ChatException('Template maksimal 300 karakter.');
    try {
      if (id == null) {
        await _db.from('chat_quick_replies').insert({'body': text, 'sort_order': sortOrder});
      } else {
        await _db.from('chat_quick_replies').update({'body': text}).eq('id', id);
      }
    } catch (e) {
      throw _wrap(e, 'Template gagal disimpan');
    }
  }

  Future<void> deleteQuickReply(String id) async {
    try {
      await _db.from('chat_quick_replies').delete().eq('id', id);
    } catch (e) {
      throw _wrap(e, 'Template gagal dihapus');
    }
  }
}
