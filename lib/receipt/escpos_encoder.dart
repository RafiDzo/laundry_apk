/// Mengubah [ReceiptLine] menjadi byte perintah ESC/POS untuk thermal printer generik.
///
/// Referensi perintah (ESC/POS standar Epson, didukung mayoritas printer 58/80 mm murah):
///   ESC @        inisialisasi            ESC t n    tabel karakter (0 = PC437)
///   ESC a n      rata kiri/tengah/kanan  ESC E n    tebal on/off
///   GS ! n       ukuran huruf (0x11 = lebar & tinggi ganda)
///   ESC d n      maju n baris            GS V 66 0  potong kertas (partial, dengan feed)
///   ESC p 0 t1 t2  buka laci kas
///   GS ( k ...   QR code (model 2)
library;

import 'dart:typed_data';

import 'receipt_builder.dart';

class EscPos {
  static const esc = 0x1B;
  static const gs = 0x1D;
  static const lf = 0x0A;

  static const init = [esc, 0x40];
  static const codePagePc437 = [esc, 0x74, 0x00];
  static List<int> align(RAlign a) => [esc, 0x61, a == RAlign.left ? 0 : (a == RAlign.center ? 1 : 2)];
  static List<int> bold(bool on) => [esc, 0x45, on ? 1 : 0];
  static List<int> size({bool large = false}) => [gs, 0x21, large ? 0x11 : 0x00];
  static List<int> feed(int n) => [esc, 0x64, n.clamp(0, 255)];
  static const cut = [gs, 0x56, 0x42, 0x00];
  static const openDrawer = [esc, 0x70, 0x00, 0x19, 0xFA];

  /// QR model 2. [moduleSize] 1-16 (6 ≈ 2,5 cm di 58 mm), koreksi galat level M.
  static List<int> qr(String data, {int moduleSize = 6}) {
    final bytes = ascii(data);
    final len = bytes.length + 3;
    return [
      gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // model 2
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize.clamp(1, 16), // ukuran modul
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // koreksi galat M
      gs, 0x28, 0x6B, len & 0xFF, (len >> 8) & 0xFF, 0x31, 0x50, 0x30, ...bytes, // simpan data
      gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // cetak
    ];
  }

  /// Teks → byte ASCII. Karakter di luar ASCII sudah dibersihkan ReceiptBuilder;
  /// sisa yang lolos tetap diganti '?' agar printer tidak mencetak simbol acak.
  static List<int> ascii(String s) => [for (final c in s.codeUnits) (c >= 0x20 && c <= 0x7E) ? c : 0x3F];
}

class EscPosEncoder {
  final PaperWidth width;
  final bool cutPaper;
  final bool openCashDrawer;

  const EscPosEncoder({this.width = PaperWidth.mm58, this.cutPaper = true, this.openCashDrawer = false});

  Uint8List encode(List<ReceiptLine> lines, {int copies = 1}) {
    final out = <int>[];
    for (var c = 0; c < copies.clamp(1, 5); c++) {
      out
        ..addAll(EscPos.init)
        ..addAll(EscPos.codePagePc437);
      for (final l in lines) {
        switch (l) {
          case TextLine():
            out
              ..addAll(EscPos.align(l.align))
              ..addAll(EscPos.bold(l.bold || l.large))
              ..addAll(EscPos.size(large: l.large))
              ..addAll(EscPos.ascii(l.text))
              ..add(EscPos.lf);
            if (l.bold || l.large) out.addAll(EscPos.bold(false));
            if (l.large) out.addAll(EscPos.size());
          case DividerLine():
            out
              ..addAll(EscPos.align(RAlign.left))
              ..addAll(EscPos.ascii(l.char * width.columns))
              ..add(EscPos.lf);
          case QrLine():
            out
              ..addAll(EscPos.align(RAlign.center))
              // Perintah cetak QR sudah memindahkan kertas ke baris baru
              ..addAll(EscPos.qr(l.data, moduleSize: width == PaperWidth.mm58 ? 5 : 7))
              ..addAll(EscPos.align(RAlign.left));
          case FeedLine():
            out.addAll(EscPos.feed(l.lines));
        }
      }
      if (cutPaper) out.addAll(EscPos.cut);
    }
    if (openCashDrawer) out.addAll(EscPos.openDrawer);
    return Uint8List.fromList(out);
  }
}
