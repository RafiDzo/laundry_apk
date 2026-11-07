import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/order_model.dart';
import '../models/review_model.dart';
import '../screens/receipt_screen.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'review_sheet.dart';

/// Bar tombol bawah untuk pesanan yang sudah selesai: Lihat Struk + Beri Ulasan.
class OrderDoneActions extends StatefulWidget {
  final OrderModel order;
  const OrderDoneActions({super.key, required this.order});

  @override
  State<OrderDoneActions> createState() => _OrderDoneActionsState();
}

class _OrderDoneActionsState extends State<OrderDoneActions> {
  ReviewModel? _review;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    final map = await SupabaseService().getMyReviewsByOrder(user.id);
    if (!mounted) return;
    setState(() {
      _review = map[widget.order.id];
      _loaded = true;
    });
    _maybePrompt();
  }

  /// Pengingat sekali per pesanan: buka form rating otomatis saat pesanan
  /// sudah diterima dan belum diulas.
  Future<void> _maybePrompt() async {
    if (_review != null || widget.order.status != 'delivered') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'review_prompted_${widget.order.id}';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
    } catch (_) {
      return; // tanpa penyimpanan lokal, jangan memunculkan pop-up berulang
    }
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _openReview();
  }

  Future<void> _openReview() async {
    final sent = await showReviewSheet(
      context,
      widget.order,
      existing: _review,
    );
    // Form sudah menampilkan "Terima kasih atas ulasanmu"; cukup muat ulang status tombol
    if (sent && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptScreen(order: widget.order),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: Text(
                  'Lihat Struk',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0077E6),
                  side: const BorderSide(color: Color(0xFF0077E6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openReview,
                icon: const Icon(Icons.star_rounded, size: 18),
                label: Text(
                  !_loaded
                      ? 'Beri Rating'
                      : _review == null
                          ? 'Beri Rating'
                          : (_review!.canEdit ? 'Ubah rating ★${_review!.rating}' : 'Ratingmu ★${_review!.rating}'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
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
      ),
    );
  }
}
