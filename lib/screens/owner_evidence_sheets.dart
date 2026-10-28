import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/order_model.dart';
import '../services/evidence_service.dart';
import '../widgets/evidence_widgets.dart';

const _primary = Color(0xFF0077B6);
const _textDark = Color(0xFF0F172A);
const _textLight = Color(0xFF64748B);

Widget _sheetHeader(BuildContext ctx, IconData icon, String title, String subtitle) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _textLight)),
          ],
        ),
      ),
      IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close, color: Colors.grey)),
    ],
  );
}

Widget _errorBox(String text) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600)),
    );

Widget _submitButton({required bool busy, required String label, required VoidCallback? onPressed}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        disabledBackgroundColor: const Color(0xFFCBD5E1),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Text(label, style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
    ),
  );
}

Widget _sheetContainer(BuildContext context, Widget child) {
  return Container(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      top: 24,
      left: 20,
      right: 20,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(child: child),
  );
}

// ═══════════════════════════════════════════════
//  FOTO PENERIMAAN (wajib sebelum cucian diproses)
// ═══════════════════════════════════════════════
/// Mengembalikan true jika foto & catatan penerimaan berhasil disimpan.
Future<bool> showIntakeSheet(BuildContext context, OrderModel order) async {
  final service = EvidenceService();
  final noteCtrl = TextEditingController(text: order.intakeNote ?? '');
  final countCtrl = TextEditingController(
    text: order.intakeItemCount?.toString() ??
        order.items.fold<num>(0, (s, i) => s + (i.unit.contains('kg') ? 0 : i.qty)).toInt().toString(),
  );
  List<XFile> photos = [];
  bool busy = false;
  String? error;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSheet) => _sheetContainer(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHeader(ctx, Icons.photo_camera_back_rounded, 'Foto Penerimaan',
                'Bukti kondisi cucian saat diterima outlet'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Foto seluruh cucian & bagian yang sudah rusak/bernoda sejak awal. '
                'Foto ini jadi pembanding jika pelanggan mengajukan klaim kerusakan.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF1E3A8A), height: 1.45),
              ),
            ),
            const SizedBox(height: 16),
            PhotoPickerField(
              photos: photos,
              label: 'Foto Kondisi (min. 1)',
              onChanged: (p) => setSheet(() => photos = p),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: countCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Jumlah Item / Potong',
                prefixIcon: const Icon(Icons.checkroom_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: 'Catatan Kondisi',
                hintText: 'Mis. kemeja biru kerah sobek, celana putih ada noda kuning',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (error != null) _errorBox(error!),
            const SizedBox(height: 20),
            _submitButton(
              busy: busy,
              label: 'Simpan & Mulai Proses',
              onPressed: () async {
                final count = int.tryParse(countCtrl.text) ?? 0;
                if (photos.isEmpty) {
                  setSheet(() => error = 'Ambil minimal 1 foto kondisi cucian.');
                  return;
                }
                if (count <= 0) {
                  setSheet(() => error = 'Isi jumlah item yang diterima.');
                  return;
                }
                setSheet(() {
                  busy = true;
                  error = null;
                });
                try {
                  await service.uploadPhotos(orderId: order.id, stage: 'intake', files: photos);
                  await service.saveIntake(orderId: order.id, itemCount: count, note: noteCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  print('Error intake: $e');
                  setSheet(() {
                    busy = false;
                    error = evidenceErrorMessage(e);
                  });
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

// ═══════════════════════════════════════════════
//  SERAH TERIMA (kode pelanggan + foto)
// ═══════════════════════════════════════════════
/// Mengembalikan true jika pesanan berhasil ditandai sudah diterima pelanggan.
Future<bool> showHandoverSheet(BuildContext context, OrderModel order) async {
  final service = EvidenceService();
  final codeCtrl = TextEditingController();
  final isWalkIn = order.userId.isEmpty;
  List<XFile> photos = [];
  bool photosUploaded = false; // agar tidak unggah ulang saat kode salah lalu dicoba lagi
  bool busy = false;
  String? error;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSheet) => _sheetContainer(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHeader(ctx, Icons.handshake_rounded, 'Serah Terima',
                order.isDropoff ? 'Pelanggan mengambil cucian di outlet' : 'Kurir menyerahkan cucian ke pelanggan'),
            const SizedBox(height: 16),
            if (!isWalkIn) ...[
              Text('Kode Serah Terima dari Pelanggan',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark)),
              const SizedBox(height: 4),
              Text('Minta pelanggan membuka halaman Lacak di aplikasinya dan sebutkan kode 4 digit.',
                  style: GoogleFonts.inter(fontSize: 12, color: _textLight)),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.quicksand(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 12),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '• • • •',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!photosUploaded)
              PhotoPickerField(
                photos: photos,
                label: 'Foto Serah Terima (min. 1)',
                onChanged: (p) => setSheet(() => photos = p),
              )
            else
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 6),
                  Text('Foto serah terima sudah diunggah',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                ],
              ),
            if (error != null) _errorBox(error!),
            const SizedBox(height: 20),
            _submitButton(
              busy: busy,
              label: 'Konfirmasi Diterima Pelanggan',
              onPressed: () async {
                final code = codeCtrl.text.trim();
                if (!isWalkIn && code.length != 4) {
                  setSheet(() => error = 'Masukkan 4 digit kode dari pelanggan.');
                  return;
                }
                if (!photosUploaded && photos.isEmpty) {
                  setSheet(() => error = 'Ambil minimal 1 foto saat cucian diserahkan.');
                  return;
                }
                setSheet(() {
                  busy = true;
                  error = null;
                });
                try {
                  if (!photosUploaded) {
                    await service.uploadPhotos(orderId: order.id, stage: 'handover', files: photos);
                    photosUploaded = true;
                  }
                  final res = await service.confirmHandover(order.id, isWalkIn ? null : code);
                  if (res == 'OK') {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                    return;
                  }
                  setSheet(() {
                    busy = false;
                    error = switch (res) {
                      'WRONG_CODE' => 'Kode salah. Periksa lagi kode di aplikasi pelanggan.',
                      'LOCKED' => 'Kode terkunci karena 5x salah. Minta pelanggan menekan "Sudah Diterima" di aplikasinya.',
                      'NOT_READY' => 'Pesanan harus berstatus "Selesai" sebelum diserahkan.',
                      'PHOTO_REQUIRED' => 'Foto serah terima belum tersimpan. Coba lagi.',
                      'NOT_ALLOWED' => 'Akun ini bukan pemilik outlet pesanan ini.',
                      _ => 'Serah terima gagal ($res).',
                    };
                  });
                } catch (e) {
                  print('Error handover: $e');
                  setSheet(() {
                    busy = false;
                    error = evidenceErrorMessage(e);
                  });
                }
              },
            ),
            if (!isWalkIn) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Pelanggan juga bisa menekan "Sudah Diterima" sendiri di aplikasinya.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: _textLight),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
