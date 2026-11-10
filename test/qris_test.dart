import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:laundry_apk/payments/qr_image_decoder.dart';
import 'package:zxing2/qrcode.dart' as zx;
import 'package:laundry_apk/payments/qris.dart';
import 'package:laundry_apk/payments/qris_scanner.dart';

/// Susun QRIS statis contoh (merchant fiktif) dengan CRC yang benar
String sampleStatic() {
  String tlv(String t, String v) => '$t${v.length.toString().padLeft(2, '0')}$v';
  final merchant = tlv('00', 'ID.CO.CONTOH.WWW') + tlv('01', '936000000000000001') + tlv('02', 'ID1234567890123') + tlv('03', 'UMI');
  final body = tlv('00', '01') +
      tlv('01', '11') +
      tlv('26', merchant) +
      tlv('52', '7210') +
      tlv('53', '360') +
      tlv('58', 'ID') +
      tlv('59', 'LAUNDRY CONTOH') +
      tlv('60', 'SURABAYA') +
      tlv('61', '60111') +
      '6304';
  return body + Qris.crc16(body);
}

void main() {
  test('CRC16-CCITT sesuai nilai uji standar', () {
    // CRC-16/CCITT-FALSE untuk "123456789" = 29B1
    expect(Qris.crc16('123456789'), '29B1');
  });

  test('validasi QRIS statis contoh', () {
    final s = sampleStatic();
    expect(Qris.validate(s), isNull);
    expect(Qris.isStatic(s), isTrue);
    expect(Qris.merchantName(s), 'LAUNDRY CONTOH');
    expect(Qris.merchantCity(s), 'SURABAYA');
  });

  test('statis → dinamis: tag 01=12, tag 54 sebelum 58, CRC valid', () {
    final d = Qris.withAmount(sampleStatic(), 12000);
    expect(Qris.validate(d), isNull);
    expect(Qris.isStatic(d), isFalse);
    expect(Qris.amountOf(d), 12000);
    expect(d.indexOf('540512000') < d.indexOf('5802ID'), isTrue);
    expect(Qris.merchantName(d), 'LAUNDRY CONTOH');
  });

  test('nominal lama diganti, bukan digandakan', () {
    final d1 = Qris.withAmount(sampleStatic(), 12000);
    final d2 = Qris.withAmount(d1, 49137);
    expect(Qris.amountOf(d2), 49137);
    expect(RegExp('54').allMatches(d2.substring(0, d2.indexOf('5802'))).isNotEmpty, isTrue);
    expect(Qris.validate(d2), isNull);
  });

  test('teks rusak ditolak dengan alasan jelas', () {
    final s = sampleStatic();
    expect(Qris.validate(''), isNotNull);
    expect(Qris.validate('hello'), contains('000201'));
    expect(Qris.validate('${s.substring(0, s.length - 1)}0'), contains('Checksum'));
    expect(() => Qris.withAmount(s, 0), throwsA(isA<QrisException>()));
  });

  test('pickQris memilih QRIS valid dari hasil scan', () {
    final s = sampleStatic();
    expect(pickQris(['https://contoh.id', s]).payload, s);
    expect(pickQris([null, '  ']).ok, isFalse);
    expect(pickQris(['https://contoh.id']).error, contains('bukan QRIS'));
    expect(pickQris(['${s.substring(0, s.length - 1)}0']).error, contains('rusak'));
  });

  test('NMID dikenali dan diberi pesan jelas', () {
    expect(Qris.looksLikeNmid('ID1026634963833A01'), isTrue);
    expect(Qris.validate('ID1026634963833A01'), contains('NMID'));
    expect(Qris.looksLikeNmid(sampleStatic()), isFalse);
  });

  test('gambar QRIS (PNG & JPG) terbaca oleh pembaca Dart', () {
    final payload = sampleStatic();
    final m = zx.Encoder.encode(payload, zx.ErrorCorrectionLevel.m).matrix!;
    const scale = 6, pad = 60;
    final image = img.Image(width: m.width * scale + pad * 2, height: m.height * scale + pad * 2);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var x = 0; x < m.width; x++) {
      for (var y = 0; y < m.height; y++) {
        if (m.get(x, y) == 1) {
          img.fillRect(image,
              x1: pad + x * scale, y1: pad + y * scale,
              x2: pad + (x + 1) * scale - 1, y2: pad + (y + 1) * scale - 1,
              color: img.ColorRgb8(0, 0, 0));
        }
      }
    }
    expect(decodeQrFromImageBytes(img.encodePng(image)), payload);
    expect(decodeQrFromImageBytes(img.encodeJpg(image, quality: 80)), payload);

    final blank = img.Image(width: 300, height: 300);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(decodeQrFromImageBytes(img.encodePng(blank)), isNull);
  });
}
