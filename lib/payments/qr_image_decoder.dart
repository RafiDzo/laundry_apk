import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Baca kode QR dari file gambar (PNG/JPG/WebP) murni di Dart, sehingga
/// berjalan di semua platform termasuk web (Chrome).
/// Mengembalikan teks QR, atau null jika tidak ada QR yang terbaca.
String? decodeQrFromImageBytes(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;

  // Gambar besar (foto kamera 12MP) diperkecil agar cepat; QR tetap terbaca.
  const maxSide = 1400;
  if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }

  final pixels = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.abgr)
      .buffer
      .asInt32List();
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);

  // Dua cara binarisasi: Hybrid bagus untuk foto (cahaya tidak rata),
  // GlobalHistogram bagus untuk screenshot / gambar digital.
  for (final bitmap in [
    BinaryBitmap(HybridBinarizer(source)),
    BinaryBitmap(GlobalHistogramBinarizer(source)),
  ]) {
    try {
      return QRCodeReader().decode(bitmap, hints: hints).text;
    } catch (_) {
      // coba cara berikutnya
    }
  }
  return null;
}
