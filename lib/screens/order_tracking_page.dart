import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'home_screen.dart';

class OrderTrackingPage extends StatefulWidget {
  final String orderId;

  const OrderTrackingPage({super.key, required this.orderId});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final Animation<double> _pulseAnimation;

  // Color palette – home screen theme
  static const _blue = Color(0xFF0077E6);
  static const _blueLight = Color(0xFFEFF6FF);
  static const _surface = Color(0xFFF8FAFC);
  static const _white = Colors.white;
  static const _textDark = Color(0xFF0F172A);
  static const _textMid = Color(0xFF334155);
  static const _textLight = Color(0xFF64748B);
  static const _textHint = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bgOuter = Color(0xFFEDF2F7);

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget _staggered({required int index, required Widget child}) {
    final begin = (index * 0.12).clamp(0.0, 0.7);
    final end = (begin + 0.35).clamp(0.0, 1.0);
    final slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
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
    final orderId = widget.orderId.toUpperCase().substring(
      0,
      math.min(8, widget.orderId.length),
    );
    return Scaffold(
      backgroundColor: _bgOuter,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            color: _surface,
            child: Column(
              children: [
                _buildHeader(orderId),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      children: [
                        _staggered(index: 0, child: _buildStatusCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 1, child: _buildDriverCard()),
                        const SizedBox(height: 16),
                        _staggered(index: 2, child: _buildLiveProgressCard()),
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

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  // ══════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════
  Widget _buildHeader(String orderId) {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _white,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  _goToHome();
                }
              },
              icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
            ),
            Expanded(
              child: Text(
                'Pesanan #$orderId',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_horiz_rounded, color: _textMid),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  STATUS CARD (spinning washer)
  // ══════════════════════════════════════════
  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _blue.withValues(alpha: 0.05),
            blurRadius: 30,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSpinningWasher(),
          const SizedBox(height: 16),
          Text(
            'ESTIMASI WAKTU',
            style: GoogleFonts.plusJakartaSans(
              color: _textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '14',
                style: GoogleFonts.plusJakartaSans(
                  color: _textDark,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'mnt',
                style: GoogleFonts.plusJakartaSans(
                  color: _textLight,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatusBadge(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 20),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                _statItem('Berat', '6.5 kg'),
                _statItem('Suhu', '40°C'),
                _statItem('Siklus', 'Normal'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinningWasher() {
    return AnimatedBuilder(
      animation: Listenable.merge([_spinController, _pulseAnimation]),
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring
            Container(
              width: 140 + (8 * _pulseAnimation.value),
              height: 140 + (8 * _pulseAnimation.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _blue.withValues(alpha: 0.18 * _pulseAnimation.value),
                  width: 2,
                ),
              ),
            ),
            // Spinning progress ring
            Transform.rotate(
              angle: _spinController.value * 2 * math.pi,
              child: Container(
                width: 126,
                height: 126,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    startAngle: 0,
                    endAngle: math.pi * 2,
                    colors: [
                      _blue,
                      const Color(0xFF38BDF8),
                      _blue.withValues(alpha: 0.3),
                      Colors.transparent,
                      Colors.transparent,
                      _blue.withValues(alpha: 0.15),
                    ],
                    stops: const [0.0, 0.15, 0.35, 0.5, 0.85, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(alpha: 0.25),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            // Inner circle with icon
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blueLight,
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withValues(alpha: 0.15),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_laundry_service_rounded,
                color: _blue,
                size: 44,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _blueLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 10 * _pulseAnimation.value,
                    height: 10 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue.withValues(
                        alpha: 0.35 * (1 - _pulseAnimation.value),
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Sedang Dicuci',
            style: GoogleFonts.plusJakartaSans(
              color: _blue,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: _textHint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              color: _textDark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  DRIVER CARD
  // ══════════════════════════════════════════
  Widget _buildDriverCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuDNbFdVaqA_8R8o2B2bgNohvcDFNa6KRk0P-mMVAQ-g5m4Cl4t1f43n_V4b8c63c8gu7FaQqJH-G2yFe6luDuDMjF7AhoumW2U7Xm_J6v8edNmUTOO669GZ9mvFxfn0GjmAKIHDlTqQxfBmRRANyG6inXudEjrbjlta0Sd2fOXWHUUUAnjGvMibz4c_zFVgrcW89DqqIQawXnBeAIpTyEV6o1dpv4RMaWZwWqvD46qeedv2d-TIw_6IKh6ZEOOD7HgCKHRVYgSPvjg',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blueLight,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: _blue,
                      size: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: _white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Budi Santoso',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFD97706),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '4.9 • Honda Beat B 1234 CD',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: _blue.withValues(alpha: 0.3), blurRadius: 12),
              ],
            ),
            child: IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.chat_bubble_rounded,
                color: _white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  LIVE PROGRESS CARD
  // ══════════════════════════════════════════
  Widget _buildLiveProgressCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progres Langsung',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _blueLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _blue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Aktif',
                  style: GoogleFonts.plusJakartaSans(
                    color: _blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTimelineItem(
            icon: Icons.check_circle_rounded,
            title: 'Kurir Menuju Lokasi',
            subtitle: '10:30 • Selesai',
            status: _StepStatus.completed,
            isFirst: true,
          ),
          _buildTimelineItem(
            icon: Icons.scale_rounded,
            title: 'Proses Penimbangan',
            subtitle: '10:45 • 6.5kg Terverifikasi',
            status: _StepStatus.completed,
          ),
          _buildTimelineItem(
            icon: Icons.local_laundry_service_rounded,
            title: 'Sedang Dicuci (65%)',
            subtitle: 'Mesin #2 • Est. 14 mnt lagi',
            status: _StepStatus.active,
            progressValue: 0.65,
          ),
          _buildTimelineItem(
            icon: Icons.iron_rounded,
            title: 'Proses Setrika',
            subtitle: 'Menunggu',
            status: _StepStatus.pending,
          ),
          _buildTimelineItem(
            icon: Icons.local_shipping_rounded,
            title: 'Siap Diantar',
            subtitle: 'Est. 14:00 WIB',
            status: _StepStatus.pending,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required _StepStatus status,
    double? progressValue,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isCompleted = status == _StepStatus.completed;
    final isActive = status == _StepStatus.active;
    final isPending = status == _StepStatus.pending;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 42,
            child: Column(
              children: [
                // Icon circle
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? _blue
                        : isCompleted
                        ? _blueLight
                        : const Color(0xFFF1F5F9),
                    border: Border.all(
                      color: isActive || isCompleted ? _blue : _border,
                      width: isActive ? 2 : 1,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ]
                        : isCompleted
                        ? [
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: isActive
                      ? AnimatedBuilder(
                          animation: _spinController,
                          builder: (context, child) => Transform.rotate(
                            angle: _spinController.value * 2 * math.pi,
                            child: Icon(icon, color: _white, size: 18),
                          ),
                        )
                      : Icon(
                          icon,
                          color: isCompleted ? _blue : _textHint,
                          size: 18,
                        ),
                ),
                // Connecting line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isCompleted || isActive
                            ? _blue.withValues(alpha: 0.4)
                            : _border,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 4),
              child: Opacity(
                opacity: isPending ? 0.45 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        color: isActive
                            ? _textDark
                            : isCompleted
                            ? _textLight
                            : _textMid,
                        fontSize: isActive ? 15 : 14,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: _textHint,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: isActive ? _blue : _textHint,
                        fontSize: 12,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (progressValue != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progressValue,
                          minHeight: 6,
                          backgroundColor: _border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _blue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: _white,
        border: Border(top: BorderSide(color: _border)),
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
                      'Menghubungkan ke layanan bantuan kurir Washora...',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.headset_mic_rounded, size: 18, color: Colors.white),
              label: Text(
                'Bantuan Kurir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
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

// ── Step status enum ──
enum _StepStatus { completed, active, pending }
