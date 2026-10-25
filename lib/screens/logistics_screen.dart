import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'payment_method_page.dart';
import '../models/order_model.dart';

class LogisticsScreen extends StatefulWidget {
  final Map<String, dynamic> laundry;
  final List<OrderItem> items;
  final int totalAmount;
  final String notes;

  const LogisticsScreen({
    super.key,
    required this.laundry,
    required this.items,
    required this.totalAmount,
    required this.notes,
  });

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen>
    with SingleTickerProviderStateMixin {
  // Delivery type: 0 = Kurir, 1 = Drop-off
  int _selectedDeliveryType = 0;

  // Schedule
  int _selectedDayIndex = 0;
  int _selectedTimeIndex = 1; // 11:00 default

  late AnimationController _entranceController;

  final List<Map<String, String>> _days = [
    {'day': 'SEN', 'date': '14'},
    {'day': 'SEL', 'date': '15'},
    {'day': 'RAB', 'date': '16'},
    {'day': 'KAM', 'date': '17'},
    {'day': 'JUM', 'date': '18'},
  ];

  final List<Map<String, dynamic>> _timeSlots = [
    {'time': '09:00', 'available': false},
    {'time': '11:00', 'available': true},
    {'time': '13:00', 'available': true},
    {'time': '15:00', 'available': true},
    {'time': '17:00', 'available': true},
    {'time': '19:00', 'available': true},
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Widget _buildStaggeredChild({required int index, required Widget child}) {
    final begin = (index * 0.12).clamp(0.0, 0.7);
    final end = (begin + 0.3).clamp(0.0, 1.0);

    final slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(begin, end, curve: Curves.easeOutCubic),
          ),
        );

    final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      ),
    );

    return SlideTransition(
      position: slideAnimation,
      child: FadeTransition(opacity: fadeAnimation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0EA5E9)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Header
            Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),

            // Scrollable content
            Positioned.fill(
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Spacer for header
                    const SizedBox(height: 56),
                    // Scrollable body
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Opsi Pengiriman
                            _buildStaggeredChild(
                              index: 0,
                              child: _buildDeliveryOptions(),
                            ),
                            const SizedBox(height: 28),

                            // Jadwal Penjemputan
                            _buildStaggeredChild(
                              index: 1,
                              child: _buildScheduleSection(),
                            ),
                            const SizedBox(height: 28),

                            // Estimasi Pengembalian
                            _buildStaggeredChild(
                              index: 2,
                              child: _buildEstimationCard(),
                            ),
                            const SizedBox(height: 28),

                            // Ringkasan Biaya
                            _buildStaggeredChild(
                              index: 3,
                              child: _buildCostSummary(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom button
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(shape: const CircleBorder()),
                  ),
                  Expanded(
                    child: Text(
                      'Pilih Layanan & Waktu',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  OPSI PENGIRIMAN
  // ═══════════════════════════════════════════════
  Widget _buildDeliveryOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opsi Pengiriman',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        // Kurir Antar-Jemput
        _buildDeliveryOption(
          index: 0,
          icon: Icons.two_wheeler,
          title: 'Kurir Antar-Jemput',
          subtitle: 'Kami jemput & antar cucianmu',
        ),
        const SizedBox(height: 12),

        // Drop-off Sendiri
        _buildDeliveryOption(
          index: 1,
          icon: Icons.storefront,
          title: 'Drop-off Sendiri',
          subtitle: 'Antar langsung ke outlet',
        ),
      ],
    );
  }

  Widget _buildDeliveryOption({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedDeliveryType == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedDeliveryType = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.black.withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.2),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF257BF4)
                : Colors.white.withValues(alpha: 0.05),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF257BF4).withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? const Color(0xFF257BF4)
                    : Colors.white.withValues(alpha: 0.1),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF257BF4).withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),

            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? const Color(0xFF257BF4)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF257BF4)
                      : const Color(0xFF64748B).withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  JADWAL PENJEMPUTAN
  // ═══════════════════════════════════════════════
  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jadwal Penjemputan',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        // Day selector (horizontal scroll)
        SizedBox(
          height: 78,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _days.length,
            itemBuilder: (context, index) {
              final isSelected = _selectedDayIndex == index;
              return Padding(
                padding: EdgeInsets.only(
                  right: index < _days.length - 1 ? 10 : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDayIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isSelected
                          ? const Color(0xFF257BF4)
                          : Colors.black.withValues(alpha: 0.2),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF257BF4).withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF257BF4,
                                ).withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _days[index]['day']!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _days[index]['date']!,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Time slots grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.4,
          ),
          itemCount: _timeSlots.length,
          itemBuilder: (context, index) {
            final slot = _timeSlots[index];
            final isAvailable = slot['available'] as bool;
            final isSelected = _selectedTimeIndex == index && isAvailable;

            return GestureDetector(
              onTap: isAvailable
                  ? () => setState(() => _selectedTimeIndex = index)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: !isAvailable
                      ? Colors.white.withValues(alpha: 0.05)
                      : isSelected
                      ? const Color(0xFF257BF4)
                      : Colors.black.withValues(alpha: 0.2),
                  border: Border.all(
                    color: !isAvailable
                        ? Colors.white.withValues(alpha: 0.05)
                        : isSelected
                        ? const Color(0xFF257BF4).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF257BF4,
                            ).withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    slot['time'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: !isAvailable
                          ? const Color(0xFF64748B).withValues(alpha: 0.5)
                          : isSelected
                          ? Colors.white
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  ESTIMASI PENGEMBALIAN
  // ═══════════════════════════════════════════════
  Widget _buildEstimationCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estimasi Pengembalian',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black.withValues(alpha: 0.3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Glow decoration
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF257BF4).withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  // Content
                  Column(
                    children: [
                      Icon(
                        Icons.calendar_month,
                        size: 36,
                        color: const Color(0xFF38BDF8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kamis, 17 Feb - 14:00 WIB',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estimasi waktu berdasarkan layanan yang dipilih.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  RINGKASAN BIAYA SEMENTARA
  // ═══════════════════════════════════════════════
  Widget _buildCostSummary() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Glow decoration
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF257BF4).withValues(alpha: 0.2),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RINGKASAN BIAYA SEMENTARA',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFCBD5E1),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Estimasi Berat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estimasi Berat',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                      Text(
                        '3 kg',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Estimasi Harga
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Estimasi Harga',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                      Text(
                        'Rp ${widget.totalAmount}',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Info note
                  Container(
                    padding: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFFFACC15),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Harga final akan ditentukan setelah cucian ditimbang oleh kurir atau outlet.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFFCBD5E1),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  BOTTOM BUTTON
  // ═══════════════════════════════════════════════
  Widget _buildBottomButton() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0EA5E9).withValues(alpha: 0.0),
              const Color(0xFF0EA5E9).withValues(alpha: 0.9),
            ],
          ),
        ),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    PaymentMethodPage(
                      isDropoff: _selectedDeliveryType == 1,
                      laundry: widget.laundry,
                      items: widget.items,
                      totalAmount: widget.totalAmount,
                      notes: widget.notes,
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      final curve = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1.0, 0.0),
                          end: Offset.zero,
                        ).animate(curve),
                        child: FadeTransition(
                          opacity: Tween<double>(
                            begin: 0.5,
                            end: 1.0,
                          ).animate(curve),
                          child: child,
                        ),
                      );
                    },
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF257BF4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Pilih Pembayaran',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
