import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_builder.dart';

/// Struk sebagai PDF selebar kertas thermal (58/80 mm), font monospace Courier
/// dengan ukuran dihitung agar 32/48 kolom pas satu baris — sama dengan printer.
Future<Uint8List> buildReceiptPdf(List<ReceiptLine> lines, ReceiptSettings settings) async {
  final roll = settings.width == PaperWidth.mm58 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
  const margin = 2.5 * PdfPageFormat.mm;
  final format = roll.copyWith(marginLeft: margin, marginRight: margin, marginTop: 3 * PdfPageFormat.mm, marginBottom: 3 * PdfPageFormat.mm);
  final cols = settings.width.columns;
  // Lebar satu huruf Courier = 0,6 × ukuran font
  final fontSize = (format.availableWidth / (cols * 0.6)) * 0.98;
  final regular = pw.Font.courier();
  final bold = pw.Font.courierBold();

  pw.Alignment align(RAlign a) => switch (a) {
        RAlign.left => pw.Alignment.centerLeft,
        RAlign.center => pw.Alignment.center,
        RAlign.right => pw.Alignment.centerRight,
      };

  final doc = pw.Document(title: 'Struk Washora', author: 'Washora');
  doc.addPage(
    pw.Page(
      pageFormat: format,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final l in lines)
            switch (l) {
              TextLine() => pw.Align(
                  alignment: align(l.align),
                  child: pw.Text(
                    l.text,
                    style: pw.TextStyle(
                      font: l.bold || l.large ? bold : regular,
                      fontSize: l.large ? fontSize * 2 : fontSize,
                      lineSpacing: 0,
                    ),
                  ),
                ),
              DividerLine() => pw.Text(l.char * cols, style: pw.TextStyle(font: regular, fontSize: fontSize)),
              QrLine() => pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: l.data,
                      width: 26 * PdfPageFormat.mm,
                      height: 26 * PdfPageFormat.mm,
                    ),
                  ),
                ),
              FeedLine() => pw.SizedBox(height: fontSize * 1.2 * l.lines),
            },
        ],
      ),
    ),
  );
  return doc.save();
}
