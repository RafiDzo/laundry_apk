import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../widgets/quick_snackbar.dart';
import '../widgets/washora_logo.dart';

const _kBlue = Color(0xFF0077E6);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kHint = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

String _rupiah(num v) =>
    'Rp ${v.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

String _qty(num q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toStringAsFixed(1).replaceAll('.', ',');

String _dateTime(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _paymentLabel(String m) {
  final s = m.toLowerCase();
  if (s.contains('qris')) return 'QRIS';
  if (s.contains('cash') || s.contains('tunai') || s.contains('cod')) {
    return 'Tunai';
  }
  if (s.contains('gopay')) return 'GoPay';
  if (s.contains('ovo')) return 'OVO';
  if (s.contains('dana')) return 'DANA';
  if (s.contains('transfer') || s.contains('bank') || s.contains('va')) {
    return 'Transfer Bank';
  }
  return m.isEmpty ? '-' : m;
}

/// Nomor struk singkat dari id pesanan, mis. "WSH-3F9A12"
String receiptNumber(OrderModel o) {
  final clean = o.id.replaceAll('-', '').toUpperCase();
  return 'WSH-${clean.length >= 6 ? clean.substring(0, 6) : clean}';
}

/// Struk / invoice pesanan yang bisa dibagikan ke WhatsApp atau disalin.
class ReceiptScreen extends StatelessWidget {
  final OrderModel order;
  const ReceiptScreen({super.key, required this.order});

  int get _itemsSubtotal =>
      order.items.fold<num>(0, (s, i) => s + i.price * i.qty).round();
  int get _otherFees => (order.totalPrice - _itemsSubtotal).clamp(0, 1 << 31);

  bool get _isPaid =>
      order.status == 'delivered' ||
      order.paymentMethod.toLowerCase().contains('qris');

  String _asText() {
    final b = StringBuffer()
      ..writeln('🧺 *STRUK WASHORA*')
      ..writeln('No: ${receiptNumber(order)}')
      ..writeln('Tanggal: ${_dateTime(order.createdAt)}')
      ..writeln('Outlet: ${order.shopName.isEmpty ? '-' : order.shopName}')
      ..writeln(
        'Layanan: ${order.isDropoff ? 'Antar sendiri (drop-off)' : 'Antar jemput kurir'}',
      )
      ..writeln('------------------------------');
    for (final i in order.items) {
      b.writeln(i.name);
      b.writeln(
        '  ${_qty(i.qty)} ${i.unit.replaceAll('/', '').trim()} x ${_rupiah(i.price)} = ${_rupiah(i.price * i.qty)}',
      );
    }
    b.writeln('------------------------------');
    if (order.items.isNotEmpty) {
      b.writeln('Subtotal: ${_rupiah(_itemsSubtotal)}');
    }
    if (_otherFees > 0) {
      b.writeln('Biaya layanan & antar: ${_rupiah(_otherFees)}');
    }
    b
      ..writeln('*TOTAL: ${_rupiah(order.totalPrice)}*')
      ..writeln(
        'Pembayaran: ${_paymentLabel(order.paymentMethod)} (${_isPaid ? 'Lunas' : 'Bayar di outlet'})',
      )
      ..writeln('Status: ${order.statusLabel}')
      ..writeln()
      ..writeln('Terima kasih sudah mencuci di Washora! ✨');
    return b.toString();
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      ),
    );
  }

  Future<void> _shareWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(_asText())}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) _toast(context, 'Tidak bisa membuka WhatsApp');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _asText()));
    _toast(context, 'Struk disalin. Tempel di chat mana saja.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF4FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: _kInk,
        title: Text(
          'Struk Pesanan',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              _buildPaper(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(
                        'Salin',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBlue,
                        side: const BorderSide(color: _kBlue),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _shareWhatsApp(context),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(
                        'Bagikan ke WhatsApp',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaper() {
    return PhysicalShape(
      clipper: const _ReceiptClipper(),
      color: Colors.white,
      elevation: 3,
      shadowColor: _kInk.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kepala struk
            const Center(child: WashoraLogo(size: 46)),
            const SizedBox(height: 6),
            Text(
              'WASHORA',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _kInk,
                letterSpacing: 3,
              ),
            ),
            Text(
              order.shopName.isEmpty ? 'Laundry Antar Jemput' : order.shopName,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kMuted),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      (_isPaid
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706))
                          .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isPaid ? '✓ LUNAS' : 'BAYAR DI OUTLET',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: _isPaid
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFB45309),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _kv('No. Struk', receiptNumber(order), bold: true),
            _kv('Tanggal', _dateTime(order.createdAt)),
            if ((order.customerName ?? '').isNotEmpty)
              _kv('Pelanggan', order.customerName!),
            _kv(
              'Layanan',
              order.isDropoff ? 'Antar sendiri' : 'Antar jemput kurir',
            ),
            _kv('Status', order.statusLabel),
            const _Dashed(),
            // Rincian item
            if (order.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Layanan laundry',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _kInk,
                  ),
                ),
              )
            else
              for (final i in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i.name,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kInk,
                              ),
                            ),
                            Text(
                              '${_qty(i.qty)} ${i.unit.replaceAll('/', '').trim()} × ${_rupiah(i.price)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: _kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _rupiah(i.price * i.qty),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kInk,
                        ),
                      ),
                    ],
                  ),
                ),
            const _Dashed(),
            if (order.items.isNotEmpty)
              _kv('Subtotal', _rupiah(_itemsSubtotal)),
            if (_otherFees > 0)
              _kv('Biaya layanan & antar', _rupiah(_otherFees)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'TOTAL',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const Spacer(),
                Text(
                  _rupiah(order.totalPrice),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _kv('Metode bayar', _paymentLabel(order.paymentMethod)),
            if ((order.notes ?? '').isNotEmpty) _kv('Catatan', order.notes!),
            const _Dashed(),
            const SizedBox(height: 4),
            // "Barcode" dekoratif dari nomor struk
            SizedBox(
              height: 44,
              child: CustomPaint(
                painter: _BarcodePainter(receiptNumber(order)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              receiptNumber(order),
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                color: _kMuted,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Terima kasih sudah mencuci di Washora ✨',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kMuted),
            ),
            Text(
              'Simpan struk ini sebagai bukti transaksi.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: _kHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: _kMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: _kInk,
                letterSpacing: bold ? 1 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (_, c) {
          final n = (c.maxWidth / 8).floor();
          return Row(
            children: List.generate(
              n,
              (_) => Expanded(
                child: Container(
                  height: 1.2,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: _kBorder,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Kertas struk dengan tepi bawah bergerigi
class _ReceiptClipper extends CustomClipper<Path> {
  const _ReceiptClipper();

  @override
  Path getClip(Size size) {
    const tooth = 10.0;
    final path = Path()
      ..moveTo(0, 12)
      ..quadraticBezierTo(0, 0, 12, 0)
      ..lineTo(size.width - 12, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 12)
      ..lineTo(size.width, size.height - tooth);
    final count = (size.width / (tooth * 2)).floor();
    final step = size.width / count;
    for (var i = count; i > 0; i--) {
      final x = i * step;
      path
        ..lineTo(x - step / 2, size.height)
        ..lineTo(x - step, size.height - tooth);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BarcodePainter extends CustomPainter {
  final String code;
  _BarcodePainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _kInk;
    final bits = <int>[];
    for (final c in code.codeUnits) {
      for (var b = 0; b < 7; b++) {
        bits.add((c >> b) & 1);
      }
    }
    final total = bits.fold<int>(0, (s, b) => s + (b == 1 ? 3 : 1) + 1);
    final unit = size.width * 0.8 / total;
    var x = size.width * 0.1;
    for (final b in bits) {
      final w = (b == 1 ? 3 : 1) * unit;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w + unit;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.code != code;
}
