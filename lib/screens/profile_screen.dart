import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../models/user_model.dart';
import 'order_tracking_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();
  final ImagePicker _imagePicker = ImagePicker();

  UserModel? _userData;

  String? _customAvatarUrl;
  String _selectedFragrance = 'Lavender Serenity';
  String _specialNotes = 'Pisahkan pakaian putih & bahan sensitif';
  String _primaryAddress = 'Rumah • Jl. Merdeka No. 12, Panggilan Kurir: Bel Hitam';
  String _userPhone = '0812-3456-7890';
  String _defaultPayment = 'QRIS & E-Wallet (GoPay / OVO)';
  final int _tokenBalance = 957;

  final List<Map<String, String>> _addresses = [
    {
      'label': 'Rumah',
      'address': 'Jl. Merdeka No. 12, RT 02 / RW 05, Menteng',
      'note': 'Titip di satpam atau pencet bel pintu pagar hitam',
      'isDefault': 'true',
    },
    {
      'label': 'Kos Putra Washora',
      'address': 'Jl. Belimbing No. 4A, Kamar 07, Sukolilo',
      'note': 'Kamar lantai 2, gantung di depan pintu',
      'isDefault': 'false',
    },
    {
      'label': 'Kantor Cyber Tower',
      'address': 'Gedung Cyber Lt. 3, Jl. Kuningan Barat No. 8',
      'note': 'Serahkan ke resepsionis lobi utama',
      'isDefault': 'false',
    },
  ];

  final List<String> _fragrances = [
    'Lavender Serenity (Aroma relaksasi)',
    'Ocean Breeze (Segar & tahan lama)',
    'Floral Blossom (Bunga segar lembut)',
    'Baby Powder (Hypoallergenic bayi)',
    'Original Fresh (Standar laundry premium)',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileAndPrefs();
  }

  Future<void> _loadProfileAndPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customAvatarUrl = prefs.getString('pref_avatar_url');
      _selectedFragrance = prefs.getString('pref_fragrance') ?? 'Lavender Serenity';
      _specialNotes = prefs.getString('pref_notes') ?? 'Pisahkan pakaian putih & bahan sensitif';
      _userPhone = prefs.getString('pref_phone') ?? '0812-3456-7890';
      _primaryAddress = prefs.getString('pref_address') ?? _addresses[0]['address']!;
    });

    final uid = _authService.currentUser?.id;
    if (uid != null) {
      try {
        final userModel = await _supabaseService.getUserProfile(uid);
        if (mounted) {
          setState(() {
            _userData = userModel;
            if (_customAvatarUrl == null || _customAvatarUrl!.isEmpty) {
              _customAvatarUrl = userModel?.profileImageUrl;
            }
          });
        }
      } catch (_) {
        // Fallback gracefully
      }
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_fragrance', _selectedFragrance);
    await prefs.setString('pref_notes', _specialNotes);
    await prefs.setString('pref_phone', _userPhone);
    await prefs.setString('pref_address', _primaryAddress);
  }

  Future<void> _updateAvatar(String? newAvatarUrl) async {
    setState(() {
      _customAvatarUrl = newAvatarUrl;
    });

    final prefs = await SharedPreferences.getInstance();
    if (newAvatarUrl != null && newAvatarUrl.isNotEmpty) {
      await prefs.setString('pref_avatar_url', newAvatarUrl);
    } else {
      await prefs.remove('pref_avatar_url');
    }

    final uid = _authService.currentUser?.id;
    if (uid != null) {
      try {
        await _supabaseService.updateUserProfile(uid, {
          'profile_image_url': newAvatarUrl,
        });
      } catch (_) {
        // Ignored
      }
    }
  }

  // ═══════════════════════════════════════════════
  //  ALGORITMA AMBIL FOTO LANGSUNG DARI DIREKTORI
  // ═══════════════════════════════════════════════
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';

      await _updateAvatar(dataUri);

      if (mounted) {
        _showToast('Foto profil berhasil diperbarui dari direktori.');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Gagal memuat gambar: $e');
      }
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0077E6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _getUserDisplayName() {
    if (_userData != null && _userData!.name.trim().isNotEmpty) {
      return _userData!.name;
    }
    final metaName = _authService.currentUser?.userMetadata?['name']?.toString();
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName;
    }
    final email = _authService.currentUser?.email;
    if (email != null && email.contains('@')) {
      final namePart = email.split('@').first;
      return namePart[0].toUpperCase() + namePart.substring(1);
    }
    return 'Rafi Kurniawan';
  }

  String _getUserEmail() {
    return _userData?.email ?? _authService.currentUser?.email ?? 'krafi2320@gmail.com';
  }

  String _getInitialLetter() {
    final name = _getUserDisplayName().trim();
    if (name.isEmpty) return 'R';
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Neutral background for desktop
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC), // Pure clean light surface
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                  blurRadius: 40,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF0077E6).withValues(alpha: 0.05),
                  blurRadius: 60,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Soft blue decorative atmosphere in background
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0077E6).withValues(alpha: 0.07),
                    ),
                  ),
                ),
                Positioned(
                  top: 200,
                  left: -80,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0284C7).withValues(alpha: 0.05),
                    ),
                  ),
                ),

                // Main Scrollable Content
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildIdentityCard(),
                              const SizedBox(height: 16),
                              _buildMembershipTierCard(),
                              const SizedBox(height: 22),
                              _buildSectionHeader('PREFERENSI & AKUN', 'Kelola alamat dan setelan cuci'),
                              const SizedBox(height: 10),
                              _buildAccountGroup(),
                              const SizedBox(height: 22),
                              _buildSectionHeader('KEAMANAN & DUKUNGAN', 'Sandi dan bantuan layanan'),
                              const SizedBox(height: 10),
                              _buildSecurityGroup(),
                              const SizedBox(height: 20),
                              _buildLogoutCard(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Navigation Bar locked inside container
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomNavBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  1. TOP BAR
  // ═══════════════════════════════════════════════
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Profil Pengguna',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.settings_outlined,
              size: 20,
              color: Color(0xFF0077E6),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  2. IDENTITY CARD WITH DIRECT GALLERY PICKER
  // ═══════════════════════════════════════════════
  Widget _buildIdentityCard() {
    final displayName = _getUserDisplayName();
    final email = _getUserEmail();
    final initial = _getInitialLetter();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: const Color(0xFF0077E6).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar circle that directly opens directory file picker
          GestureDetector(
            onTap: _pickImageFromGallery,
            child: Stack(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0077E6), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0077E6).withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _customAvatarUrl != null && _customAvatarUrl!.isNotEmpty
                        ? (_customAvatarUrl!.startsWith('data:image')
                            ? Image.memory(
                                base64Decode(_customAvatarUrl!.split(',').last),
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                _customAvatarUrl!,
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _buildInitialsAvatar(initial),
                              ))
                        : _buildInitialsAvatar(initial),
                  ),
                ),
                // Camera Icon overlay badge
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0077E6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0077E6).withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: _showEditNameDialog,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit_rounded, size: 16, color: Color(0xFF0077E6)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Text(
                        'Pelanggan Terverifikasi',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF16A34A),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(String letter) {
    return Container(
      color: const Color(0xFFEFF6FF),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.plusJakartaSans(
          color: const Color(0xFF0077E6),
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  3. MEMBERSHIP TIER CARD (BLUE ACCENT)
  // ═══════════════════════════════════════════════
  Widget _buildMembershipTierCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0066CC), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0066CC).withValues(alpha: 0.38),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Silver Member',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Aktif s.d 2099',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTierStat('$_tokenBalance', 'Token Saldo'),
              Container(width: 1, height: 26, color: Colors.white24),
              _buildTierStat('14', 'Total Order'),
              Container(width: 1, height: 26, color: Colors.white24),
              _buildTierStat('120', 'Poin Reward'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTierStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  4. QUIET PANELS PREFERENCES & ACCOUNT
  // ═══════════════════════════════════════════════
  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF0077E6),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountGroup() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: const Color(0xFF0077E6).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildQuietRow(
            icon: Icons.place_rounded,
            title: 'Alamat Penjemputan',
            subtitle: _primaryAddress,
            onTap: _showAddressPickerSheet,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildQuietRow(
            icon: Icons.local_florist_rounded,
            title: 'Preferensi Parfum',
            subtitle: _selectedFragrance,
            onTap: _showFragranceDialog,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildQuietRow(
            icon: Icons.note_alt_rounded,
            title: 'Catatan Khusus Cucian',
            subtitle: _specialNotes,
            onTap: _showNotesDialog,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildQuietRow(
            icon: Icons.payment_rounded,
            title: 'Metode Pembayaran',
            subtitle: _defaultPayment,
            onTap: _showPaymentOptionsDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityGroup() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: const Color(0xFF0077E6).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildQuietRow(
            icon: Icons.lock_outline_rounded,
            title: 'Keamanan & Kata Sandi',
            subtitle: 'Perbarui kata sandi akun Anda',
            onTap: _showChangePasswordDialog,
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildQuietRow(
            icon: Icons.support_agent_rounded,
            title: 'Pusat Bantuan & CS',
            subtitle: 'Hubungi Customer Care 24/7',
            onTap: () {
              _showToast('Customer Care Washora: 0812-9999-0000');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuietRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF0077E6), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  5. LOGOUT CARD
  // ═══════════════════════════════════════════════
  Widget _buildLogoutCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: _showLogoutConfirmDialog,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 18),
              const SizedBox(width: 8),
              Text(
                'Keluar dari Akun',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFDC2626),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  6. BOTTOM NAVIGATION BAR (MATCHING HOME)
  // ═══════════════════════════════════════════════
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: const Color(0xFF0077E6).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
        left: 16,
        right: 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_rounded, 'Beranda', 0),
          _buildNavItem(Icons.receipt_long_rounded, 'Pesanan', 1),
          _buildNavItem(Icons.local_shipping_rounded, 'Lacak', 2),
          _buildNavItem(Icons.history_rounded, 'Riwayat', 3),
          _buildNavItem(Icons.person_rounded, 'Profil', 4),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = index == 4;
    return InkWell(
      onTap: () {
        if (index == 0) {
          Navigator.pop(context);
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const OrderTrackingPage(orderId: 'TRK-98421'),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(isActive ? 6 : 4),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFFEFF6FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isActive ? const Color(0xFF0077E6) : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isActive ? const Color(0xFF0077E6) : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  MODALS & DIALOGS (CONSTRAINED RESPONSIVE)
  // ═══════════════════════════════════════════════
  void _showEditNameDialog() {
    final controller = TextEditingController(text: _getUserDisplayName());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Ubah Nama Profil',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF0F172A), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nama lengkap Anda',
            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8)),
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
            child: Text('Batal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final uid = _authService.currentUser?.id;
                if (uid != null) {
                  await _supabaseService.updateUserProfile(uid, {'name': newName});
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _loadProfileAndPrefs();
                _showToast('Nama berhasil diubah');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077E6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Simpan', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showFragranceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Pilih Aroma Parfum',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _fragrances.map((f) {
            final isSelected = _selectedFragrance == f.split(' (').first;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF0F7FF) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                title: Text(
                  f,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0077E6) : const Color(0xFF0F172A),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0077E6))
                    : null,
                onTap: () {
                  setState(() {
                    _selectedFragrance = f.split(' (').first;
                  });
                  _savePreferences();
                  Navigator.pop(ctx);
                  _showToast('Aroma parfum disetel ke $_selectedFragrance');
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showNotesDialog() {
    final controller = TextEditingController(text: _specialNotes);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Catatan Khusus Cucian',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF0F172A), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Contoh: Jangan gunakan pemutih untuk baju batik',
            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 12),
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
            child: Text('Batal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _specialNotes = controller.text.trim());
              _savePreferences();
              Navigator.pop(ctx);
              _showToast('Catatan disimpan');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077E6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Simpan', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPaymentOptionsDialog() {
    final options = ['QRIS & E-Wallet (GoPay / OVO)', 'Transfer Bank BCA / Mandiri', 'Cash on Delivery (COD)'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Metode Pembayaran Utama',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final isSelected = _defaultPayment == opt;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF0F7FF) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                title: Text(
                  opt,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0077E6) : const Color(0xFF0F172A),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0077E6))
                    : null,
                onTap: () {
                  setState(() => _defaultPayment = opt);
                  Navigator.pop(ctx);
                  _showToast('Metode pembayaran utama diperbarui.');
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showAddressPickerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x260F172A),
                  blurRadius: 30,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grab Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Header Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFF0077E6),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih Alamat Antar / Jemput',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tentukan lokasi kurir untuk menjemput cucian',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Address Cards
                    ..._addresses.map((item) {
                      final isDefault = _primaryAddress.contains(item['label']!);
                      IconData addressIcon = Icons.home_rounded;
                      if (item['label']!.toLowerCase().contains('kantor')) {
                        addressIcon = Icons.business_rounded;
                      } else if (item['label']!.toLowerCase().contains('kos')) {
                        addressIcon = Icons.apartment_rounded;
                      }

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _primaryAddress = '${item['label']!} • ${item['address']!}';
                          });
                          _savePreferences();
                          Navigator.pop(ctx);
                          _showToast('Alamat utama diubah ke ${item['label']}');
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDefault ? const Color(0xFFF0F7FF) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDefault ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                              width: isDefault ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDefault
                                    ? const Color(0xFF0077E6).withValues(alpha: 0.08)
                                    : const Color(0xFF0F172A).withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDefault ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  addressIcon,
                                  size: 18,
                                  color: isDefault ? const Color(0xFF0077E6) : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          item['label']!,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (isDefault) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDBEAFE),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Utama',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1D4ED8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['address']!,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF475569),
                                        height: 1.35,
                                      ),
                                    ),
                                    if (item['note'] != null && item['note']!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline_rounded,
                                            size: 13,
                                            color: Color(0xFF94A3B8),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              item['note']!,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF64748B),
                                                fontStyle: FontStyle.italic,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  isDefault
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: isDefault ? const Color(0xFF0077E6) : const Color(0xFFCBD5E1),
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Ganti Kata Sandi',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan kata sandi baru (minimal 6 karakter):',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFF0F172A), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Kata sandi baru',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8)),
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
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
            child: Text('Batal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPass = passwordController.text.trim();
              if (newPass.length >= 6) {
                try {
                  await _authService.updatePassword(newPass);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showToast('Kata sandi berhasil diperbarui.');
                } catch (e) {
                  _showToast('Gagal update sandi: $e');
                }
              } else {
                _showToast('Sandi minimal 6 karakter');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077E6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Perbarui', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Konfirmasi Keluar',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        content: Text(
          'Apakah Anda yakin ingin keluar dari akun Washora Anda?',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
            child: Text('Batal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Keluar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
