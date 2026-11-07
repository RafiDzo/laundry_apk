import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

import 'receipt_builder.dart';

/// Pratinjau struk di layar menyerupai kertas thermal: lebar mengikuti jumlah
/// kolom (32/48), font monospace, QR digambar dari data yang sama dengan cetakan.
class ReceiptPreview extends StatelessWidget {
  final List<ReceiptLine> lines;
  final ReceiptSettings settings;
  const ReceiptPreview({super.key, required this.lines, required this.settings});

  @override
  Widget build(BuildContext context) {
    final cols = settings.width.columns;
    return LayoutBuilder(builder: (context, c) {
      // Lebar kertas di layar: 58mm ≈ 300px, 80mm ≈ 420px, mengecil jika layar sempit
      final target = settings.width == PaperWidth.mm58 ? 300.0 : 420.0;
      final paper = target.clamp(0.0, c.maxWidth);
      const pad = 14.0;
      final fontSize = ((paper - pad * 2) / (cols * 0.6)).clamp(6.0, 14.0);
      final base = TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier New', 'Courier', 'Roboto Mono'],
        fontSize: fontSize,
        height: 1.25,
        color: const Color(0xFF111827),
      );

      Alignment align(RAlign a) => switch (a) {
            RAlign.left => Alignment.centerLeft,
            RAlign.center => Alignment.center,
            RAlign.right => Alignment.centerRight,
          };

      return Center(
        child: Container(
          width: paper,
          padding: const EdgeInsets.fromLTRB(pad, 16, pad, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in lines)
                switch (l) {
                  TextLine() => Align(
                      alignment: align(l.align),
                      child: Text(
                        l.text,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: base.copyWith(
                          fontWeight: l.bold || l.large ? FontWeight.w800 : FontWeight.w400,
                          fontSize: l.large ? fontSize * 2 : fontSize,
                        ),
                      ),
                    ),
                  DividerLine() => Text(l.char * cols, softWrap: false, overflow: TextOverflow.clip, style: base),
                  QrLine() => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(child: QrImage(data: l.data, size: 104)),
                    ),
                  FeedLine() => SizedBox(height: fontSize * 1.25 * l.lines),
                },
            ],
          ),
        ),
      );
    });
  }
}

/// QR code dari paket `barcode` (paket yang sama dipakai PDF), tanpa dependensi tambahan.
class QrImage extends StatelessWidget {
  final String data;
  final double size;
  const QrImage({super.key, required this.data, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kode QR pesanan',
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(data)),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    for (final e in Barcode.qrCode().make(data, width: size.width, height: size.height)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.data != data;
}
