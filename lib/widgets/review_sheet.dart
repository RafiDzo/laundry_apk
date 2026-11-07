import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/order_model.dart';
import '../models/review_model.dart';
import '../services/supabase_service.dart';
import 'quick_snackbar.dart';

const _kBlue = Color(0xFF0077E6);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kStar = Color(0xFFFBBF24);

const _ratingWords = [
  '',
  'Sangat Buruk',
  'Kurang',
  'Cukup',
  'Bagus',
  'Luar Biasa!',
];
const _quickTags = [
  'Wangi tahan lama',
  'Bersih banget',
  'Rapi & licin',
  'Tepat waktu',
  'Kurir ramah',
  'Harga terjangkau',
  'Packing rapi',
];

/// Lembar ulasan untuk pesanan yang sudah selesai.
/// Mengembalikan true jika ulasan berhasil dikirim.
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
  late final _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String get _serviceSummary {
    final items = widget.order.items;
    if (items.isEmpty) return 'Layanan laundry';
    final first = items.first.name;
    return items.length > 1 ? '$first +${items.length - 1}' : first;
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            'Pilih jumlah bintang dulu ya',
            style: GoogleFonts.plusJakartaSans(),
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await SupabaseService().submitReview(
        orderId: widget.order.id,
        shopId: widget.order.shopId,
        rating: _rating,
        comment: _comment.text.trim(),
        tags: _tags.toList(),
        serviceSummary: _serviceSummary,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final msg = e.toString();
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
          content: Text(
            msg.contains('reviews') &&
                    (msg.contains('does not exist') || msg.contains('42P01'))
                ? 'Fitur ulasan belum aktif. Jalankan supabase_ulasan_lokasi.sql di Supabase.'
                : msg.contains('row-level security') || msg.contains('42501')
                ? 'Ulasan hanya bisa dikirim untuk pesanan yang sudah selesai.'
                : 'Gagal mengirim ulasan. Coba lagi.',
            style: GoogleFonts.plusJakartaSans(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _kBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.existing == null
                      ? 'Bagaimana cucianmu?'
                      : 'Ubah ulasanmu',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.order.shopName.isEmpty ? 'Outlet' : widget.order.shopName} • $_serviceSummary',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _rating;
                    return GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: AnimatedScale(
                        scale: filled ? 1.0 : 0.88,
                        duration: const Duration(milliseconds: 150),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            filled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 44,
                            color: filled ? _kStar : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _rating == 0
                        ? 'Ketuk bintang untuk menilai'
                        : _ratingWords[_rating],
                    key: ValueKey(_rating),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _rating == 0
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Apa yang kamu suka?',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickTags.map((t) {
                    final on = _tags.contains(t);
                    return GestureDetector(
                      onTap: () =>
                          setState(() => on ? _tags.remove(t) : _tags.add(t)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? _kBlue.withValues(alpha: 0.10)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: on ? _kBlue : _kBorder),
                        ),
                        child: Text(
                          t,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: on ? _kBlue : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _comment,
                  maxLines: 3,
                  maxLength: 300,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ceritakan pengalamanmu (opsional)',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _kBlue, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.existing == null
                                ? 'Kirim Ulasan'
                                : 'Simpan Perubahan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
