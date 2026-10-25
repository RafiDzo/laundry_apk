import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF00B4D8);
    const Color boneWhiteColor = Color(0xFFF8F9FA);
    const Color darkNavyColor = Color(0xFF2B2D42);

    return Scaffold(
      backgroundColor: boneWhiteColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Logo Header
                    _buildLogoHeader(primaryColor),
                    const SizedBox(height: 48),

                    // Instruction Section
                    Text(
                      'Pilih peran Anda untuk melanjutkan',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: darkNavyColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Selamat datang di ekosistem laundry modern. Silakan pilih cara Anda berinteraksi dengan layanan kami.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: darkNavyColor.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Role 1: Customer
                    _buildRoleCard(
                      context: context,
                      title: 'Masuk sebagai Pengguna',
                      subtitle: 'Pesan layanan laundry dengan mudah',
                      icon: Icons.person_rounded,
                      roleType: 'customer',
                      primaryColor: primaryColor,
                    ),
                    
                    const SizedBox(height: 20),

                    // Role 2: Owner
                    _buildRoleCard(
                      context: context,
                      title: 'Masuk sebagai Mitra',
                      subtitle: 'Kelola order dan operasional laundry Anda',
                      icon: Icons.store_rounded,
                      roleType: 'owner',
                      primaryColor: primaryColor,
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom Navigation 
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 32.0),
              decoration: BoxDecoration(
                color: boneWhiteColor.withValues(alpha: 0.8),
                border: Border(
                  top: BorderSide(
                    color: darkNavyColor.withValues(alpha: 0.05),
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildBottomNavItem(Icons.help_outline_rounded, 'Bantuan', darkNavyColor),
                  _buildBottomNavItem(Icons.info_outline_rounded, 'Tentang', darkNavyColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoHeader(Color primaryColor) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.local_laundry_service_rounded,
              size: 56,
              color: primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'WASHORA',
          style: GoogleFonts.quicksand(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String roleType,
    required Color primaryColor,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoginScreen(role: roleType),
          ),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.4),
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, Color darkNavyColor) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: darkNavyColor.withValues(alpha: 0.5),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: darkNavyColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
