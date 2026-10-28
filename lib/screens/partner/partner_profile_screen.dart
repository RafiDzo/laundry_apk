import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../role_selection_screen.dart';
import 'partner_revenue_screen.dart';
import 'partner_chat_screen.dart';

const Color _blue = Color(0xFF0077E6);
const Color _blueLight = Color(0xFFEFF6FF);
const Color _surface = Color(0xFFF8FAFC);
const Color _textDark = Color(0xFF0F172A);
const Color _textMid = Color(0xFF334155);
const Color _textLight = Color(0xFF64748B);
const Color _textHint = Color(0xFF94A3B8);
const Color _border = Color(0xFFE2E8F0);
const Color _success = Color(0xFF10B981);
const Color _warning = Color(0xFFF59E0B);
const Color _danger = Color(0xFFEF4444);

class PartnerProfileScreen extends StatefulWidget {
  const PartnerProfileScreen({super.key});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  bool _isOpen = true;
  int _selectedNavIndex = 4;

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerRevenueScreen()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerChatScreen()),
        );
        break;
      case 4:
        break;
    }
  }

  Future<void> _handleLogout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  Widget _buildMenuTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _blueLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _blue, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: _textHint),
      onTap: onTap,
    );
  }

  Widget _buildStoreHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: _blueLight,
                child: const Icon(
                  Icons.store_rounded,
                  size: 44,
                  color: _blue,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: _success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Budi Laundry Jaya',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.workspace_premium, color: _warning, size: 14),
              const SizedBox(width: 4),
              Text(
                'Mitra Premium • Sejak 2022',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Status Operasional',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textLight,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _isOpen,
                onChanged: (val) {
                  setState(() {
                    _isOpen = val;
                  });
                },
                activeThumbColor: _success,
              ),
              const SizedBox(width: 4),
              Text(
                _isOpen ? 'BUKA' : 'TUTUP',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isOpen ? _success : _danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
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
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Text(
                  '8',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Pesanan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textLight,
                  ),
                ),
              ],
            ),
            const VerticalDivider(color: _border, width: 1),
            Column(
              children: [
                Text(
                  '4.9 ★',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Rating Toko',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textLight,
                  ),
                ),
              ],
            ),
            const VerticalDivider(color: _border, width: 1),
            Column(
              children: [
                Text(
                  '98%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Kepuasan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: _textMid,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildBusinessManagementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('MANAJEMEN BISNIS'),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
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
            children: [
              _buildMenuTile(
                Icons.store_mall_directory_outlined,
                'Informasi Toko',
                'Nama, alamat & foto toko',
                () {},
              ),
              const Divider(indent: 56, height: 1, color: _border),
              _buildMenuTile(
                Icons.category_outlined,
                'Katalog Layanan',
                'Daftar harga & paket layanan',
                () {},
              ),
              const Divider(indent: 56, height: 1, color: _border),
              _buildMenuTile(
                Icons.payment_outlined,
                'Metode Pembayaran',
                'Qris, VA & Rekening Bank',
                () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('AKUN & KEAMANAN'),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
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
            children: [
              _buildMenuTile(
                Icons.manage_accounts_outlined,
                'Profil Pengelola',
                'Data diri & KTP',
                () {},
              ),
              const Divider(indent: 56, height: 1, color: _border),
              _buildMenuTile(
                Icons.security_outlined,
                'Keamanan',
                'Sandi PIN & Autentikasi Dua Arah',
                () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _handleLogout,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _danger),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Keluar dari Akun',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _danger,
            ),
          ),
        ),
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
          'Profil Mitra',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildStoreHeader(),
            const SizedBox(height: 16),
            _buildStatsCard(),
            const SizedBox(height: 24),
            _buildBusinessManagementSection(),
            const SizedBox(height: 24),
            _buildAccountSecuritySection(),
            const SizedBox(height: 24),
            _buildLogoutButton(),
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
