import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../services/supabase_service.dart';
import '../widgets/order_evidence_section.dart';
import 'home_screen.dart';

class DropoffTrackingPage extends StatefulWidget {
  final String orderId;

  const DropoffTrackingPage({super.key, required this.orderId});

  @override
  State<DropoffTrackingPage> createState() => _DropoffTrackingPageState();
}

class _DropoffTrackingPageState extends State<DropoffTrackingPage>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final Animation<double> _pulseAnimation;
  bool _copied = false;

  // ── Color Theme (Consistent with Washora Light Theme) ──
  static const Color _primaryBlue = Color(0xFF0077E6);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _bgCanvas = Color(0xFFEDF2F7);
  static const Color _textDark = Color(0xFF0F172A);
  static const Color _textMid = Color(0xFF334155);
  static const Color _textLight = Color(0xFF64748B);
  static const Color _textHint = Color(0xFF94A3B8);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _successGreen = Color(0xFF16A34A);
  static const Color _dangerRed = Color(0xFFDC2626);

  // Data pesanan realtime + data outlet tujuan dari Supabase
  final SupabaseService _supabaseService = SupabaseService();
  OrderModel? _order;
  ShopModel? _shop;
  bool _isLoading = true;
  StreamSubscription<OrderModel?>? _orderSub;
  Timer? _reconnectTimer;

  void _subscribeOrder() {
    _orderSub?.cancel();
    _orderSub = _supabaseService.watchOrder(widget.orderId).listen(
      (order) {
        if (!mounted) return;
        final needsShop = _shop == null && order != null && order.shopId.isNotEmpty;
        setState(() {
          _order = order;
          _isLoading = false;
        });
        if (needsShop) _loadShop(order.shopId);
      },
      onError: (e) {
        print('Error watchOrder: $e');
        if (!mounted) return;
        setState(() => _isLoading = false);
        // Koneksi realtime terputus: sambung ulang otomatis
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _subscribeOrder();
        });
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribeOrder();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _orderSub?.cancel();
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadShop(String shopId) async {
    final shop = await _supabaseService.getShopById(shopId);
    if (mounted && shop != null) setState(() => _shop = shop);
  }

  /// Langkah timeline drop-off yang sedang aktif (0-3); 4 = semua selesai.
  /// Outlet tidak punya status "diterima kasir" terpisah, jadi begitu mitra
  /// mulai mencuci, langkah 1 & 2 dianggap selesai.
  int get _dropoffStep {
    switch (_order?.status) {
      case 'washing':
      case 'drying':
        return 2;
      case 'done':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  String get _cleanCode {
    final raw = widget.orderId.toUpperCase().replaceAll('-', '');
    final part = raw.length > 6 ? raw.substring(0, 6) : raw;
    return 'DRP-$part';
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _cleanCode));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              'Kode Drop-off $_cleanCode berhasil disalin!',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  Widget _staggered({required int index, required Widget child}) {
    final begin = (index * 0.12).clamp(0.0, 0.7);
    final end = (begin + 0.35).clamp(0.0, 1.0);
    final slide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      ),
    );
    return SlideTransition(
      position: slide,
      child: FadeTransition(opacity: fade, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            color: _surface,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: _primaryBlue))
                      : _order == null
                          ? _buildNotFound()
                          : SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Tiket & panduan hanya relevan selama cucian belum diserahkan
                                  if (!_order!.isCancelled && _dropoffStep == 0) ...[
                                    _staggered(index: 0, child: _buildDropoffTicketCard()),
                                    const SizedBox(height: 16),
                                  ],
                                  _staggered(index: 1, child: _buildStatusCard()),
                                  const SizedBox(height: 16),
                                  _staggered(index: 2, child: _buildOutletCard()),
                                  const SizedBox(height: 16),
                                  // Kode serah terima, foto bukti & klaim kerusakan
                                  OrderEvidenceSection(order: _order!),
                                  if (!_order!.isCancelled)
                                    _staggered(index: 3, child: _buildTimelineCard()),
                                  if (!_order!.isCancelled && _dropoffStep == 0) ...[
                                    const SizedBox(height: 16),
                                    _staggered(index: 4, child: _buildGuidanceCard()),
                                  ],
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                ),
                _buildBottomActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  1. APP HEADER
  // ═══════════════════════════════════════════════
  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _goToHome,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: _textDark, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Tiket Drop-off Outlet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                  Text(
                    'Pesanan #${widget.orderId.toUpperCase().substring(0, math.min(8, widget.orderId.length))}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Butuh bantuan? Silakan hubungi kasir outlet atau layanan pelanggan Washora.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.help_outline_rounded, color: _textMid, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  2. DROPOFF TICKET & BARCODE CARD
  // ═══════════════════════════════════════════════
  Widget _buildDropoffTicketCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0077E6), Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(21),
                topRight: Radius.circular(21),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'KODE TIKET PENYERAHAN OUTLET',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Aktif',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Tunjukkan kode atau barcode ini ke kasir outlet:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textLight,
                  ),
                ),
                const SizedBox(height: 12),

                // Prominent Code Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _cleanCode,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.0,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _copyToClipboard,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _copied ? _successGreen : _primaryBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _copied ? Icons.check_rounded : Icons.copy_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Simulated Barcode
                _buildBarcodeDisplay(),

                const SizedBox(height: 12),
                Text(
                  '*Kasir akan memindai atau mengetik kode di atas untuk verifikasi barang',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: _textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(42, (i) {
                // Procedural widths mimicking standard barcode
                final widths = [2.0, 1.0, 3.0, 1.0, 4.0, 1.5, 2.5, 1.0];
                final width = widths[i % widths.length];
                final isSpace = (i % 7 == 3 || i % 11 == 2);
                return Container(
                  width: width,
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  color: isSpace ? Colors.transparent : const Color(0xFF0F172A),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _cleanCode.replaceAll('-', ' '),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 4.0,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  3. STATUS OVERVIEW CARD
  // ═══════════════════════════════════════════════
  String _formatRupiah(int amount) =>
      'Rp ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 56, color: _textHint),
            const SizedBox(height: 12),
            Text(
              'Pesanan tidak ditemukan',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark),
            ),
            const SizedBox(height: 6),
            Text(
              'Pesanan ini tidak ada atau bukan milik akun yang sedang login.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textLight),
            ),
          ],
        ),
      ),
    );
  }

  /// (warna aksen, label kecil, judul, keterangan, ikon) sesuai status pesanan
  (Color, String, String, String, IconData) get _statusInfo {
    final order = _order!;
    if (order.isCancelled) {
      return (
        _dangerRed,
        'Dibatalkan',
        'Pesanan Dibatalkan',
        'Dibatalkan oleh outlet. Hubungi outlet jika ada pertanyaan.',
        Icons.cancel_rounded,
      );
    }
    switch (_dropoffStep) {
      case 2:
        return (
          _primaryBlue,
          'Sedang Diproses',
          order.status == 'drying' ? 'Pengeringan & Setrika' : 'Cucian Sedang Dicuci',
          'Outlet sedang mengerjakan cucian Anda',
          Icons.local_laundry_service_rounded,
        );
      case 3:
        return (
          _successGreen,
          'Siap Diambil',
          'Cucian Siap Diambil',
          'Ambil di outlet sesuai jam operasional',
          Icons.inventory_2_rounded,
        );
      case 4:
        return (
          _successGreen,
          'Selesai',
          'Pesanan Selesai',
          'Cucian sudah diambil. Terima kasih!',
          Icons.check_circle_rounded,
        );
      default:
        return (
          const Color(0xFFD97706),
          'Menunggu Drop-off',
          'Silakan Antar ke Outlet',
          'Bawa pakaian Anda sebelum jam tutup outlet',
          Icons.storefront_rounded,
        );
    }
  }

  Widget _buildStatusCard() {
    final (accent, label, title, subtitle, icon) = _statusInfo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Store Icon with gentle pulsing glow
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3 * _pulseAnimation.value),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15 * _pulseAnimation.value),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: accent,
                      size: 28,
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: _textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 16),

          // 3 specs row
          Row(
            children: [
              _buildStatItem('Metode', 'Drop-off Mandiri', Icons.directions_walk_rounded),
              _buildDivider(),
              _buildStatItem('Biaya Antar', 'Bebas Biaya', Icons.savings_rounded),
              _buildDivider(),
              _buildStatItem('Total', _formatRupiah(_order!.totalPrice), Icons.receipt_long_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: _primaryBlue),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _textHint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFFF1F5F9),
    );
  }

  // ═══════════════════════════════════════════════
  //  4. OUTLET INFORMATION CARD
  // ═══════════════════════════════════════════════
  Widget _buildOutletCard() {
    final shopName = _shop?.name ?? (_order!.shopName.isEmpty ? 'Outlet Laundry' : _order!.shopName);
    final address = _shop?.address ?? '';
    final openHours = _shop?.openHours ?? '';
    final rating = _shop?.rating ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lokasi Outlet Tujuan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      'Buka Sekarang',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Icon(
                  Icons.store_mall_directory_rounded,
                  color: Color(0xFF16A34A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    if (rating > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 3),
                          Text(
                            rating.toStringAsFixed(1),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _textLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textMid,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (openHours.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Jam Layanan Kasir: $openHours',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _primaryBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action Buttons: Petunjuk Arah & Hubungi Kasir
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Membuka navigasi Google Maps menuju $shopName...',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.directions_rounded, size: 16, color: _primaryBlue),
                  label: Text(
                    'Petunjuk Arah',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _primaryBlue,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    backgroundColor: const Color(0xFFF0F7FF),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Menghubungi kasir $shopName...',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Color(0xFF0F172A)),
                  label: Text(
                    'Hubungi Kasir',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _border),
                    backgroundColor: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  5. TIMELINE STATUS DROPOFF
  // ═══════════════════════════════════════════════
  Widget _buildTimelineCard() {
    final current = _dropoffStep;
    const steps = [
      ('Siap Diantar ke Outlet', 'Bawa pakaian kotor ke outlet dan tunjukkan tiket ini ke kasir.'),
      ('Diterima Kasir & Ditimbang', 'Kasir memeriksa pakaian dan mencocokkan berat cucian Anda.'),
      ('Proses Pencucian & Setrika', 'Cucian diproses secara higienis menggunakan deterjen & pewangi premium.'),
      ('Selesai & Siap Diambil di Outlet', 'Cucian wangi & rapi siap diambil kembali di outlet.'),
    ];
    String timeLabel(int i) {
      if (i < current) return 'Selesai';
      if (i == current) return 'Sekarang';
      return 'Menunggu';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tahapan Pesanan Drop-off',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
              Text(
                current >= steps.length ? 'Semua Selesai' : 'Langkah ${current + 1} dari ${steps.length}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: current >= steps.length ? _successGreen : _primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          for (var i = 0; i < steps.length; i++)
            _buildStep(
              stepNumber: i + 1,
              title: steps[i].$1,
              subtitle: steps[i].$2,
              time: timeLabel(i),
              isActive: i == current,
              isCompleted: i < current,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required int stepNumber,
    required String title,
    required String subtitle,
    required String time,
    required bool isActive,
    required bool isCompleted,
    required bool isLast,
  }) {
    final Color circleColor = isCompleted
        ? _successGreen
        : isActive
            ? _primaryBlue
            : const Color(0xFFF1F5F9);

    final Color iconTextColor = (isCompleted || isActive) ? Colors.white : _textHint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step indicator column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: _primaryBlue.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                        : Text(
                            '$stepNumber',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: iconTextColor,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isCompleted ? _successGreen : _border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Content column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          color: isActive ? _textDark : _textMid,
                        ),
                      ),
                      Text(
                        time,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive ? _primaryBlue : _textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: _textLight,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  6. GUIDANCE TIPS
  // ═══════════════════════════════════════════════
  Widget _buildGuidanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFEF3C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Text(
                'Panduan Praktis Drop-off Mandiri',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTipItem('Periksa saku pakaian Anda untuk memastikan tidak ada barang berharga atau uang.'),
          _buildTipItem('Sebutkan jika ada noda membandel atau pakaian yang memerlukan penanganan khusus ke kasir.'),
          _buildTipItem('Simpan kode drop-off ini untuk verifikasi saat mengambil pakaian bersih Anda.'),
        ],
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF78350F),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  7. BOTTOM ACTION BUTTONS
  // ═══════════════════════════════════════════════
  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _goToHome,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Kembali ke Beranda',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Menghubungkan ke layanan bantuan Washora...',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.support_agent_rounded, size: 18, color: Colors.white),
              label: Text(
                'Bantuan Kasir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
