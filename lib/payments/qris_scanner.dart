import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_image_decoder.dart';
import 'qris.dart';

/// Hasil membaca QRIS dari kamera / gambar.
class QrisReadResult {
  final String? payload;
  final String? error;
  const QrisReadResult.ok(String this.payload) : error = null;
  const QrisReadResult.fail(String this.error) : payload = null;
  bool get ok => payload != null;
}

/// Pilih nilai QRIS dari daftar kode yang terbaca. QR lain (link, teks biasa)
/// dikenali agar pesan errornya jelas.
QrisReadResult pickQris(Iterable<String?> raws) {
  final codes = raws.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (codes.isEmpty) return const QrisReadResult.fail('Tidak ada kode QR yang terbaca.');
  for (final c in codes) {
    if (Qris.validate(c) == null) return QrisReadResult.ok(c);
  }
  final c = codes.first;
  if (c.startsWith('000201')) {
    return QrisReadResult.fail('Kode QRIS terbaca tapi rusak: ${Qris.validate(c)}');
  }
  return const QrisReadResult.fail('Kode QR ini bukan QRIS. Gunakan QRIS statis dari bank / e-wallet outlet.');
}

/// Galeri → baca QR dari gambar. Android/iOS memakai pembaca bawaan (ML Kit /
/// Vision); jika gagal, dan selalu di web, memakai pembaca Dart (zxing2).
Future<QrisReadResult?> readQrisFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null; // dibatalkan

  const notFound = QrisReadResult.fail(
      'QR tidak ditemukan di gambar. Pastikan gambar QRIS terlihat utuh, tidak buram, dan tidak terpotong.');

  if (!kIsWeb) {
    final controller = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.qrCode]);
    try {
      final capture = await controller.analyzeImage(file.path, formats: const [BarcodeFormat.qrCode]);
      if (capture != null && capture.barcodes.isNotEmpty) {
        return pickQris(capture.barcodes.map((b) => b.rawValue));
      }
    } catch (_) {
      // lanjut ke pembaca Dart
    } finally {
      controller.dispose();
    }
  }

  try {
    final text = decodeQrFromImageBytes(await file.readAsBytes());
    return text == null ? notFound : pickQris([text]);
  } catch (_) {
    return const QrisReadResult.fail('Gambar tidak bisa dibaca. Gunakan file PNG/JPG, atau coba Scan Kamera.');
  }
}

/// Kamera → halaman pemindai; kembali dengan payload QRIS valid atau null.
Future<String?> scanQrisWithCamera(BuildContext context) {
  return Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _QrisScanPage()));
}

class _QrisScanPage extends StatefulWidget {
  const _QrisScanPage();

  @override
  State<_QrisScanPage> createState() => _QrisScanPageState();
}

class _QrisScanPageState extends State<_QrisScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _hint;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final r = pickQris(capture.barcodes.map((b) => b.rawValue));
    if (r.ok) {
      _done = true;
      Navigator.pop(context, r.payload);
    } else if (r.error != _hint) {
      setState(() => _hint = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = (size.width * 0.72).clamp(200.0, 320.0);
    final window = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.42), width: box, height: box);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Scan QRIS Outlet', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'Matikan senter' : 'Nyalakan senter',
                icon: Icon(on ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            placeholderBuilder: (context) => _ScanMessage(
              icon: Icons.videocam_outlined,
              message: kIsWeb
                  ? 'Menyalakan kamera...\nJika browser meminta izin kamera, klik "Izinkan" (Allow) di dekat bar alamat.'
                  : 'Menyalakan kamera...',
            ),
            errorBuilder: (context, e) => _ScanMessage(
              icon: Icons.no_photography_outlined,
              message: switch (e.errorCode) {
                MobileScannerErrorCode.permissionDenied => kIsWeb
                    ? 'Izin kamera ditolak browser. Klik ikon kamera/gembok di bar alamat → izinkan Kamera, lalu muat ulang halaman. '
                        'Atau gunakan "Dari Galeri".'
                    : 'Izin kamera ditolak. Aktifkan izin kamera untuk Washora di Pengaturan HP, atau gunakan "Dari Galeri".',
                MobileScannerErrorCode.unsupported =>
                  'Perangkat ini tidak punya kamera yang bisa dipakai. Gunakan "Dari Galeri".',
                _ => 'Kamera tidak bisa dibuka (mungkin sedang dipakai aplikasi lain). Gunakan "Dari Galeri".',
              },
            ),
          ),
          // Bingkai area pindai
          Positioned.fromRect(
            rect: window,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 24,
            child: Column(
              children: [
                Text(
                  'Arahkan kamera ke stiker QRIS outlet Anda',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_hint != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_hint!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _ScanMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}
