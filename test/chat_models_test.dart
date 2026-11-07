import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/chat_models.dart';

void main() {
  final base = {
    'id': 'm1',
    'conversation_id': 'c1',
    'sender_id': 'u1',
    'type': 'text',
    'body': 'Halo',
    'created_at': '2026-11-07T12:09:00Z',
  };

  test('status pesan: terkirim → diterima → dibaca', () {
    expect(ChatMessage.fromMap(base).state, MessageState.sent);
    expect(ChatMessage.fromMap({...base, 'delivered_at': '2026-11-07T12:10:00Z'}).state, MessageState.delivered);
    expect(
      ChatMessage.fromMap({...base, 'delivered_at': '2026-11-07T12:10:00Z', 'read_at': '2026-11-07T12:11:00Z'}).state,
      MessageState.read,
    );
  });

  test('pesan lokal: mengirim dan gagal', () {
    final m = ChatMessage.fromMap(base).copyWith(pending: true);
    expect(m.state, MessageState.sending);
    expect(m.copyWith(pending: false, failed: true).state, MessageState.failed);
  });

  test('nama lawan bicara dan hitungan belum dibaca sesuai peran', () {
    final c = ChatConversation.fromMap({
      'id': 'c1',
      'order_id': 'abcdef12-3456',
      'shop_id': 's1',
      'user_id': 'cust',
      'owner_id': 'mitra',
      'customer_name': 'Budi',
      'shop_name': 'Laundry Bersih',
      'customer_unread': 2,
      'owner_unread': 5,
      'created_at': '2026-11-07T12:00:00Z',
    });
    expect(c.partnerName('mitra'), 'Budi');
    expect(c.partnerName('cust'), 'Laundry Bersih');
    expect(c.unreadFor('mitra'), 5);
    expect(c.unreadFor('cust'), 2);
    expect(c.orderCode, 'ABCDEF12');
  });
}
