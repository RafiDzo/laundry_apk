import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/order_model.dart';
import '../models/review_model.dart';
import '../screens/receipt_screen.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'quick_snackbar.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    final map = await SupabaseService().getMyReviewsByOrder(user.id);
    if (mounted) setState(() => _review = map[widget.order.id]);
  }

  Future<void> _openReview() async {
    final sent = await showReviewSheet(
      context,
      widget.order,
      existing: _review,
    );
    if (!sent || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF16A34A),
        content: Text(
          'Terima kasih! Ulasanmu sudah tersimpan 🎉',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
      ),
    );
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
                  _review == null
                      ? 'Beri Ulasan'
                      : 'Ulasanmu ${_review!.rating}★',
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
