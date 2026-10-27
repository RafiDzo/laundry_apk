class NotificationModel {
  final String id;
  final String userId;
  final String? orderId;
  final String? status; // status pesanan yang memicu notifikasi
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    this.orderId,
    this.status,
    required this.title,
    required this.body,
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> data) {
    return NotificationModel(
      id: data['id'] ?? '',
      userId: data['user_id'] ?? '',
      orderId: data['order_id'],
      status: data['status'],
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      isRead: data['is_read'] ?? false,
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at']).toLocal()
          : DateTime.now(),
    );
  }
}
