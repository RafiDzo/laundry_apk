import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/screens/payment_method_page.dart';

void main() {
  test('validasi nomor WhatsApp checkout', () {
    final v = PaymentMethodPageStateTest.validate;
    expect(v('0812-3456-7899'), isNull);
    expect(v('+62 812 3456 7899'), isNull);
    expect(v('6281234567899'), isNull);
    expect(v(''), contains('wajib'));
    expect(v('0212345678'), contains('08'));
    expect(v('0812'), contains('Panjang'));
  });
}
