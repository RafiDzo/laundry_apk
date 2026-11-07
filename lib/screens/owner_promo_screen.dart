import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/shop_model.dart';
import '../models/shop_promo_model.dart';
import '../services/promo_service.dart';
import '../widgets/quick_snackbar.dart';

class OwnerPromoScreen extends StatefulWidget {
  final ShopModel shop;

  const OwnerPromoScreen({super.key, required this.shop});

  @override
  State<OwnerPromoScreen> createState() => _OwnerPromoScreenState();
}

class _OwnerPromoScreenState extends State<OwnerPromoScreen> {
  final PromoService _promoService = PromoService();
  String _selectedFilter = 'Semua';

  // State lokal fallback jika realtime belum mengalir
  List<ShopPromoModel> _promos = [];
  bool _isLoading = true;
  StreamSubscription<List<ShopPromoModel>>? _sub;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  void _startStream() {
    _sub?.cancel();
    _sub = _promoService.streamShopPromos(widget.shop.id).listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _promos = data;
          _isLoading = false;
        });
      },
      onError: (e) async {
        print('Error stream promo: $e');
        final fallback = await _promoService.getShopPromos(widget.shop.id);
        if (!mounted) return;
        setState(() {
          _promos = fallback;
          _isLoading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<ShopPromoModel> get _filteredPromos {
    switch (_selectedFilter) {
      case 'Aktif':
        return _promos.where((p) => p.isRunningNow).toList();
      case 'Akan Datang':
        return _promos.where((p) => p.isUpcoming).toList();
      case 'Nonaktif / Berakhir':
        return _promos.where((p) => !p.isActive || p.isExpired || p.isQuotaExhausted).toList();
      default:
        return _promos;
    }
  }

  int get _activeCount => _promos.where((p) => p.isRunningNow).length;
  int get _totalClaims => _promos.fold<int>(0, (sum, p) => sum + p.usedCount);
  int get _endingSoonCount {
    final now = DateTime.now();
    final in3Days = now.add(const Duration(days: 3));
    return _promos.where((p) => p.isRunningNow && p.endAt != null && p.endAt!.isBefore(in3Days)).length;
  }

  Future<void> _togglePromo(ShopPromoModel promo, bool val) async {
    try {
      await _promoService.togglePromoStatus(promo.id, val);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(
          content: Text(val ? 'Promo "${promo.title}" diaktifkan' : 'Promo "${promo.title}" dinonaktifkan'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(
          content: Text('Gagal mengubah status: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deletePromo(ShopPromoModel promo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Hapus Promo?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'Promo "${promo.title}" akan dihapus permanen dan tidak dapat digunakan pelanggan lagi.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _promoService.deletePromo(promo.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showQuickSnackBar(
          const SnackBar(
            content: Text('Promo berhasil dihapus'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showQuickSnackBar(
          SnackBar(
            content: Text('Gagal menghapus promo: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openPromoForm({ShopPromoModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PromoFormSheet(
        shop: widget.shop,
        existing: existing,
        onSaved: () {
          // Stream akan update otomatis
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kelola Promo & Diskon',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF0F172A),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.shop.name,
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Panduan Promo',
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF0077E6)),
            onPressed: _showGuideDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF0077E6),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF0077E6),
                  onRefresh: () async {
                    final data = await _promoService.getShopPromos(widget.shop.id);
                    if (mounted) setState(() => _promos = data);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      _buildSummaryKPI(),
                      const SizedBox(height: 18),
                      _buildFilterTabs(),
                      const SizedBox(height: 14),
                      if (_filteredPromos.isEmpty)
                        _buildEmptyState()
                      else
                        ..._filteredPromos.map((p) => _buildPromoCard(p)),
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _openPromoForm(),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: Text(
                'Buat Promo Baru',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0077E6),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF0077E6).withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  1. SUMMARY KPI
  // ═══════════════════════════════════════════════
  Widget _buildSummaryKPI() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildKpiItem('Aktif', '$_activeCount', const Color(0xFF10B981), Icons.bolt_rounded),
          Container(width: 1, height: 36, color: const Color(0xFFF1F5F9)),
          _buildKpiItem('Total Klaim', '$_totalClaims', const Color(0xFF0077E6), Icons.local_activity_rounded),
          Container(width: 1, height: 36, color: const Color(0xFFF1F5F9)),
          _buildKpiItem('Habis Segera', '$_endingSoonCount', const Color(0xFFF59E0B), Icons.timer_outlined),
        ],
      ),
    );
  }

  Widget _buildKpiItem(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  2. FILTER TABS
  // ═══════════════════════════════════════════════
  Widget _buildFilterTabs() {
    final filters = ['Semua', 'Aktif', 'Akan Datang', 'Nonaktif / Berakhir'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                f,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF0077E6) : const Color(0xFF64748B),
                ),
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedFilter = f),
              selectedColor: const Color(0xFFEFF6FF),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  3. PROMO TICKET CARD
  // ═══════════════════════════════════════════════
  Widget _buildPromoCard(ShopPromoModel promo) {
    final isRunning = promo.isRunningNow;
    final color = promo.type.color;
    final lightColor = promo.type.lightColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRunning ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: isRunning ? 0.05 : 0.02),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar Kartu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                // Badge Kategori
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: lightColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(promo.type.icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        promo.type.shortLabel,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Badge Status
                if (!promo.isActive)
                  _buildStatusChip('NONAKTIF', const Color(0xFF64748B), const Color(0xFFF1F5F9))
                else if (promo.isExpired)
                  _buildStatusChip('KEDALUWARSA', const Color(0xFFEF4444), const Color(0xFFFEE2E2))
                else if (promo.isQuotaExhausted)
                  _buildStatusChip('KUOTA HABIS', const Color(0xFFF59E0B), const Color(0xFFFEF3C7))
                else if (promo.isUpcoming)
                  _buildStatusChip('AKAN DATANG', const Color(0xFF0284C7), const Color(0xFFE0F2FE))
                else
                  _buildStatusChip('AKTIF', const Color(0xFF10B981), const Color(0xFFECFDF5)),

                const Spacer(),

                // Toggle Switch
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: promo.isActive,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF0077E6),
                    inactiveThumbColor: const Color(0xFF94A3B8),
                    inactiveTrackColor: const Color(0xFFE2E8F0),
                    onChanged: (val) => _togglePromo(promo, val),
                  ),
                ),

                // Menu Titik Tiga
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF94A3B8)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'edit') _openPromoForm(existing: promo);
                    if (val == 'delete') _deletePromo(promo);
                    if (val == 'copy_code' && promo.code != null) {
                      Clipboard.setData(ClipboardData(text: promo.code!));
                      ScaffoldMessenger.of(context).showQuickSnackBar(
                        const SnackBar(
                          content: Text('Kode voucher disalin ke clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (promo.code != null)
                      PopupMenuItem(
                        value: 'copy_code',
                        child: Row(
                          children: [
                            const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Text('Salin Kode', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text('Edit Promo', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text('Hapus Promo', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFFEF4444))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Judul & Nilai Diskon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        promo.summaryDescription,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  promo.valueDisplay,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Kode Voucher Pill (jika ada)
          if (promo.code != null && promo.code!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.confirmation_number_outlined, size: 13, color: Color(0xFF0077E6)),
                    const SizedBox(width: 6),
                    Text(
                      'KODE: ${promo.code}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: const Color(0xFF0077E6),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Divider tiket halus
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 1, color: const Color(0xFFF1F5F9)),
          ),

          // Footer: Kuota & Periode
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Kuota
                Row(
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      promo.isUnlimitedQuota
                          ? '${promo.usedCount} klaim (Tanpa Batas)'
                          : '${promo.usedCount}/${promo.quota} klaim',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),

                // Masa Berlaku
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateRange(promo.startAt, promo.endAt),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime? end) {
    String d(DateTime t) => '${t.day}/${t.month}';
    if (end == null) return 'Mulai ${d(start)} (Seterusnya)';
    return '${d(start)} – ${d(end)}';
  }

  // ═══════════════════════════════════════════════
  //  4. EMPTY STATE
  // ═══════════════════════════════════════════════
  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.loyalty_rounded, size: 32, color: Color(0xFF0077E6)),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum Ada Promo di Kategori Ini',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Buat promo diskon atau voucher gratis ongkir untuk menarik lebih banyak pelanggan ke outletmu.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _openPromoForm(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Buat Promo Sekarang'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0077E6),
              side: const BorderSide(color: Color(0xFF93C5FD)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.tips_and_updates_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Text(
              'Tips Promo Efektif',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _guideItem('1. Diskon Persen (10-25%)', 'Cocok untuk menarik pelanggan baru saat hari biasa.'),
              _guideItem('2. Gratis Ongkir Antar-Jemput', 'Sangat efektif meningkatkan pesanan di atas Rp 40.000.'),
              _guideItem('3. Batasi Kuota Klaim', 'Misal 30 klaim pertama, agar pelanggan terdorong segera order.'),
              _guideItem('4. Promo Jam Sepi (Flash)', 'Buat diskon khusus malam atau hari kerja untuk meratakan antrean.'),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077E6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Widget _guideItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(desc, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  5. FORM BOTTOM SHEET (BUAT & EDIT PROMO)
// ═══════════════════════════════════════════════════
class _PromoFormSheet extends StatefulWidget {
  final ShopModel shop;
  final ShopPromoModel? existing;
  final VoidCallback onSaved;

  const _PromoFormSheet({
    required this.shop,
    this.existing,
    required this.onSaved,
  });

  @override
  State<_PromoFormSheet> createState() => _PromoFormSheetState();
}

class _PromoFormSheetState extends State<_PromoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final PromoService _promoService = PromoService();

  late ShopPromoType _type;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _maxSavingCtrl;
  late final TextEditingController _minOrderCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _quotaCtrl;

  late bool _hasCode;
  late bool _hasQuota;
  late DateTime _startDate;
  DateTime? _endDate;
  late List<String> _selectedServiceIds;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _type = p?.type ?? ShopPromoType.discountPct;
    _hasCode = p?.code != null;
    _hasQuota = p?.quota != null;
    _startDate = p?.startAt ?? DateTime.now();
    _endDate = p?.endAt;
    _selectedServiceIds = List.of(p?.serviceIds ?? []);

    _titleCtrl = TextEditingController(text: p?.title ?? '');
    _valueCtrl = TextEditingController(text: p != null ? '${p.value}' : '20');
    _maxSavingCtrl = TextEditingController(
      text: (p?.maxSaving != null && p!.maxSaving > 0) ? '${p.maxSaving}' : '',
    );
    _minOrderCtrl = TextEditingController(
      text: (p?.minOrder != null && p!.minOrder > 0) ? '${p.minOrder}' : '25000',
    );
    _codeCtrl = TextEditingController(text: p?.code ?? '');
    final quotaVal = p?.quota;
    _quotaCtrl = TextEditingController(text: quotaVal != null ? '$quotaVal' : '50');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _valueCtrl.dispose();
    _maxSavingCtrl.dispose();
    _minOrderCtrl.dispose();
    _codeCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate ?? _startDate.add(const Duration(days: 14)),
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0077E6),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final title = _titleCtrl.text.trim();
    final val = int.tryParse(_valueCtrl.text.replaceAll('.', '')) ?? 0;
    final maxSaving = int.tryParse(_maxSavingCtrl.text.replaceAll('.', '')) ?? 0;
    final minOrder = int.tryParse(_minOrderCtrl.text.replaceAll('.', '')) ?? 0;
    final code = _hasCode && _codeCtrl.text.trim().isNotEmpty ? _codeCtrl.text.trim().toUpperCase() : null;
    final quota = _hasQuota ? int.tryParse(_quotaCtrl.text.replaceAll('.', '')) : null;

    try {
      if (widget.existing != null) {
        final updated = widget.existing!.copyWith(
          title: title,
          type: _type,
          value: _type == ShopPromoType.freeDelivery ? 0 : val,
          maxSaving: _type == ShopPromoType.discountPct ? maxSaving : 0,
          minOrder: minOrder,
          code: code,
          quota: quota,
          startAt: _startDate,
          endAt: _endDate,
          serviceIds: _selectedServiceIds,
        );
        await _promoService.updatePromo(updated);
      } else {
        final newPromo = ShopPromoModel(
          id: '',
          shopId: widget.shop.id,
          title: title,
          type: _type,
          value: _type == ShopPromoType.freeDelivery ? 0 : val,
          maxSaving: _type == ShopPromoType.discountPct ? maxSaving : 0,
          minOrder: minOrder,
          code: code,
          quota: quota,
          startAt: _startDate,
          endAt: _endDate,
          serviceIds: _selectedServiceIds,
        );
        await _promoService.createPromo(newPromo);
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showQuickSnackBar(
          SnackBar(
            content: Text(widget.existing != null ? 'Promo berhasil diperbarui' : 'Promo baru berhasil dibuat!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showQuickSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Modal
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.existing != null ? 'Edit Promo' : 'Buat Promo Baru',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Form scrollable
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // STEP 1: Pilih Tipe Promo
                    _buildSectionTitle('1. Pilih Jenis Promo'),
                    const SizedBox(height: 10),
                    _buildTypeSelector(),

                    const SizedBox(height: 22),

                    // STEP 2: Detail Promo
                    _buildSectionTitle('2. Rincian Promo'),
                    const SizedBox(height: 10),
                    _buildTextField(
                      controller: _titleCtrl,
                      label: 'Nama / Judul Promo',
                      hint: 'Mis. Diskon Gajian 20%',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                    ),

                    if (_type != ShopPromoType.freeDelivery) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _valueCtrl,
                              label: _type == ShopPromoType.discountPct ? 'Besar Diskon (%)' : 'Potongan (Rp)',
                              hint: _type == ShopPromoType.discountPct ? '20' : '10000',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Wajib';
                                final n = int.tryParse(v);
                                if (n == null || n <= 0) return 'Tidak valid';
                                if (_type == ShopPromoType.discountPct && n > 100) return 'Maks 100%';
                                return null;
                              },
                            ),
                          ),
                          if (_type == ShopPromoType.discountPct) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                controller: _maxSavingCtrl,
                                label: 'Maks. Diskon (Rp)',
                                hint: '25000 (0=unlimited)',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _minOrderCtrl,
                      label: 'Minimal Transaksi (Rp)',
                      hint: '0 (Tanpa minimal order)',
                      keyboardType: TextInputType.number,
                    ),

                    const SizedBox(height: 22),

                    // STEP 3: Kuota & Kode
                    _buildSectionTitle('3. Kuota & Kode Voucher'),
                    const SizedBox(height: 10),

                    // Toggle Kuota
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Batasi Kuota Klaim',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _hasQuota ? 'Maksimal jumlah pemesanan memakai promo ini' : 'Promo berlaku tanpa batas kuota',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      value: _hasQuota,
                      activeTrackColor: const Color(0xFF0077E6),
                      onChanged: (v) => setState(() => _hasQuota = v),
                    ),
                    if (_hasQuota) ...[
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _quotaCtrl,
                        label: 'Jumlah Kuota',
                        hint: '50',
                        keyboardType: TextInputType.number,
                        validator: (v) => _hasQuota && (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Isi kuota minimal 1' : null,
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Toggle Kode Voucher
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Wajibkan Kode Voucher',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _hasCode ? 'Pelanggan harus memasukkan kode saat checkout' : 'Otomatis aktif tanpa perlu ketik kode',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      value: _hasCode,
                      activeTrackColor: const Color(0xFF0077E6),
                      onChanged: (v) => setState(() => _hasCode = v),
                    ),
                    if (_hasCode) ...[
                      const SizedBox(height: 8),
                      _buildTextField(
                        controller: _codeCtrl,
                        label: 'Kode Voucher (Huruf Besar)',
                        hint: 'HEMAT20',
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => _hasCode && (v == null || v.trim().isEmpty) ? 'Isi kode voucher' : null,
                      ),
                    ],

                    const SizedBox(height: 22),

                    // STEP 4: Masa Berlaku
                    _buildSectionTitle('4. Masa Berlaku'),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickDateRange,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFF0077E6), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Periode Aktif',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _endDate == null
                                        ? '${_startDate.day}/${_startDate.month}/${_startDate.year} – Seterusnya'
                                        : '${_startDate.day}/${_startDate.month}/${_startDate.year} – ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // STEP 5: Layanan yang berlaku
                    _buildSectionTitle('5. Layanan yang Berlaku'),
                    const SizedBox(height: 10),
                    _buildServiceSelector(),

                    const SizedBox(height: 28),

                    // Live Preview Kartu
                    _buildSectionTitle('Preview di Aplikasi Pelanggan'),
                    const SizedBox(height: 10),
                    _buildLivePreviewCard(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom CTA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077E6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.existing != null ? 'Simpan Perubahan' : 'Terbitkan Promo',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.3,
      children: ShopPromoType.values.map((t) {
        final isSelected = _type == t;
        return InkWell(
          onTap: () => setState(() => _type = t),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? t.lightColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? t.color : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(t.icon, size: 18, color: isSelected ? t.color : const Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.shortLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? t.color : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF0F172A)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildServiceSelector() {
    final services = widget.shop.services;
    final isAll = _selectedServiceIds.isEmpty;

    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Berlaku untuk Semua Layanan',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          value: isAll,
          activeColor: const Color(0xFF0077E6),
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _selectedServiceIds.clear();
              } else if (services.isNotEmpty) {
                _selectedServiceIds = [services.first.id];
              }
            });
          },
        ),
        if (!isAll && services.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ...services.map((s) {
            final checked = _selectedServiceIds.contains(s.id);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.name, style: GoogleFonts.plusJakartaSans(fontSize: 12)),
              subtitle: Text(
                'Rp ${s.price} ${s.unit}',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              value: checked,
              activeColor: const Color(0xFF0077E6),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedServiceIds.add(s.id);
                  } else {
                    _selectedServiceIds.remove(s.id);
                  }
                });
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _buildLivePreviewCard() {
    final title = _titleCtrl.text.trim().isNotEmpty ? _titleCtrl.text.trim() : 'Contoh Judul Promo';
    final code = _hasCode && _codeCtrl.text.trim().isNotEmpty ? _codeCtrl.text.trim().toUpperCase() : null;
    final valStr = _type == ShopPromoType.freeDelivery
        ? 'Gratis Ongkir'
        : (_type == ShopPromoType.discountPct ? '${_valueCtrl.text}%' : 'Rp ${_valueCtrl.text}');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _type.lightColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _type.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(_type.icon, color: _type.color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _minOrderCtrl.text.isNotEmpty && _minOrderCtrl.text != '0'
                      ? 'Min. belanja Rp ${_minOrderCtrl.text}'
                      : 'Tanpa minimum transaksi',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                if (code != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      'KODE: $code',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _type.color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            valStr,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _type.color,
            ),
          ),
        ],
      ),
    );
  }
}
