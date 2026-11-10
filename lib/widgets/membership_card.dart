import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/membership_models.dart';
import '../screens/membership_screen.dart';
import '../screens/order_history_screen.dart';
import '../services/membership_service.dart';
import '../services/supabase_service.dart';
import '../utils/format_id.dart';

/// Kartu status member di Profil: tingkat asli dari database, masa berlaku,
/// jumlah pesanan asli. Mengetuk kartu membuka halaman Langganan.
class MembershipCard extends StatefulWidget {
  const MembershipCard({super.key});

  @override
  State<MembershipCard> createState() => _MembershipCardState();
}

class _MembershipCardState extends State<MembershipCard> {
  MembershipState? _state;
  int? _orders;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await MembershipService().fetchState();
      if (mounted) setState(() => _state = s);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      final list = await SupabaseService().fetchUserOrders(uid);
      if (mounted) setState(() => _orders = list.length);
    }
  }

  Future<void> _open() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final active = s?.active;
    final plan = s?.planOf(active);
    final pending = s?.pending;
    final colors = plan == null
        ? const [Color(0xFF0066CC), Color(0xFF0284C7)]
        : [plan.color, Color.lerp(plan.color, Colors.black, 0.25)!];

    final title = plan != null
        ? 'Member ${plan.name}'
        : pending != null
            ? 'Menunggu konfirmasi'
            : 'Belum berlangganan';
    final chip = active != null
        ? 'Aktif s.d ${tanggal(active.endsAt!)}'
        : pending != null
            ? 'Diproses admin'
            : (_failed ? 'Ketuk untuk coba lagi' : 'Lihat paket');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text(chip,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.white24),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat(
                    _orders == null ? '–' : '$_orders',
                    'Total Order',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderHistoryScreen())),
                  ),
                  Container(width: 1, height: 26, color: Colors.white24),
                  _stat(
                    plan == null ? '–' : (plan.freeDeliveryQuota == null ? '∞' : '${(plan.freeDeliveryQuota! - active!.freeDeliveryUsed).clamp(0, 999)}'),
                    'Gratis Ongkir',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label, {VoidCallback? onTap}) {
    final child = Column(
      children: [
        Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
    return onTap == null
        ? child
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: child),
          );
  }
}
