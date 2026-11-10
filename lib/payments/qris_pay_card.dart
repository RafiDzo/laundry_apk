import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../receipt/receipt_preview.dart' show QrImage;
import '../utils/format_id.dart';
import '../widgets/quick_snackbar.dart';
import 'qris.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _red = Color(0xFFB91C1C);

TextStyle _t(double s, {Color c = _ink, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: s, fontWeight: w, color: c);

/// Kartu bayar QRIS dengan nominal terisi otomatis.
/// Pembeli scan dengan aplikasi e-wallet / m-banking apa pun yang mendukung QRIS.
class QrisPayCard extends StatelessWidget {
  final String payload; // teks QRIS statis pemilik dana
  final int amount;
  final String title;
  final String? caption;
  const QrisPayCard({super.key, required this.payload, required this.amount, required this.title, this.caption});

  @override
  Widget build(BuildContext context) {
    String? dynamicPayload;
    String? error;
    try {
      dynamicPayload = Qris.withAmount(payload, amount);
    } on QrisException catch (e) {
      error = e.message;
    }
    final merchant = Qris.merchantName(payload);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: _ink),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: _t(14, w: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                child: Text('QRIS', style: _t(11, w: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
              child: Text('QRIS penerima tidak valid: $error', style: _t(12.5, c: _red)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
              child: QrImage(data: dynamicPayload!, size: 220),
            ),
            const SizedBox(height: 12),
            Text(merchant.isEmpty ? 'Penerima QRIS' : merchant, style: _t(13, c: _muted, w: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(rupiah(amount), style: GoogleFonts.quicksand(fontSize: 28, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '$amount'));
                ScaffoldMessenger.of(context).showQuickSnackBar(const SnackBar(content: Text('Nominal disalin.')));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Salin nominal'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 40)),
            ),
            Text(
              caption ?? 'Scan dengan aplikasi e-wallet atau m-banking apa pun. Nominal sudah terisi otomatis.',
              textAlign: TextAlign.center,
              style: _t(11.5, c: _muted),
            ),
          ],
        ],
      ),
    );
  }
}
