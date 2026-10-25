import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
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
  static const Color _blueLight = Color(0xFFEFF6FF);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _bgCanvas = Color(0xFFEDF2F7);
  static const Color _textDark = Color(0xFF0F172A);
  static const Color _textMid = Color(0xFF334155);
  static const Color _textLight = Color(0xFF64748B);
  static const Color _textHint = Color(0xFF94A3B8);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _successGreen = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
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
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
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
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _staggered(index: 0, child: _buildDropoffTicketCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 1, child: _buildStatusCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 2, child: _buildOutletCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 3, child: _buildTimelineCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 4, child: _buildGuidanceCard()),
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
  Widget _buildStatusCard() {
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
                      color: _blueLight,
                      border: Border.all(
                        color: _primaryBlue.withValues(alpha: 0.3 * _pulseAnimation.value),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryBlue.withValues(alpha: 0.15 * _pulseAnimation.value),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: _primaryBlue,
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
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Menunggu Drop-off',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Silakan Antar ke Outlet',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Bawa pakaian Anda sebelum jam tutup outlet',
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
              _buildStatItem('Estimasi', '24 Jam', Icons.access_time_rounded),
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
                      'Washora CleanPro Kemang',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          '4.9 (1.2k+ ulasan) • 1.2 km dari Anda',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jl. Kemang Raya No. 12A, Mampang Prapatan, Jakarta Selatan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textMid,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jam Layanan Kasir: 08:00 - 21:00 WIB',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _primaryBlue,
                      ),
                    ),
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
                          'Membuka navigasi Google Maps menuju Washora CleanPro Kemang...',
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
                          'Menghubungi kasir outlet di 0812-3456-7890 via WhatsApp...',
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
                'Langkah 1 dari 4',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _buildStep(
            stepNumber: 1,
            title: 'Siap Diantar ke Outlet',
            subtitle: 'Bawa pakaian kotor ke outlet dan tunjukkan tiket ini ke kasir.',
            time: 'Sekarang',
            isActive: true,
            isCompleted: false,
            isLast: false,
          ),
          _buildStep(
            stepNumber: 2,
            title: 'Diterima Kasir & Ditimbang',
            subtitle: 'Kasir memeriksa pakaian dan mencocokkan berat cucian Anda.',
            time: 'Menunggu',
            isActive: false,
            isCompleted: false,
            isLast: false,
          ),
          _buildStep(
            stepNumber: 3,
            title: 'Proses Pencucian & Setrika',
            subtitle: 'Cucian diproses secara higienis menggunakan deterjen & pewangi premium.',
            time: 'Menunggu',
            isActive: false,
            isCompleted: false,
            isLast: false,
          ),
          _buildStep(
            stepNumber: 4,
            title: 'Selesai & Siap Diambil di Outlet',
            subtitle: 'Notifikasi akan dikirim saat cucian wangi & rapi siap diambil kembali.',
            time: 'Estimasi Besok',
            isActive: false,
            isCompleted: false,
            isLast: true,
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
