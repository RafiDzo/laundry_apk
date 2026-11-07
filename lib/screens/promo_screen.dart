import 'membership_screen.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/promo_model.dart';
import '../widgets/quick_snackbar.dart';

const _kPrimary = Color(0xFF0077E6);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kBg = Color(0xFFF4F7FB);

/// Halaman "Promo & Voucher": flash sale, voucher berbentuk tiket,
/// paket langganan, dan input kode promo.
class PromoScreen extends StatefulWidget {
  /// Voucher yang langsung dibuka detailnya (dari banner beranda).
  final String? openPromoId;

  /// true = langsung gulir ke bagian Paket Langganan.
  final bool scrollToPlans;

  const PromoScreen({super.key, this.openPromoId, this.scrollToPlans = false});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  final _codeController = TextEditingController();
  final _plansKey = GlobalKey();
  Set<String> _claimed = {};

  /// null = Semua, 'saved' = Tersimpan, selain itu nama PromoCategory.
  String? _filter;

  @override
  void initState() {
    super.initState();
    PromoWallet.load().then((ids) {
      if (mounted) setState(() => _claimed = ids);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.scrollToPlans && _plansKey.currentContext != null) {
        Scrollable.ensureVisible(
          _plansKey.currentContext!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
      final id = widget.openPromoId;
      if (id != null) {
        final promo = PromoCatalog.all.where((p) => p.id == id);
        if (promo.isNotEmpty) _openDetail(promo.first);
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  int get _potentialSaving => PromoCatalog.all
      .where((p) => _claimed.contains(p.id))
      .fold(0, (sum, p) => sum + p.maxSaving);

  void _toast(String msg, {IconData icon = Icons.check_circle_rounded}) {
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: const Color(0xFF4ADE80), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _claim(Promo p) {
    if (_claimed.contains(p.id)) return;
    HapticFeedback.lightImpact();
    setState(() => _claimed = {..._claimed, p.id});
    PromoWallet.save(_claimed);
    _toast('Voucher ${p.code} berhasil diklaim!');
  }

  void _copy(Promo p) {
    Clipboard.setData(ClipboardData(text: p.code));
    _toast('Kode ${p.code} disalin', icon: Icons.copy_rounded);
  }

  void _redeemCode() {
    final code = _codeController.text;
    if (code.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final promo = PromoCatalog.byCode(code);
    if (promo == null) {
      _toast(
        'Kode "${code.trim().toUpperCase()}" tidak ditemukan',
        icon: Icons.error_outline_rounded,
      );
      return;
    }
    _codeController.clear();
    _claim(promo);
  }

  List<Promo> get _visiblePromos {
    final list = PromoCatalog.regular;
    if (_filter == null) return list;
    if (_filter == 'saved') {
      return PromoCatalog.all.where((p) => _claimed.contains(p.id)).toList();
    }
    return list.where((p) => p.category.name == _filter).toList();
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final promos = _visiblePromos;
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildFlashSale()),
          SliverToBoxAdapter(child: _buildCategoryChips()),
          if (promos.isEmpty)
            SliverToBoxAdapter(child: _buildEmpty())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverList.separated(
                itemCount: promos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _VoucherTicket(
                  promo: promos[i],
                  claimed: _claimed.contains(promos[i].id),
                  onTap: () => _openDetail(promos[i]),
                  onClaim: () => _claim(promos[i]),
                  onCopy: () => _copy(promos[i]),
                ),
              ),
            ),
          SliverToBoxAdapter(child: _buildPlans()),
          SliverToBoxAdapter(child: _buildHowTo()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  HEADER + DOMPET VOUCHER + INPUT KODE
  // ═══════════════════════════════════════════════
  Widget _buildHeader() {
    return Stack(
      children: [
        Container(
          height: 210,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0055B8), Color(0xFF0077E6), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Stack(
            children: [
              _circle(right: -40, top: -30, d: 160, a: 0.10),
              _circle(right: 60, top: 70, d: 40, a: 0.12),
              _circle(left: -30, bottom: -50, d: 120, a: 0.08),
              Positioned(
                right: 18,
                top: 64,
                child: Transform.rotate(
                  angle: -0.25,
                  child: Icon(
                    Icons.local_offer_rounded,
                    size: 84,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Text(
                      'Promo & Voucher',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 0, 16),
                  child: Text(
                    'Cucian bersih, dompet tetap tebal ✨',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildWalletCard(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kInk.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voucher Saya',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _kMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${_claimed.length} ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kInk,
                            ),
                          ),
                          TextSpan(
                            text: 'tersimpan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _kInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Potensi hemat',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: _kMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRupiah(_potentialSaving),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        color: _kMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _redeemCode(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Masukkan kode promo',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _redeemCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Pakai',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circle({
    double? left,
    double? top,
    double? right,
    double? bottom,
    required double d,
    required double a,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: a),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  FLASH SALE
  // ═══════════════════════════════════════════════
  Widget _buildFlashSale() {
    final flash = PromoCatalog.flash;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFF97316),
                  size: 24,
                ),
                const SizedBox(width: 4),
                Text(
                  'Flash Sale',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const Spacer(),
                Text(
                  'Berakhir dalam ',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _kMuted,
                  ),
                ),
                const _Countdown(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: flash.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _FlashCard(
                promo: flash[i],
                claimed: _claimed.contains(flash[i].id),
                onTap: () => _openDetail(flash[i]),
                onClaim: () => _claim(flash[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  KATEGORI
  // ═══════════════════════════════════════════════
  Widget _buildCategoryChips() {
    final items = <(String?, String, IconData)>[
      (null, 'Semua', Icons.apps_rounded),
      ('saved', 'Tersimpan', Icons.bookmark_rounded),
      for (final c in PromoCategory.values) (c.name, c.label, c.icon),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Voucher Untukmu',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kInk,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (key, label, icon) = items[i];
                final active = _filter == key;
                final count = key == 'saved' ? _claimed.length : null;
                return GestureDetector(
                  onTap: () => setState(() => _filter = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: active ? _kPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? _kPrimary : _kBorder),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: active ? Colors.white : _kMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          count != null && count > 0
                              ? '$label ($count)'
                              : label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : _kInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final saved = _filter == 'saved';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          children: [
            Icon(
              saved ? Icons.bookmark_border_rounded : Icons.search_off_rounded,
              size: 44,
              color: const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 10),
            Text(
              saved
                  ? 'Belum ada voucher tersimpan'
                  : 'Belum ada voucher di kategori ini',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _kMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              saved
                  ? 'Tekan "Klaim" pada voucher untuk menyimpannya.'
                  : 'Coba kategori lain, ya.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  PAKET LANGGANAN
  // ═══════════════════════════════════════════════
  Widget _buildPlans() {
    return Padding(
      key: _plansKey,
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipScreen())),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
            child: Row(
              children: [
                for (final c in const [Color(0xFF9A5B2E), Color(0xFF64748B), Color(0xFFB7791F)])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.workspace_premium_rounded, color: c, size: 22),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Langganan Bronze · Silver · Gold',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w800, color: _kInk)),
                      const SizedBox(height: 2),
                      Text('Mulai Rp 19.000/bulan · lihat benefit tiap tingkat',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _kMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  CARA PAKAI
  // ═══════════════════════════════════════════════
  Widget _buildHowTo() {
    const steps = [
      (Icons.touch_app_rounded, 'Klaim', 'Simpan voucher favoritmu'),
      (Icons.local_laundry_service_rounded, 'Pesan', 'Pilih outlet & layanan'),
      (Icons.celebration_rounded, 'Hemat', 'Tunjukkan kode saat bayar'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cara pakai voucher',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _kInk,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _kPrimary.withValues(alpha: 0.15),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(steps[i].$1, color: _kPrimary, size: 20),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${i + 1}. ${steps[i].$2}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          steps[i].$3,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10.5,
                            color: _kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < steps.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Color(0xFF93C5FD),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  DETAIL VOUCHER (BOTTOM SHEET)
  // ═══════════════════════════════════════════════
  void _openDetail(Promo p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final claimed = _claimed.contains(p.id);
          final until = p.validUntil;
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
          final untilText =
              '${until.day} ${months[until.month - 1]} ${until.year}, 23:59';
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header berwarna
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: p.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          p.valueLabel,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                        Text(
                          p.valueCaption,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Kode promo
                        CustomPaint(
                          painter: _DashedBorderPainter(color: p.colors.first),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'KODE PROMO',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          color: _kMuted,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      Text(
                                        p.code,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: _kInk,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _copy(p),
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Salin',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: p.colors.first,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _infoRow(
                          Icons.shopping_bag_outlined,
                          'Min. transaksi',
                          formatRupiah(p.minOrder),
                        ),
                        _infoRow(
                          Icons.event_rounded,
                          'Berlaku sampai',
                          untilText,
                        ),
                        _infoRow(p.category.icon, 'Kategori', p.category.label),
                        _infoRow(
                          Icons.pie_chart_outline_rounded,
                          'Kuota terpakai',
                          '${(p.quotaUsed * 100).round()}%',
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Syarat & Ketentuan',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final t in p.terms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    right: 8,
                                  ),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: p.colors.first,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    t,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      color: const Color(0xFF475569),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: claimed
                              ? () => _copy(p)
                              : () {
                                  _claim(p);
                                  setSheet(() {});
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: claimed
                                ? const Color(0xFF16A34A)
                                : p.colors.first,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                claimed
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                claimed
                                    ? 'Tersimpan · Salin Kode'
                                    : 'Klaim Voucher',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kInk,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  HITUNG MUNDUR FLASH SALE (sampai 23:59:59 hari ini)
// ═══════════════════════════════════════════════════
class _Countdown extends StatefulWidget {
  const _Countdown();

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late Timer _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day + 1);
    if (mounted) setState(() => _left = end.difference(now));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = [
      two(_left.inHours),
      two(_left.inMinutes % 60),
      two(_left.inSeconds % 60),
    ];
    return Row(
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              parts[i],
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (i < parts.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                ':',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
//  KARTU FLASH SALE
// ═══════════════════════════════════════════════════
class _FlashCard extends StatelessWidget {
  final Promo promo;
  final bool claimed;
  final VoidCallback onTap;
  final VoidCallback onClaim;

  const _FlashCard({
    required this.promo,
    required this.claimed,
    required this.onTap,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final left = 1 - promo.quotaUsed;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: promo.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: promo.colors.last.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      promo.valueLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        promo.valueCaption,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  promo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Min. ${formatRupiah(promo.minOrder)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                // Bar sisa kuota
                Stack(
                  children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: promo.quotaUsed.clamp(0.08, 1.0),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Text(
                          left < 0.2
                              ? '🔥 Hampir habis!'
                              : 'Sisa ${(left * 100).round()}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: promo.colors.last,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: claimed ? onTap : onClaim,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: claimed
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.white,
                      foregroundColor: claimed
                          ? Colors.white
                          : promo.colors.last,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      claimed ? 'Tersimpan ✓' : 'Klaim Sekarang',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  VOUCHER BERBENTUK TIKET
// ═══════════════════════════════════════════════════
class _VoucherTicket extends StatelessWidget {
  final Promo promo;
  final bool claimed;
  final VoidCallback onTap;
  final VoidCallback onClaim;
  final VoidCallback onCopy;

  const _VoucherTicket({
    required this.promo,
    required this.claimed,
    required this.onTap,
    required this.onClaim,
    required this.onCopy,
  });

  static const double _stubWidth = 96;

  @override
  Widget build(BuildContext context) {
    final daysLeft = promo.validDays;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: _kInk.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const _TicketClipper(notchX: _stubWidth),
          child: Container(
            height: 118,
            color: Colors.white,
            child: Row(
              children: [
                // Potongan kiri berwarna
                Container(
                  width: _stubWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: promo.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: -18,
                        bottom: -18,
                        child: Icon(
                          promo.category.icon,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  promo.valueLabel,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              promo.valueCaption,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white70,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Garis putus-putus
                CustomPaint(
                  size: const Size(1, double.infinity),
                  painter: _DashedLinePainter(),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: promo.colors.first.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                promo.category.label,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: promo.colors.first,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (daysLeft <= 7)
                              Text(
                                daysLeft == 0
                                    ? 'Berakhir hari ini'
                                    : 'Sisa $daysLeft hari',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          promo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Min. transaksi ${formatRupiah(promo.minOrder)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: onCopy,
                              child: Row(
                                children: [
                                  Text(
                                    promo.code,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _kInk,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: _kMuted,
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 30,
                              child: claimed
                                  ? OutlinedButton.icon(
                                      onPressed: onTap,
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        'Tersimpan',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF16A34A,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFF86EFAC),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: onClaim,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: promo.colors.first,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'Klaim',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  final double notchX;
  const _TicketClipper({required this.notchX});

  @override
  Path getClip(Size size) {
    const r = 10.0;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: r))
      ..addOval(
        Rect.fromCircle(center: Offset(notchX, size.height), radius: r),
      );
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  bool shouldReclip(covariant _TicketClipper old) => old.notchX != notchX;
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2;
    var y = 14.0;
    while (y < size.height - 14) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 5), paint);
      y += 9;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.06));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}

