class ReviewModel {
  final String id;
  final String orderId;
  final String shopId;
  final String userId;
  final String userName; // "Anonim" jika dikirim anonim (diatur server)
  final int rating;
  final String comment;
  final List<String> tags;
  final String serviceSummary;
  final DateTime createdAt;

  // Lanjutan (supabase_ulasan_lanjutan.sql)
  final bool isAnonymous;
  final Map<String, int> aspects; // kunci: ReviewAspect.key
  final List<String> photoUrls;
  final String? reply;
  final DateTime? replyAt;
  final DateTime? updatedAt;

  /// Ulasan bisa diubah pelanggan selama 7 hari sejak dikirim
  static const Duration editWindow = Duration(days: 7);

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
    this.isAnonymous = false,
    this.aspects = const {},
    this.photoUrls = const [],
    this.reply,
    this.replyAt,
    this.updatedAt,
  });

  factory ReviewModel.fromMap(Map<String, dynamic> d) {
    DateTime? date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    final aspects = <String, int>{};
    for (final a in ReviewAspect.values) {
      final v = (d[a.column] as num?)?.toInt();
      if (v != null && v >= 1 && v <= 5) aspects[a.key] = v;
    }
    final anonymous = d['is_anonymous'] == true;
    return ReviewModel(
      id: d['id']?.toString() ?? '',
      orderId: d['order_id']?.toString() ?? '',
      shopId: d['shop_id']?.toString() ?? '',
      userId: d['user_id']?.toString() ?? '',
      userName: anonymous
          ? 'Anonim'
          : ((d['user_name'] as String?)?.trim().isNotEmpty == true ? d['user_name'] : 'Pelanggan'),
      rating: (d['rating'] as num?)?.toInt() ?? 0,
      comment: d['comment'] ?? '',
      tags: (d['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      serviceSummary: d['service_summary'] ?? '',
      createdAt: date(d['created_at']) ?? DateTime.now(),
      isAnonymous: anonymous,
      aspects: aspects,
      photoUrls: (d['photo_urls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      reply: (d['reply'] as String?)?.trim().isNotEmpty == true ? d['reply'] as String : null,
      replyAt: date(d['reply_at']),
      updatedAt: date(d['updated_at']),
    );
  }

  bool get hasReply => reply != null;
  bool get hasPhotos => photoUrls.isNotEmpty;
  DateTime get editableUntil => createdAt.add(editWindow);
  bool get canEdit => DateTime.now().isBefore(editableUntil);
  bool get wasEdited => updatedAt != null && updatedAt!.difference(createdAt).inMinutes >= 1;

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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${createdAt.day.toString().padLeft(2, '0')} ${months[createdAt.month - 1]} ${createdAt.year}';
  }
}

/// Aspek penilaian opsional
enum ReviewAspect {
  cleanliness('cleanliness', 'aspect_cleanliness', 'Kebersihan'),
  timeliness('timeliness', 'aspect_timeliness', 'Ketepatan waktu'),
  friendliness('friendliness', 'aspect_friendliness', 'Keramahan'),
  price('price', 'aspect_price', 'Kesesuaian harga');

  final String key;
  final String column;
  final String label;
  const ReviewAspect(this.key, this.column, this.label);

  static ReviewAspect? byKey(String k) => values.where((a) => a.key == k).firstOrNull;
}

/// Ringkasan rating satu outlet (RPC review_summary)
class ReviewSummary {
  final double average;
  final int count;
  final Map<int, int> distribution; // bintang → jumlah
  final int withPhotos;
  final int unreplied;
  final Map<String, double> aspects; // ReviewAspect.key → rata-rata
  final List<(DateTime month, double average, int count)> monthly;

  const ReviewSummary({
    required this.average,
    required this.count,
    required this.distribution,
    required this.withPhotos,
    required this.unreplied,
    required this.aspects,
    required this.monthly,
  });

  static const empty = ReviewSummary(
    average: 0,
    count: 0,
    distribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
    withPhotos: 0,
    unreplied: 0,
    aspects: {},
    monthly: [],
  );

  factory ReviewSummary.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final dist = Map<String, dynamic>.from(j['distribution'] as Map? ?? {});
    final asp = Map<String, dynamic>.from(j['aspects'] as Map? ?? {});
    return ReviewSummary(
      average: d(j['average']),
      count: i(j['count']),
      distribution: {for (var s = 1; s <= 5; s++) s: i(dist['$s'])},
      withPhotos: i(j['with_photos']),
      unreplied: i(j['unreplied']),
      aspects: {
        for (final e in asp.entries)
          if (e.value != null) e.key: d(e.value),
      },
      monthly: [
        for (final m in (j['monthly'] as List? ?? const []))
          (DateTime.parse('${m['month']}-01'), d(m['average']), i(m['count'])),
      ],
    );
  }

  /// Hitung dari daftar ulasan (cadangan jika RPC belum dipasang)
  factory ReviewSummary.fromReviews(List<ReviewModel> list) {
    if (list.isEmpty) return empty;
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final aspectSum = <String, List<int>>{};
    for (final r in list) {
      dist[r.rating] = (dist[r.rating] ?? 0) + 1;
      for (final a in r.aspects.entries) {
        (aspectSum[a.key] ??= []).add(a.value);
      }
    }
    final avg = list.fold<int>(0, (s, r) => s + r.rating) / list.length;
    return ReviewSummary(
      average: (avg * 10).round() / 10,
      count: list.length,
      distribution: dist,
      withPhotos: list.where((r) => r.hasPhotos).length,
      unreplied: list.where((r) => !r.hasReply).length,
      aspects: {
        for (final e in aspectSum.entries)
          e.key: ((e.value.reduce((a, b) => a + b) / e.value.length) * 10).round() / 10,
      },
      monthly: const [],
    );
  }
}

/// "4,8" — satu angka desimal dengan koma
String formatRating(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
