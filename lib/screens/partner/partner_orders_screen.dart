import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'partner_home_screen.dart';
import 'partner_revenue_screen.dart';
import 'partner_chat_screen.dart';
import 'partner_profile_screen.dart';

const Color _blue = Color(0xFF0077E6);
const Color _surface = Color(0xFFF8FAFC);
const Color _textDark = Color(0xFF0F172A);
const Color _textMid = Color(0xFF334155);
const Color _textLight = Color(0xFF64748B);
const Color _textHint = Color(0xFF94A3B8);
const Color _border = Color(0xFFE2E8F0);
const Color _success = Color(0xFF10B981);
const Color _warning = Color(0xFFF59E0B);

class PartnerOrdersScreen extends StatefulWidget {
  const PartnerOrdersScreen({super.key});

  @override
  State<PartnerOrdersScreen> createState() => _PartnerOrdersScreenState();
}

class _PartnerOrdersScreenState extends State<PartnerOrdersScreen> {
  int _selectedTab = 0;
  int _selectedNavIndex = 1;

  final List<Map<String, String>> _allOrders = [
    {
      'id': 'ORD-8823',
      'customer': 'Budi Santoso',
      'service': 'Cuci Lipat',
      'weight': '5 kg',
      'status': 'Baru',
      'amount': 'Rp 45.000',
      'time': '5 min lalu',
      'note': '',
    },
    {
      'id': 'ORD-8819',
      'customer': 'Lina Hartati',
      'service': 'Cuci Kering',
      'weight': '3 kg',
      'status': 'Baru',
      'amount': 'Rp 30.000',
      'time': '20 min lalu',
      'note': 'Pisahkan warna',
    },
    {
      'id': 'ORD-8801',
      'customer': 'Eko Wahyudi',
      'service': 'Cuci Setrika',
      'weight': '4 kg',
      'status': 'Baru',
      'amount': 'Rp 60.000',
      'time': '35 min lalu',
      'note': '',
    },
    {
      'id': 'ORD-8312',
      'customer': 'Siti Mirnawati',
      'service': 'Cuci Setrika',
      'weight': '3 kg',
      'status': 'Proses',
      'amount': 'Rp 120.000',
      'time': '1 jam lalu',
      'note': 'Jangan diperas terlalu kencang',
    },
    {
      'id': 'ORD-8290',
      'customer': 'Ahmad Fauzi',
      'service': 'Cuci Basah',
      'weight': '6 kg',
      'status': 'Proses',
      'amount': 'Rp 54.000',
      'time': '2 jam lalu',
      'note': '',
    },
    {
      'id': 'ORD-8145',
      'customer': 'Dewi Rahayu',
      'service': 'Cuci Lipat',
      'weight': '7 kg',
      'status': 'Siap',
      'amount': 'Rp 63.000',
      'time': '3 jam lalu',
      'note': 'Antar ke alamat',
    },
  ];

  List<String> get _tabLabels => ['Baru', 'Proses', 'Siap'];

  List<Map<String, String>> get _filteredOrders {
    final label = _tabLabels[_selectedTab];
    return _allOrders.where((o) => o['status'] == label).toList();
  }

  void _onNavTap(int index) {
    if (index == _selectedNavIndex) return;
    setState(() {
      _selectedNavIndex = index;
    });
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PartnerHomeScreen()),
        );
        break;
      case 1:
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PartnerRevenueScreen()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PartnerChatScreen()),
        );
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PartnerProfileScreen()),
        );
        break;
    }
  }

  void _showStatusUpdateSheet(Map<String, String> order) {
    final List<Map<String, dynamic>> statuses = [
      {'label': 'Baru', 'color': _blue},
      {'label': 'Proses', 'color': _warning},
      {'label': 'Siap', 'color': _success},
      {'label': 'Selesai', 'color': _textHint},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Perbarui Status Pesanan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const Divider(height: 20),
              ...statuses.map((s) {
                final isSelected = order['status'] == s['label'];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? s['color'] as Color
                          : Colors.transparent,
                      border: Border.all(
                        color: s['color'] as Color,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    s['label'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: s['color'] as Color,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      final idx = _allOrders.indexWhere(
                        (o) => o['id'] == order['id'],
                      );
                      if (idx != -1) {
                        _allOrders[idx] = Map<String, String>.from(_allOrders[idx])
                          ..['status'] = s['label'] as String;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Manajemen Pesanan',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(child: _buildOrderList()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: List.generate(_tabLabels.length, (index) {
          final isSelected = index == _selectedTab;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isSelected ? _blue : _border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _tabLabels[index],
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : _textLight,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOrderList() {
    final orders = _filteredOrders;
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_laundry_service_rounded,
              size: 64,
              color: _textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'Siap menerima pesanan baru?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textMid,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Belum ada pesanan di kategori ini',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _textHint,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(orders[index]);
      },
    );
  }

  Widget _buildOrderCard(Map<String, String> order) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${order['id']}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _blue,
                ),
              ),
              const Spacer(),
              Text(
                order['time']!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: _textHint),
              const SizedBox(width: 4),
              Text(
                order['customer']!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.local_laundry_service_rounded, size: 14, color: _textHint),
              const SizedBox(width: 4),
              Text(
                '${order['service']} \u2022 ${order['weight']}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.note_rounded, size: 14, color: _textHint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order['note']!.isEmpty ? 'Tidak ada catatan' : order['note']!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: _textHint,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Text(
                order['amount']!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _showStatusUpdateSheet(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: Text(
                  'Perbarui Status \u2192',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Beranda'},
      {'icon': Icons.list_alt_rounded, 'label': 'Pesanan'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Laporan'},
      {'icon': Icons.chat_bubble_rounded, 'label': 'Chat'},
      {'icon': Icons.person_rounded, 'label': 'Profil'},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(items.length, (index) {
              final isSelected = index == _selectedNavIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onNavTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[index]['icon'] as IconData,
                        color: isSelected ? _blue : _textHint,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[index]['label'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? _blue : _textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
