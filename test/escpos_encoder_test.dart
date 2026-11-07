import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apk/models/order_model.dart';
import 'package:laundry_apk/receipt/escpos_encoder.dart';
import 'package:laundry_apk/receipt/printer_driver.dart';
import 'package:laundry_apk/receipt/receipt_builder.dart';

ReceiptData _data({bool copy = false}) => ReceiptData(
      order: OrderModel(
        id: 'abcdef12-3456-7890',
        userId: 'u',
        shopId: 's',
        shopName: 'Laundry Bersih',
        items: [
          OrderItem(name: 'Cuci Kiloan Express Wangi Lavender Super Lembut', qty: 3.5, price: 8000, unit: '/ kg'),
          OrderItem(name: 'Setrika', qty: 4, price: 3000, unit: '/ pcs'),
        ],
        totalPrice: 39000,
        serviceFee: 2000,
        paymentMethod: 'qris',
        createdAt: DateTime(2026, 11, 7, 21, 10),
        customerName: 'José',
        promoId: 'p',
        promoTitle: 'HEMAT10',
        discountAmount: 5000,
      ),
      shopName: 'Laundry Bersih',
      shopAddress: 'Jl. Mawar No. 12',
      cashierName: 'Rafi',
      isCopy: copy,
      printedAt: DateTime(2026, 11, 7, 21, 15),
    );

bool _contains(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  for (final w in PaperWidth.values) {
    test('round-trip ${w.label}: hasil decode printer = pratinjau', () {
      final b = ReceiptBuilder(ReceiptSettings(width: w));
      final lines = b.build(_data());
      final bytes = EscPosEncoder(width: w).encode(lines);
      final job = SimulatedPrinterDriver.decode(bytes, w);
      // Pratinjau & simulasi harus identik (selain spasi di ujung baris)
      final preview = b.toText(lines).map((l) => l.trimRight()).toList();
      expect(job.paper.map((l) => l.trimRight()).toList(), preview);
      for (final l in job.paper) {
        if (!l.startsWith('[QR')) expect(l.length, lessThanOrEqualTo(w.columns));
      }
      expect(job.cuts, 1);
    });
  }

  test('perintah dasar: init, tebal, ukuran ganda, potong', () {
    final b = const ReceiptBuilder();
    final bytes = const EscPosEncoder().encode(b.build(_data()));
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(_contains(bytes, [0x1B, 0x45, 0x01]), isTrue); // tebal
    expect(_contains(bytes, [0x1D, 0x21, 0x11]), isTrue); // nama outlet besar
    expect(_contains(bytes, [0x1D, 0x56, 0x42, 0x00]), isTrue); // potong
    expect(bytes.every((x) => x <= 0xFF), isTrue);
  });

  test('QR: panjang data di header GS ( k benar', () {
    final q = EscPos.qr('WASHORA:abc');
    // blok simpan data: 1D 28 6B pL pH 31 50 30 <data>
    final i = q.indexOf(0x50) - 6;
    expect(q.sublist(i, i + 3), [0x1D, 0x28, 0x6B]);
    expect(q[i + 3], 'WASHORA:abc'.length + 3);
    expect(q[i + 4], 0);
  });

  test('karakter non-ASCII tidak pernah dikirim ke printer', () {
    final bytes = EscPos.ascii('José 🧺 李');
    expect(bytes.every((x) => x >= 0x20 && x <= 0x7E), isTrue);
  });

  test('salinan, jumlah copy, dan laci kas', () {
    final b = const ReceiptBuilder();
    final bytes = const EscPosEncoder(openCashDrawer: true).encode(b.build(_data(copy: true)), copies: 2);
    final job = SimulatedPrinterDriver.decode(bytes, PaperWidth.mm58);
    expect(job.cuts, 2);
    expect(job.drawerOpened, isTrue);
    expect(job.paper.where((l) => l.contains('SALINAN')).length, 4);
  });

  test('printer simulasi: belum tersambung & gagal di tengah cetak', () async {
    final p = SimulatedPrinterDriver();
    final bytes = const EscPosEncoder().encode(const ReceiptBuilder().build(_data()));
    expect(() => p.write(bytes), throwsA(isA<PrinterException>()));
    await p.connect();
    p.failNextWith = 'Kertas habis.';
    await expectLater(p.write(bytes), throwsA(isA<PrinterException>().having((e) => e.message, 'pesan', 'Kertas habis.')));
    expect(p.status, PrinterStatus.error);
    await p.connect();
    await p.write(bytes);
    expect(p.jobs.length, 1);
  });
}
