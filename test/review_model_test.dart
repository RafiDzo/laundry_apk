import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/review_model.dart';

void main() {
  Map<String, dynamic> row({int rating = 5, String? created, bool anon = false, Map<String, dynamic> extra = const {}}) => {
        'id': 'r1',
        'order_id': 'o1',
        'shop_id': 's1',
        'user_id': 'u1',
        'user_name': 'Budi',
        'rating': rating,
        'comment': 'Wangi',
        'tags': ['Wangi'],
        'created_at': created ?? DateTime.now().toUtc().toIso8601String(),
        'is_anonymous': anon,
        ...extra,
      };

  test('anonim selalu tampil sebagai Anonim', () {
    expect(ReviewModel.fromMap(row(anon: true)).userName, 'Anonim');
    expect(ReviewModel.fromMap(row()).userName, 'Budi');
  });

  test('batas edit 7 hari', () {
    expect(ReviewModel.fromMap(row()).canEdit, isTrue);
    final old = DateTime.now().subtract(const Duration(days: 8)).toUtc().toIso8601String();
    expect(ReviewModel.fromMap(row(created: old)).canEdit, isFalse);
  });

  test('aspek, foto, dan balasan terbaca', () {
    final r = ReviewModel.fromMap(row(extra: {
      'aspect_cleanliness': 4,
      'aspect_price': 9, // di luar 1-5 diabaikan
      'photo_urls': ['https://x/storage/v1/object/public/review-photos/o1/a.jpg'],
      'reply': 'Terima kasih!',
    }));
    expect(r.aspects, {'cleanliness': 4});
    expect(r.hasPhotos, isTrue);
    expect(r.hasReply, isTrue);
  });

  test('ringkasan dari daftar ulasan', () {
    final list = [
      ReviewModel.fromMap(row(rating: 5)),
      ReviewModel.fromMap(row(rating: 4)),
      ReviewModel.fromMap(row(rating: 4, extra: {'reply': 'ok'})),
    ];
    final s = ReviewSummary.fromReviews(list);
    expect(s.average, 4.3);
    expect(s.count, 3);
    expect(s.distribution[4], 2);
    expect(s.unreplied, 2);
    expect(formatRating(s.average), '4,3');
  });

  test('ringkasan dari RPC', () {
    final s = ReviewSummary.fromJson({
      'average': 4.8,
      'count': 12,
      'distribution': {'1': 0, '2': 0, '3': 1, '4': 1, '5': 10},
      'with_photos': 3,
      'unreplied': 2,
      'aspects': {'cleanliness': 4.9, 'price': null},
      'monthly': [
        {'month': '2026-10', 'average': 4.7, 'count': 5},
        {'month': '2026-11', 'average': 4.9, 'count': 7},
      ],
    });
    expect(s.distribution[5], 10);
    expect(s.aspects, {'cleanliness': 4.9});
    expect(s.monthly.length, 2);
    expect(s.monthly.last.$1.month, 11);
  });
}
