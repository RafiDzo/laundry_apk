import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/order_model.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'review_widgets.dart';

const _kBlue = Color(0xFF0077E6);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kRed = Color(0xFFB91C1C);

/// Tag cepat: yang positif ditawarkan untuk 4-5 bintang, yang perlu perbaikan untuk 1-3.
const _goodTags = ['Wangi', 'Bersih', 'Rapi', 'Tepat waktu', 'Kurir ramah', 'Harga pas'];
const _badTags = ['Lama', 'Kurang bersih', 'Bau', 'Kusut', 'Ada yang hilang', 'Kurang ramah'];

/// Lembar rating & ulasan untuk pesanan yang sudah diterima.
/// Mengembalikan true jika ulasan berhasil dikirim/diubah.
Future<bool> showReviewSheet(
  BuildContext context,
  OrderModel order, {
  ReviewModel? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(order: order, existing: existing),
  );
  return result ?? false;
}

class _ReviewSheet extends StatefulWidget {
  final OrderModel order;
  final ReviewModel? existing;
  const _ReviewSheet({required this.order, this.existing});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final Set<String> _tags = {...?widget.existing?.tags};
  late final _comment = TextEditingController(text: widget.existing?.comment ?? '');
  late final Map<ReviewAspect, int> _aspects = {
    for (final e in (widget.existing?.aspects ?? const <String, int>{}).entries)
      if (ReviewAspect.byKey(e.key) != null) ReviewAspect.byKey(e.key)!: e.value,
  };
  late bool _anonymous = widget.existing?.isAnonymous ?? false;
  late final List<String> _keptPhotos = [...?widget.existing?.photoUrls];
  final List<(Uint8List, String)> _newPhotos = [];
  bool _showAspects = false;
  bool _sending = false;
  bool _done = false;
  String? _error;
  String? _ratingError;

  bool get _locked => widget.existing != null && !widget.existing!.canEdit;
  int get _photoCount => _keptPhotos.length + _newPhotos.length;

  @override
  void initState() {
    super.initState();
    _showAspects = _aspects.isNotEmpty;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_photoCount >= ReviewService.maxPhotos) return;
    try {
      // Kompresi sebelum unggah: sisi terpanjang 1280px, kualitas 70
      final f = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > ReviewService.maxPhotoBytes) {
        setState(() => _error = 'Ukuran foto melebihi 2 MB setelah dikompres. Pilih foto lain.');
        return;
      }
      final n = f.name.toLowerCase();
      final mime = f.mimeType ?? (n.endsWith('.png') ? 'image/png' : n.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      setState(() {
        _newPhotos.add((bytes, mime));
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Foto tidak bisa dibuka.');
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _ratingError = 'Pilih jumlah bintang dulu ya. Bagian lain boleh dikosongkan.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
      _ratingError = null;
    });
    try {
      await ReviewService().submit(
        order: widget.order,
        rating: _rating,
        comment: _comment.text,
        tags: _tags.toList(),
        aspects: _aspects,
        anonymous: _anonymous,
        keptPhotoUrls: _keptPhotos,
        newPhotos: _newPhotos,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 1300));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(top: false, child: _done ? _thanks() : _form()),
      ),
    );
  }

  Widget _thanks() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.check_rounded, color: Color(0xFF15803D), size: 36),
          ),
          const SizedBox(height: 16),
          Text('Terima kasih atas ulasanmu',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: _kInk)),
          const SizedBox(height: 6),
          Text('Ulasanmu membantu pelanggan lain memilih outlet.',
              textAlign: TextAlign.center, style: rvText(12.5, color: _kMuted)),
        ],
      ),
    );
  }

  Widget _form() {
    final tags = _rating == 0 ? _goodTags : (_rating >= 4 ? _goodTags : _badTags);
    final ex = widget.existing;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 18),
          Text(
            ex == null ? 'Bagaimana cucianmu?' : (_locked ? 'Ulasanmu' : 'Ubah ulasanmu'),
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 19, fontWeight: FontWeight.w800, color: _kInk),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.order.shopName.isEmpty ? 'Outlet' : widget.order.shopName} • Pesanan #${widget.order.id.length > 8 ? widget.order.id.substring(0, 8).toUpperCase() : widget.order.id}',
            textAlign: TextAlign.center,
            style: rvText(12, color: _kMuted),
          ),
          if (ex != null) ...[
            const SizedBox(height: 8),
            Text(
              _locked
                  ? 'Batas ubah ulasan (7 hari) sudah lewat.'
                  : 'Bisa diubah sampai ${ex.editableUntil.day.toString().padLeft(2, '0')}/${ex.editableUntil.month.toString().padLeft(2, '0')}.',
              textAlign: TextAlign.center,
              style: rvText(11.5, color: _locked ? _kRed : _kMuted, weight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          IgnorePointer(
            ignoring: _locked,
            child: Center(
              child: StarInput(
                value: _rating,
                onChanged: (v) => setState(() {
                  // Tag yang tidak cocok lagi dengan arah rating dibuang
                  if ((v >= 4) != (_rating >= 4)) _tags.removeWhere((t) => !(v >= 4 ? _goodTags : _badTags).contains(t));
                  _rating = v;
                  _ratingError = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _rating == 0 ? 'Ketuk atau geser bintang · wajib' : ratingWords[_rating],
            textAlign: TextAlign.center,
            style: rvText(13, color: _rating == 0 ? const Color(0xFF94A3B8) : const Color(0xFFB45309), weight: FontWeight.w700),
          ),
          if (_ratingError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_ratingError!, textAlign: TextAlign.center, style: rvText(12, color: _kRed, weight: FontWeight.w600)),
            ),
          if (!_locked) ...[
            const SizedBox(height: 18),
            Text(_rating > 0 && _rating < 4 ? 'Apa yang perlu diperbaiki?' : 'Apa yang kamu suka?',
                style: rvText(13, color: _kInk, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tags)
                  FilterChip(
                    label: Text(t),
                    selected: _tags.contains(t),
                    onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                    labelStyle: rvText(12, color: _tags.contains(t) ? _kBlue : const Color(0xFF475569), weight: FontWeight.w600),
                    selectedColor: _kBlue.withValues(alpha: 0.10),
                    checkmarkColor: _kBlue,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _tags.contains(t) ? _kBlue : _kBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Penilaian per aspek (opsional, dilipat agar form tetap singkat)
            InkWell(
              onTap: () => setState(() => _showAspects = !_showAspects),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Nilai per aspek (opsional)', style: rvText(13, color: _kInk, weight: FontWeight.w700)),
                    ),
                    Icon(_showAspects ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _kMuted),
                  ],
                ),
              ),
            ),
            if (_showAspects)
              for (final a in ReviewAspect.values)
                Row(
                  children: [
                    Expanded(child: Text(a.label, style: rvText(12.5, color: _kInk))),
                    StarInput(
                      value: _aspects[a] ?? 0,
                      size: 26,
                      onChanged: (v) => setState(() => _aspects[a] = v),
                    ),
                  ],
                ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              maxLines: 4,
              maxLength: 500,
              style: rvText(13, color: _kInk),
              decoration: InputDecoration(
                hintText: 'Ceritakan pengalamanmu (opsional)',
                hintStyle: rvText(13, color: const Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _kBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _kBlue, width: 1.5)),
              ),
            ),
            const SizedBox(height: 4),
            Text('Foto hasil cucian (opsional, maks. ${ReviewService.maxPhotos})',
                style: rvText(13, color: _kInk, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _keptPhotos.length; i++)
                  _thumb(Image.network(_keptPhotos[i], fit: BoxFit.cover), () => setState(() => _keptPhotos.removeAt(i))),
                for (var i = 0; i < _newPhotos.length; i++)
                  _thumb(Image.memory(_newPhotos[i].$1, fit: BoxFit.cover), () => setState(() => _newPhotos.removeAt(i))),
                if (_photoCount < ReviewService.maxPhotos) ...[
                  _addTile(Icons.add_photo_alternate_outlined, 'Galeri', () => _addPhoto(ImageSource.gallery)),
                  if (!kIsWeb) _addTile(Icons.photo_camera_outlined, 'Kamera', () => _addPhoto(ImageSource.camera)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              title: Text('Kirim sebagai anonim', style: rvText(13, color: _kInk, weight: FontWeight.w700)),
              subtitle: Text('Namamu tampil sebagai "Anonim" di halaman outlet', style: rvText(11.5, color: _kMuted)),
            ),
          ],
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: _kRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: rvText(12, color: _kRed, weight: FontWeight.w600))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (!_locked)
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _sending
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(
                        _error != null ? 'Coba lagi' : (widget.existing == null ? 'Kirim Ulasan' : 'Simpan Perubahan'),
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
              ),
            )
          else
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Tutup'),
            ),
        ],
      ),
    );
  }

  Widget _thumb(Widget image, VoidCallback onRemove) => Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 72, height: 72, child: image)),
          Positioned(
            top: -8,
            right: -8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(side: BorderSide(color: _kBorder)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.close_rounded, size: 16, color: _kMuted),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _addTile(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _kMuted, size: 22),
              const SizedBox(height: 2),
              Text(label, style: rvText(10.5, color: _kMuted, weight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
