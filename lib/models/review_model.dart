class ReviewModel {
  final String id;
  final String orderId;
  final String shopId;
  final String userId;
  final String userName;
  final int rating;
  final String comment;
  final List<String> tags;
  final String serviceSummary;
  final DateTime createdAt;

  const ReviewModel({
    required this.id,
    required this.orderId,
    required this.shopId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.serviceSummary,
    required this.createdAt,
  });

  factory ReviewModel.fromMap(Map<String, dynamic> d) {
    return ReviewModel(
      id: d['id']?.toString() ?? '',
      orderId: d['order_id']?.toString() ?? '',
      shopId: d['shop_id']?.toString() ?? '',
      userId: d['user_id']?.toString() ?? '',
      userName: (d['user_name'] as String?)?.trim().isNotEmpty == true
          ? d['user_name']
          : 'Pelanggan',
      rating: (d['rating'] as num?)?.toInt() ?? 0,
      comment: d['comment'] ?? '',
      tags: (d['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      serviceSummary: d['service_summary'] ?? '',
      createdAt: d['created_at'] != null
          ? DateTime.parse(d['created_at']).toLocal()
          : DateTime.now(),
    );
  }

  String get initial =>
      userName.isNotEmpty ? userName.characters.first.toUpperCase() : '?';

  /// "Baru saja", "3 jam lalu", "Kemarin", "5 hari lalu", "12 Okt 2026"
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'Kemarin';
    if (diff.inDays < 30) return '${diff.inDays} hari lalu';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${createdAt.day} ${months[createdAt.month - 1]} ${createdAt.year}';
  }
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
