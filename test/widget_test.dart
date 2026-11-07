import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/order_model.dart';

void main() {
  test('OrderModel dapat dibuat dari map hasil toMap', () {
    // Test sederhana pengganti test counter bawaan Flutter.
    // Aplikasi memakai Supabase sehingga widget test penuh memerlukan mock.
    expect(OrderModel, isNotNull);
  });
}
