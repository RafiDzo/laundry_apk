/// Percakapan 1-lawan-1 yang terikat pada satu pesanan (tabel chat_conversations)
class ChatConversation {
  final String id;
  final String orderId;
  final String shopId;
  final String userId; // pelanggan
  final String ownerId; // mitra
  final String customerName;
  final String shopName;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final String? lastSenderId;
  final int customerUnread;
  final int ownerUnread;
  final String? blockedBy;
  final DateTime createdAt;

  const ChatConversation({
    required this.id,
    required this.orderId,
    required this.shopId,
    required this.userId,
    required this.ownerId,
    required this.customerName,
    required this.shopName,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.lastSenderId,
    required this.customerUnread,
    required this.ownerUnread,
    required this.blockedBy,
    required this.createdAt,
  });

  factory ChatConversation.fromMap(Map<String, dynamic> m) => ChatConversation(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        shopId: '${m['shop_id'] ?? ''}',
        userId: m['user_id'] as String,
        ownerId: m['owner_id'] as String,
        customerName: (m['customer_name'] as String?) ?? '',
        shopName: (m['shop_name'] as String?) ?? '',
        lastMessageAt: m['last_message_at'] == null ? null : DateTime.parse(m['last_message_at']).toLocal(),
        lastMessagePreview: (m['last_message_preview'] as String?) ?? '',
        lastSenderId: m['last_sender_id'] as String?,
        customerUnread: (m['customer_unread'] as num?)?.toInt() ?? 0,
        ownerUnread: (m['owner_unread'] as num?)?.toInt() ?? 0,
        blockedBy: m['blocked_by'] as String?,
        createdAt: m['created_at'] == null ? DateTime.now() : DateTime.parse(m['created_at']).toLocal(),
      );

  bool isOwner(String uid) => uid == ownerId;
  int unreadFor(String uid) => uid == ownerId ? ownerUnread : customerUnread;
  bool get isBlocked => blockedBy != null;

  /// Nama lawan bicara dari sudut pandang [uid]
  String partnerName(String uid) {
    if (uid == ownerId) return customerName.trim().isEmpty ? 'Pelanggan' : customerName.trim();
    return shopName.trim().isEmpty ? 'Outlet laundry' : shopName.trim();
  }

  String get orderCode => orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
}

/// Status pengiriman dari sudut pandang pengirim
enum MessageState { sending, failed, sent, delivered, read }

class ChatMessage {
  final String id; // id server; sementara = clientId saat belum terkirim
  final String conversationId;
  final String senderId;
  final String type; // 'text' | 'image'
  final String body;
  final String? imagePath;
  final String? clientId;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  /// Hanya untuk pesan lokal (optimistic): sedang dikirim / gagal
  final bool pending;
  final bool failed;

  /// Gambar lokal yang belum terunggah (untuk pratinjau & kirim ulang)
  final List<int>? localBytes;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.body,
    required this.createdAt,
    this.imagePath,
    this.clientId,
    this.deliveredAt,
    this.readAt,
    this.pending = false,
    this.failed = false,
    this.localBytes,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String,
        type: (m['type'] as String?) ?? 'text',
        body: (m['body'] as String?) ?? '',
        imagePath: m['image_path'] as String?,
        clientId: m['client_id'] as String?,
        createdAt: DateTime.parse(m['created_at']).toLocal(),
        deliveredAt: m['delivered_at'] == null ? null : DateTime.parse(m['delivered_at']).toLocal(),
        readAt: m['read_at'] == null ? null : DateTime.parse(m['read_at']).toLocal(),
      );

  bool get isImage => type == 'image';

  MessageState get state {
    if (failed) return MessageState.failed;
    if (pending) return MessageState.sending;
    if (readAt != null) return MessageState.read;
    if (deliveredAt != null) return MessageState.delivered;
    return MessageState.sent;
  }

  ChatMessage copyWith({bool? pending, bool? failed}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        body: body,
        createdAt: createdAt,
        imagePath: imagePath,
        clientId: clientId,
        deliveredAt: deliveredAt,
        readAt: readAt,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        localBytes: localBytes,
      );
}

class QuickReply {
  final String id;
  final String body;
  final int sortOrder;
  const QuickReply({required this.id, required this.body, required this.sortOrder});

  factory QuickReply.fromMap(Map<String, dynamic> m) => QuickReply(
        id: m['id'] as String,
        body: (m['body'] as String?) ?? '',
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}
