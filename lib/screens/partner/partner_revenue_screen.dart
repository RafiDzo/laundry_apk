import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'partner_chat_screen.dart';
import 'partner_profile_screen.dart';

const Color _blue = Color(0xFF0077E6);
const Color _blueLight = Color(0xFFEFF6FF);
const Color _surface = Color(0xFFF8FAFC);
const Color _textDark = Color(0xFF0F172A);
const Color _textLight = Color(0xFF64748B);
const Color _textHint = Color(0xFF94A3B8);
const Color _border = Color(0xFFE2E8F0);
const Color _success = Color(0xFF10B981);
const Color _warning = Color(0xFFF59E0B);

class PartnerRevenueScreen extends StatefulWidget {
  const PartnerRevenueScreen({super.key});

  @override
  State<PartnerRevenueScreen> createState() => _PartnerRevenueScreenState();
}

class _PartnerRevenueScreenState extends State<PartnerRevenueScreen> {
  int _selectedNavIndex = 2;

  final List<double> _barHeights = [40.0, 65.0, 55.0, 80.0, 70.0, 90.0, 45.0];
  final List<String> _dayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  final List<Map<String, String>> _transactions = [
    {
      'name': 'Laundry Kiloan Express',
      'id': 'ORD-8821',
      'time': '10:24',
      'amount': 'Rp 45.000',
      'status': 'SELESAI',
      'type': 'kiloan',
    },
    {
      'name': 'Satuan Jas & Kemeja',
      'id': 'ORD-8312',
      'time': '11:05',
      'amount': 'Rp 125.000',
      'status': 'PROSES',
      'type': 'satuan',
    },
    {
      'name': 'Laundry Kiloan Reguler',
      'id': 'ORD-7910',
      'time': '09:30',
      'amount': 'Rp 32.000',
      'status': 'SELESAI',
      'type': 'kiloan',
    },
  ];

  void _onNavTap(int index) {
    if (index == _selectedNavIndex) return;
    setState(() {
      _selectedNavIndex = index;
    });
    switch (index) {
      case 0:
      case 1:
        // Beranda & Pesanan = dashboard mitra utama (data asli Supabase)
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case 2:
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerChatScreen()),
        );
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerProfileScreen()),
        );
        break;
    }
  }

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, Color(0xFF0056B3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL PENDAPATAN MINGGU INI',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Rp 4.250.000',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.trending_up, color: Color(0xFF4ADE80), size: 18),
              const SizedBox(width: 4),
              Text(
                '+41.5% vs minggu lalu',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF4ADE80),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Divider(
            color: Colors.white.withValues(alpha: 0.3),
            height: 32,
          ),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BULAN INI',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rp 14.500.000',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'BULAN LALU',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rp 10.250.000',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target Bulanan',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '85%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _blue,
                ),
              ),
              const Spacer(),
              Text(
                'Rp 14.5 Jt / 17 Jt',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.85,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(_blue),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rp 2.5 Jt lagi untuk mencapai target',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyPerformanceCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performa Mingguan',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final bool isHighest = i == 5;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: _barHeights[i],
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isHighest ? _blue : _blueLight,
                            border: isHighest
                                ? null
                                : Border.all(color: _blue, width: 1),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dayLabels[i],
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: _textLight,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceMixCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bauran Layanan',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_blue, Color(0xFF0056B3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    '65%',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Layanan Kiloan',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textDark,
                              ),
                            ),
                            Text(
                              '65% • Rp 9.4 Jt',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: _textLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _warning,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Layanan Satuan',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textDark,
                              ),
                            ),
                            Text(
                              '35% • Rp 4.9 Jt',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: _textLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, String> tx) {
    final bool isKiloan = tx['type'] == 'kiloan';
    final bool isSelesai = tx['status'] == 'SELESAI';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isKiloan ? _blueLight : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isKiloan ? Icons.local_laundry_service : Icons.dry_cleaning,
              color: isKiloan ? _blue : _warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['name']!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
                Text(
                  'ID: ${tx['id']} • ${tx['time']}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tx['amount']!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelesai
                      ? _success.withValues(alpha: 0.1)
                      : _warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tx['status']!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelesai ? _success : _warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Transaksi Terakhir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Lihat Semua',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          ..._transactions.map(_buildTransactionCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Laporan Pendapatan',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeaderCard(),
            const SizedBox(height: 16),
            _buildTargetCard(),
            const SizedBox(height: 16),
            _buildWeeklyPerformanceCard(),
            const SizedBox(height: 16),
            _buildServiceMixCard(),
            const SizedBox(height: 16),
            _buildTransactionsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedNavIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _blue,
        unselectedItemColor: _textHint,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Pesanan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart_rounded),
            label: 'Pendapatan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
