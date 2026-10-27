import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'partner_home_screen.dart';
import 'partner_orders_screen.dart';
import 'partner_revenue_screen.dart';
import 'partner_profile_screen.dart';
import 'partner_chat_detail_screen.dart';

const Color _blue = Color(0xFF0077E6);
const Color _surface = Color(0xFFF8FAFC);
const Color _textDark = Color(0xFF0F172A);
const Color _textLight = Color(0xFF64748B);
const Color _textHint = Color(0xFF94A3B8);
const Color _border = Color(0xFFE2E8F0);

class PartnerChatScreen extends StatefulWidget {
  const PartnerChatScreen({super.key});

  @override
  State<PartnerChatScreen> createState() => _PartnerChatScreenState();
}

class _PartnerChatScreenState extends State<PartnerChatScreen> {
  int _selectedNavIndex = 3;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Map<String, dynamic>> _allChats = [
    {
      'name': 'Rafi',
      'avatar': 'R',
      'lastMessage': 'Halo, apakah pesanan saya sudah diproses?',
      'time': '10:45',
      'unread': 2,
      'avatarColor': Color(0xFF8B5CF6),
    },
    {
      'name': 'Siti',
      'avatar': 'S',
      'lastMessage': 'Terima kasih banyak atas bantuannya!',
      'time': '09:21',
      'unread': 0,
      'avatarColor': Color(0xFFEC4899),
    },
    {
      'name': 'Budi',
      'avatar': 'B',
      'lastMessage': 'Oke, saya tunggu informasinya.',
      'time': '08:55',
      'unread': 0,
      'avatarColor': Color(0xFF0077E6),
    },
    {
      'name': 'Anisa',
      'avatar': 'A',
      'lastMessage': 'Apa bisa jemput sekarang?',
      'time': 'Kemarin',
      'unread': 1,
      'avatarColor': Color(0xFF10B981),
    },
    {
      'name': 'Denny',
      'avatar': 'D',
      'lastMessage': 'Pesanan saya sudah siap kan?',
      'time': 'Kemarin',
      'unread': 0,
      'avatarColor': Color(0xFFF59E0B),
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredChats {
    if (_searchQuery.isEmpty) return _allChats;
    return _allChats
        .where((chat) =>
            (chat['name'] as String)
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Widget _buildChatTile(Map<String, dynamic> chat, BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PartnerChatDetailScreen(
              customerName: chat['name'] as String,
              avatarLetter: chat['avatar'] as String,
              avatarColor: chat['avatarColor'] as Color,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: chat['avatarColor'] as Color,
              child: Text(
                chat['avatar'] as String,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
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
                        chat['name'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        chat['time'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          color: _textLight,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat['lastMessage'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            color: _textLight,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((chat['unread'] as int) > 0) ...[
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: _blue,
                          child: Text(
                            (chat['unread'] as int).toString(),
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == _selectedNavIndex) return;
    setState(() => _selectedNavIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerHomeScreen()),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerOrdersScreen()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerRevenueScreen()),
        );
        break;
      case 3:
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PartnerProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Pesan Pelanggan',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.bold,
            color: _textDark,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _border, height: 1),
        ),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: _textHint, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.plusJakartaSans(
                      color: _textDark,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Cari percakapan...',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: _textHint,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: _filteredChats.length,
              itemBuilder: (context, index) {
                return _buildChatTile(_filteredChats[index], context);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          onTap: _onNavTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: _blue,
          unselectedItemColor: _textLight,
          selectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Beranda',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Pesanan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Pendapatan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              label: 'Pesan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
