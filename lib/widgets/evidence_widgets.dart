import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/evidence_models.dart';

const _blue = Color(0xFF0077E6);
const _textDark = Color(0xFF0F172A);
const _textLight = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

/// Pengambil foto bukti: kamera / galeri, pratinjau, hapus sebelum diunggah.
class PhotoPickerField extends StatefulWidget {
  final List<XFile> photos;
  final ValueChanged<List<XFile>> onChanged;
  final int maxPhotos;
  final String label;

  const PhotoPickerField({
    super.key,
    required this.photos,
    required this.onChanged,
    this.maxPhotos = 5,
    this.label = 'Foto Bukti',
  });

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  final ImagePicker _picker = ImagePicker();
  final Map<XFile, Future<Uint8List>> _previews = {};

  Future<Uint8List> _preview(XFile f) => _previews.putIfAbsent(f, () => f.readAsBytes());

  Future<void> _pick(ImageSource source) async {
    final remaining = widget.maxPhotos - widget.photos.length;
    if (remaining <= 0) return;
    try {
      List<XFile> picked;
      if (source == ImageSource.gallery) {
        picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 75, limit: remaining);
      } else {
        final one = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 75);
        picked = one == null ? [] : [one];
      }
      if (picked.isEmpty) return;
      widget.onChanged([...widget.photos, ...picked.take(remaining)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak dapat mengambil foto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.photos.length < widget.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.label} (${widget.photos.length}/${widget.maxPhotos})',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...widget.photos.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FutureBuilder<Uint8List>(
                            future: _preview(f),
                            builder: (_, snap) => snap.hasData
                                ? Image.memory(snap.data!, width: 84, height: 84, fit: BoxFit.cover)
                                : Container(width: 84, height: 84, color: const Color(0xFFF1F5F9)),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              _previews.remove(f);
                              widget.onChanged(widget.photos.where((p) => p != f).toList());
                            },
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              if (canAdd) ...[
                // Di browser, "Kamera" tetap membuka pemilih file
                if (!kIsWeb) _addButton(Icons.photo_camera_rounded, 'Kamera', () => _pick(ImageSource.camera)),
                _addButton(Icons.add_photo_alternate_rounded, kIsWeb ? 'Pilih Foto' : 'Galeri',
                    () => _pick(ImageSource.gallery)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _addButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _blue),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _blue)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Galeri foto bukti (signed URL). Ketuk untuk memperbesar.
class PhotoGallery extends StatelessWidget {
  final List<OrderPhoto> photos;
  final String emptyText;
  final double size;

  const PhotoGallery({
    super.key,
    required this.photos,
    this.emptyText = 'Belum ada foto',
    this.size = 84,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Text(emptyText, style: GoogleFonts.inter(fontSize: 12, color: _textLight));
    }
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final url = photos[i].url;
          return GestureDetector(
            onTap: url == null ? null : () => _openViewer(context, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(border: Border.all(color: _border)),
                child: url == null
                    ? const Icon(Icons.broken_image_outlined, color: _textLight)
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: _textLight),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openViewer(BuildContext context, int initial) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initial),
              itemCount: photos.length,
              itemBuilder: (_, i) => InteractiveViewer(
                child: Center(child: Image.network(photos[i].url ?? '', fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pesan ramah untuk kode hasil RPC / error database
String evidenceErrorMessage(Object error) {
  final msg = error.toString();
  if (msg.contains('INTAKE_PHOTO_REQUIRED')) {
    return 'Foto kondisi cucian saat diterima wajib diunggah sebelum diproses.';
  }
  if (msg.contains('HANDOVER_REQUIRED')) {
    return 'Status "Diantar" hanya bisa lewat kode serah terima dari pelanggan.';
  }
  if (msg.contains('ORDER_ALREADY_RECEIVED')) {
    return 'Pesanan sudah diterima pelanggan dan tidak bisa diubah lagi.';
  }
  if (msg.contains('row-level security') || msg.contains('42501')) {
    return 'Akses ditolak. Pastikan SQL supabase_bukti_klaim.sql sudah dijalankan.';
  }
  if (msg.contains('Bucket not found')) {
    return 'Penyimpanan foto belum dibuat. Jalankan SQL supabase_bukti_klaim.sql.';
  }
  return 'Terjadi kesalahan: $msg';
}
