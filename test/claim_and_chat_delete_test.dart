import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/chat_models.dart';
import 'package:laundry_apk/models/evidence_models.dart';

void main() {
  Map<String, dynamic> claim(String status, {DateTime? created, String? resolution, Map<String, dynamic> extra = const {}}) => {
        'id': 'c1',
        'order_id': 'o1',
        'user_id': 'u1',
        'shop_id': 's1',
        'description': 'Kemeja luntur di kerah',
        'status': status,
        'resolution': resolution,
        'created_at': (created ?? DateTime.now()).toUtc().toIso8601String(),
        ...extra,
      };

  group('klaim', () {
    test('lewat 2x24 jam tanpa respons bisa dinaikkan', () {
      final fresh = DamageClaim.fromMap(claim('pending'));
      final old = DamageClaim.fromMap(claim('pending', created: DateTime.now().subtract(const Duration(hours: 49))));
      expect(fresh.isOverdue, isFalse);
      expect(old.isOverdue, isTrue);
      expect(old.canEscalate, isTrue);
    });

    test('disetujui cuci ulang menunggu dituntaskan; poin langsung selesai', () {
      expect(DamageClaim.fromMap(claim('approved', resolution: 'rewash')).awaitingSettlement, isTrue);
      expect(DamageClaim.fromMap(claim('resolved', resolution: 'points')).isResolved, isTrue);
      expect(DamageClaim.fromMap(claim('approved', resolution: 'points')).awaitingSettlement, isFalse);
    });

    test('label kategori, item, dan permintaan', () {
      final c = DamageClaim.fromMap(claim('pending', extra: {
        'category': 'faded',
        'affected_items': ['Kemeja Putih'],
        'requested_resolution': 'compensation',
        'requested_amount': 75000,
      }));
      expect(c.categoryLabel, 'Luntur / berubah warna');
      expect(c.affectedItems, ['Kemeja Putih']);
      expect(c.requestedLabel, 'Ganti rugi Rp 75.000');
      expect(DamageClaim.resolutionText('points', 20000), '20000 poin (= Rp 20.000)');
      expect(DamageClaim.fromMap(claim('resolved')).statusLabel, 'Selesai');
    });
  });

  group('hapus chat', () {
    final base = {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'me',
      'type': 'image',
      'body': '',
      'image_path': 'c1/me_x.jpg',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    test('pesan ditarik: bukan gambar lagi & tidak bisa ditarik ulang', () {
      final m = ChatMessage.fromMap({...base, 'deleted_at': DateTime.now().toUtc().toIso8601String()});
      expect(m.isDeleted, isTrue);
      expect(m.isImage, isFalse);
      expect(m.canUnsend('me'), isFalse);
    });

    test('tarik pesan hanya pengirim & dalam 24 jam', () {
      final m = ChatMessage.fromMap(base);
      expect(m.canUnsend('me'), isTrue);
      expect(m.canUnsend('other'), isFalse);
      final old = ChatMessage.fromMap({...base, 'created_at': DateTime.now().subtract(const Duration(hours: 25)).toUtc().toIso8601String()});
      expect(old.canUnsend('me'), isFalse);
    });

    test('percakapan yang dihapus muncul lagi saat ada pesan baru', () {
      final now = DateTime.now();
      Map<String, dynamic> conv(DateTime last, DateTime? cleared) => {
            'id': 'c1',
            'order_id': 'o1',
            'shop_id': 's1',
            'user_id': 'cust',
            'owner_id': 'mitra',
            'last_message_at': last.toUtc().toIso8601String(),
            'owner_cleared_at': cleared?.toUtc().toIso8601String(),
            'created_at': now.subtract(const Duration(days: 40)).toUtc().toIso8601String(),
          };
      final hidden = ChatConversation.fromMap(conv(now.subtract(const Duration(days: 2)), now.subtract(const Duration(days: 1))));
      expect(hidden.visibleFor('mitra'), isFalse);
      expect(hidden.visibleFor('cust'), isTrue); // pelanggan tidak menghapus
      final back = ChatConversation.fromMap(conv(now, now.subtract(const Duration(days: 1))));
      expect(back.visibleFor('mitra'), isTrue);
    });
  });
}
