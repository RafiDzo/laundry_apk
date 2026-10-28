import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_tracking_page.dart';
import 'order_flow_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import '../services/address_service.dart';

// ─────────────────────────────────────────────
//  DATA MODEL LOKAL (Demo / Dummy Data)
// ─────────────────────────────────────────────
enum OrderStatus { active, washing, drying, done, cancelled }

class _OrderHistory {
  final String id;
  final String shopName;
  final String serviceType; // 'Kilat Express', 'Reguler', 'Dry Clean', dll
  final OrderStatus status;
  final DateTime date;
  final double weightKg;
  final int totalPrice;
  final String paymentMethod;
  final String? notes;
  final String shopImageUrl;

  const _OrderHistory({
    required this.id,
    required this.shopName,
    required this.serviceType,
    required this.status,
    required this.date,
    required this.weightKg,
    required this.totalPrice,
    required this.paymentMethod,
    this.notes,
    required this.shopImageUrl,
  });
}

// ─────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  // ──────────────────────────
  //  Color palette (same as app theme)
  // ──────────────────────────
  static const _blue = Color(0xFF0077E6);
  static const _blueLight = Color(0xFFEFF6FF);
  static const _surface = Color(0xFFF8FAFC);
  static const _bgOuter = Color(0xFFEDF2F7);
  static const _textDark = Color(0xFF0F172A);
  static const _textMid = Color(0xFF334155);
  static const _textLight = Color(0xFF64748B);
  static const _textHint = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);

  // ──────────────────────────
  //  State
  // ──────────────────────────
  int _selectedTab = 0; // 0=Semua, 1=Aktif, 2=Selesai, 3=Dibatalkan
  final _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String _sortBy = 'terbaru'; // 'terbaru', 'terlama', 'tertinggi', 'terendah'
  String _selectedServiceFilter = 'Semua';
  late final AnimationController _entranceController;

  final List<String> _tabs = ['Semua', 'Aktif 🔵', 'Selesai ✅', 'Dibatalkan ❌'];

  // ──────────────────────────
  //  Demo data
  // ──────────────────────────
  final List<_OrderHistory> _orders = [
    _OrderHistory(
      id: 'TRK-98421',
      shopName: 'CleanPro Kemang',
      serviceType: 'Kilat Express',
      status: OrderStatus.washing,
      date: DateTime(2026, 10, 27, 10, 30),
      weightKg: 6.5,
      totalPrice: 97500,
      paymentMethod: 'GoPay',
      notes: 'Pisahkan baju putih',
      shopImageUrl:
          'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-88320',
      shopName: 'Lavender Eco Laundry',
      serviceType: 'Reguler',
      status: OrderStatus.done,
      date: DateTime(2026, 10, 24, 14, 0),
      weightKg: 4.0,
      totalPrice: 52000,
      paymentMethod: 'DANA',
      shopImageUrl:
          'https://images.unsplash.com/photo-1521656693074-0ef32e80a5d5?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-77115',
      shopName: 'QuickWash Express',
      serviceType: 'Dry Clean',
      status: OrderStatus.done,
      date: DateTime(2026, 10, 20, 9, 0),
      weightKg: 2.0,
      totalPrice: 85000,
      paymentMethod: 'OVO',
      notes: 'Jas & dasi, hati-hati',
      shopImageUrl:
          'https://images.unsplash.com/photo-1517677208171-0bc6725a3e60?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-65009',
      shopName: 'CleanPro Kemang',
      serviceType: 'Setrika Only',
      status: OrderStatus.done,
      date: DateTime(2026, 10, 15, 11, 20),
      weightKg: 3.5,
      totalPrice: 35000,
      paymentMethod: 'GoPay',
      shopImageUrl:
          'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-53781',
      shopName: 'Lavender Eco Laundry',
      serviceType: 'Kilat Express',
      status: OrderStatus.cancelled,
      date: DateTime(2026, 10, 10, 8, 45),
      weightKg: 5.0,
      totalPrice: 75000,
      paymentMethod: 'DANA',
      notes: 'Dibatalkan karena force majeure',
      shopImageUrl:
          'https://images.unsplash.com/photo-1521656693074-0ef32e80a5d5?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-42200',
      shopName: 'QuickWash Express',
      serviceType: 'Reguler',
      status: OrderStatus.done,
      date: DateTime(2026, 10, 5, 16, 0),
      weightKg: 7.0,
      totalPrice: 63000,
      paymentMethod: 'GoPay',
      shopImageUrl:
          'https://images.unsplash.com/photo-1517677208171-0bc6725a3e60?w=200&auto=format&fit=crop&q=60',
    ),
    _OrderHistory(
      id: 'TRK-31099',
      shopName: 'CleanPro Kemang',
      serviceType: 'Reguler',
      status: OrderStatus.done,
      date: DateTime(2026, 9, 27, 13, 10),
      weightKg: 5.5,
      totalPrice: 55000,
      paymentMethod: 'OVO',
      shopImageUrl:
          'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=200&auto=format&fit=crop&q=60',
    ),
  ];

  @override
  void initState() {
    super.initState();
    AddressService.init();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Riwayat transaksi berhasil diperbarui',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: _blue,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ──────────────────────────
  //  Filtering & Sorting Algorithm
  // ──────────────────────────
  List<_OrderHistory> get _filteredOrders {
    var list = _orders.where((o) {
      if (_selectedTab == 1) {
        return o.status == OrderStatus.active ||
            o.status == OrderStatus.washing ||
            o.status == OrderStatus.drying;
      } else if (_selectedTab == 2) {
        return o.status == OrderStatus.done;
      } else if (_selectedTab == 3) {
        return o.status == OrderStatus.cancelled;
      }
      return true;
    }).toList();

    if (_selectedServiceFilter != 'Semua') {
      list = list
          .where(
            (o) => o.serviceType.toLowerCase().contains(
                  _selectedServiceFilter.toLowerCase(),
                ),
          )
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list
          .where(
            (o) =>
                o.shopName.toLowerCase().contains(_searchQuery) ||
                o.id.toLowerCase().contains(_searchQuery) ||
                o.serviceType.toLowerCase().contains(_searchQuery) ||
                (o.notes?.toLowerCase().contains(_searchQuery) ?? false) ||
                o.paymentMethod.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }

    // Sort
    if (_sortBy == 'terbaru') {
      list.sort((a, b) => b.date.compareTo(a.date));
    } else if (_sortBy == 'terlama') {
      list.sort((a, b) => a.date.compareTo(b.date));
    } else if (_sortBy == 'tertinggi') {
      list.sort((a, b) => b.totalPrice.compareTo(a.totalPrice));
    } else if (_sortBy == 'terendah') {
      list.sort((a, b) => a.totalPrice.compareTo(b.totalPrice));
    }

    return list;
  }

  // ──────────────────────────
  //  Summary stats
  // ──────────────────────────
  int get _activeCount => _orders
      .where(
        (o) =>
            o.status == OrderStatus.active ||
            o.status == OrderStatus.washing ||
            o.status == OrderStatus.drying,
      )
      .length;

  int get _totalSpend => _orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0, (s, o) => s + o.totalPrice);

  // ──────────────────────────
  //  Navigation Helper
  // ──────────────────────────
  void _navigateToHome() {
    if (Navigator.canPop(context)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  void _openOrderDetail(_OrderHistory order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderTrackingPage(orderId: order.id),
      ),
    );
  }

  Widget _staggered({required int index, required Widget child}) {
    final begin = (index * 0.08).clamp(0.0, 0.6);
    final end = (begin + 0.35).clamp(0.0, 1.0);
    final slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
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

  // ══════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;

    return Scaffold(
      backgroundColor: _bgOuter,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                  blurRadius: 40,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative background blobs
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                Positioned(
                  top: 200,
                  left: -80,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0284C7).withValues(alpha: 0.04),
                    ),
                  ),
                ),

                // Main content
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildHeader(),
                      _buildLocationStrip(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _onRefresh,
                          color: _blue,
                          child: CustomScrollView(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    const SizedBox(height: 10),
                                    _staggered(
                                      index: 0,
                                      child: _buildSummaryRow(),
                                    ),
                                    const SizedBox(height: 14),
                                    _staggered(
                                      index: 1,
                                      child: _buildSearchBar(),
                                    ),
                                    const SizedBox(height: 12),
                                    _staggered(index: 2, child: _buildTabRow()),
                                    const SizedBox(height: 4),
                                  ],
                                ),
                              ),
                              if (filtered.isEmpty)
                                SliverFillRemaining(child: _buildEmptyState())
                              else
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    120,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      return _staggered(
                                        index: index + 3,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: _buildOrderCard(filtered[index]),
                                        ),
                                      );
                                    }, childCount: filtered.length),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Nav
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

  // ══════════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════════
  Widget _buildHeader() {
    final hasActiveFilter =
        _sortBy != 'terbaru' || _selectedServiceFilter != 'Semua';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _blueLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history_rounded, color: _blue, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Riwayat Pesanan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
              Text(
                'Semua transaksi laundry kamu',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _textLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showFilterBottomSheet,
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasActiveFilter
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasActiveFilter ? _blue : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: hasActiveFilter ? _blue : _textMid,
                      size: 18,
                    ),
                  ),
                  if (hasActiveFilter)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                        ),
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

  // ══════════════════════════════════════════════
  //  LOCATION STRIP (UBAH LOKASI LANGSUNG DI RIWAYAT)
  // ══════════════════════════════════════════════
  Widget _buildLocationStrip() {
    return ValueListenableBuilder<AddressItem>(
      valueListenable: AddressService.currentAddressNotifier,
      builder: (context, currentAddress, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => AddressService.showAddressPickerSheet(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _blueLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: _blue,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentAddress.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentAddress.address,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _textMid,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ubah',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: _blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════
  //  SUMMARY ROW (3 metric cards)
  // ══════════════════════════════════════════════
  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildSummaryCard(
            icon: Icons.receipt_long_rounded,
            label: 'Total Pesanan',
            value: '${_orders.length}',
            color: _blue,
            isSelected: _selectedTab == 0,
            onTap: () => setState(() => _selectedTab = 0),
          ),
          const SizedBox(width: 10),
          _buildSummaryCard(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Total Belanja',
            value: _formatPrice(_totalSpend),
            color: const Color(0xFF0891B2),
            isSelected: _selectedTab == 2,
            onTap: () => setState(() => _selectedTab = 2),
          ),
          const SizedBox(width: 10),
          _buildSummaryCard(
            icon: Icons.local_laundry_service_rounded,
            label: 'Aktif Sekarang',
            value: '$_activeCount',
            color: const Color(0xFF16A34A),
            highlight: _activeCount > 0,
            isSelected: _selectedTab == 1,
            onTap: () => setState(() => _selectedTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool highlight = false,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.06) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? color
                    : highlight
                        ? color.withValues(alpha: 0.35)
                        : _border,
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: highlight ? 0.12 : 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: highlight || isSelected ? color : _textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : _textHint,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  SEARCH BAR
  // ══════════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: _textHint, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textDark,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari outlet, ID pesanan...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textHint,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.close_rounded, color: _textHint, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  FILTER TAB ROW
  // ══════════════════════════════════════════════
  Widget _buildTabRow() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _tabs.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _selectedTab == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _blue : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? _blue : _border),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _blue.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                _tabs[index],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : _textMid,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  ORDER CARD
  // ══════════════════════════════════════════════
  Widget _buildOrderCard(_OrderHistory order) {
    final statusInfo = _statusInfo(order.status);
    final isActive =
        order.status == OrderStatus.washing ||
        order.status == OrderStatus.active ||
        order.status == OrderStatus.drying;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? _blue.withValues(alpha: 0.25) : _border,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? _blue.withValues(alpha: 0.08)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openOrderDetail(order),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // ─ Card top
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        order.shopImageUrl,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _blueLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: _blue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  order.shopName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _textDark,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Status chip
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusInfo.bgColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isActive)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 4),
                                        child: _PulsingDot(
                                          color: statusInfo.textColor,
                                        ),
                                      ),
                                    Text(
                                      statusInfo.label,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: statusInfo.textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Service type badge & date
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _blueLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  order.serviceType,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '•  ${_formatDate(order.date)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: _textLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Stats row: weight & TRK id
                          Row(
                            children: [
                              _miniStat(
                                Icons.scale_rounded,
                                '${order.weightKg} kg',
                              ),
                              const SizedBox(width: 10),
                              _miniStat(
                                Icons.tag_rounded,
                                order.id,
                              ),
                            ],
                          ),
                          if (order.notes != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 11,
                                  color: _textHint,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    order.notes!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: _textLight,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─ Card bottom bar
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(top: BorderSide(color: _border)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Price
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Bayar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: _textHint,
                          ),
                        ),
                        Text(
                          _formatPrice(order.totalPrice),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.paymentMethod,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: _textLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Action buttons
                    if (order.status == OrderStatus.done) ...[
                      _actionButton(
                        label: 'Pesan Lagi',
                        icon: Icons.refresh_rounded,
                        filled: false,
                        onTap: () => _showReorderBottomSheet(order),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _actionButton(
                      label: isActive ? 'Lacak' : 'Detail',
                      icon: isActive
                          ? Icons.location_on_rounded
                          : Icons.receipt_rounded,
                      filled: true,
                      onTap: () => _openOrderDetail(order),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _textHint),
        const SizedBox(width: 3),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: _textLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: filled ? _blue : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _blue),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: filled ? Colors.white : _blue),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : _blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  MODAL PESAN LAGI
  // ══════════════════════════════════════════════
  void _showReorderBottomSheet(_OrderHistory order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _blueLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: _blue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pesan Ulang Laundry',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: _textDark,
                                  ),
                                ),
                                Text(
                                  'Pesan kembali cucian di outlet ini',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: _textLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _textLight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Card info outlet
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                order.shopImageUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 50,
                                  height: 50,
                                  color: _blueLight,
                                  child: const Icon(
                                    Icons.storefront_rounded,
                                    color: _blue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.shopName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${order.serviceType} • ${order.weightKg} kg',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: _textLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatPrice(order.totalPrice),
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Lokasi Antar / Jemput
                      Text(
                        'LOKASI PENJEMPUTAN & PENGANTARAN',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textHint,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<AddressItem>(
                        valueListenable: AddressService.currentAddressNotifier,
                        builder: (context, currentAddress, _) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: _blue,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentAddress.label,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: _textDark,
                                        ),
                                      ),
                                      Text(
                                        currentAddress.address,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: _textLight,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    AddressService.showAddressPickerSheet(
                                      context,
                                    );
                                  },
                                  child: Text(
                                    'Ubah',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: _blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const OrderFlowScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Lanjut ke Pemesanan',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════
  //  MODAL FILTER & SORT
  // ══════════════════════════════════════════════
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String tempSort = _sortBy;
        String tempFilter = _selectedServiceFilter;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final services = [
              'Semua',
              'Kilat Express',
              'Reguler',
              'Dry Clean',
              'Setrika Only',
            ];
            final sortOptions = [
              {
                'id': 'terbaru',
                'name': 'Terbaru',
                'icon': Icons.calendar_today_rounded,
              },
              {
                'id': 'terlama',
                'name': 'Terlama',
                'icon': Icons.history_rounded,
              },
              {
                'id': 'tertinggi',
                'name': 'Total Tertinggi',
                'icon': Icons.trending_up_rounded,
              },
              {
                'id': 'terendah',
                'name': 'Total Terendah',
                'icon': Icons.trending_down_rounded,
              },
            ];

            return Center(
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
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _blueLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: _blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Filter & Urutkan Pesanan',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: _textDark,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: _textLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Urutkan
                          Text(
                            'URUTKAN BERDASARKAN',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _textHint,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sortOptions.map((opt) {
                              final isSel = tempSort == opt['id'];
                              return InkWell(
                                onTap: () => setSheetState(
                                  () => tempSort = opt['id'] as String,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSel ? _blue : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        opt['icon'] as IconData,
                                        size: 14,
                                        color: isSel ? Colors.white : _textMid,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        opt['name'] as String,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSel ? Colors.white : _textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Jenis Layanan
                          Text(
                            'JENIS LAYANAN',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _textHint,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: services.map((srv) {
                              final isSel = tempFilter == srv;
                              return InkWell(
                                onTap: () =>
                                    setSheetState(() => tempFilter = srv),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSel ? _blue : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    srv,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSel ? Colors.white : _textDark,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Lokasi Pengantaran
                          Text(
                            'LOKASI PENGANTARAN AKTIF',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _textHint,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<AddressItem>(
                            valueListenable:
                                AddressService.currentAddressNotifier,
                            builder: (context, currentAddress, _) {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_rounded,
                                      color: _blue,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${currentAddress.label} • ${currentAddress.address}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        AddressService.showAddressPickerSheet(
                                          context,
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Ubah',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _blue,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _sortBy = 'terbaru';
                                      _selectedServiceFilter = 'Semua';
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: const BorderSide(color: _border),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Reset',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: _textMid,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _sortBy = tempSort;
                                      _selectedServiceFilter = tempFilter;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _blue,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Terapkan Filter',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════
  //  EMPTY STATE
  // ══════════════════════════════════════════════
  Widget _buildEmptyState() {
    final titles = [
      'Belum ada pesanan',
      'Tidak ada pesanan aktif',
      'Belum ada pesanan selesai',
      'Tidak ada pesanan dibatalkan',
    ];
    final descs = [
      'Kamu belum pernah melakukan transaksi laundry.',
      'Saat ini tidak ada cucian yang sedang diproses.',
      'Pesanan yang sudah selesai akan muncul di sini.',
      'Tidak ada riwayat pesanan yang dibatalkan.',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _blueLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: _blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Tidak ada hasil untuk "$_searchQuery"'
                  : titles[_selectedTab],
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Coba gunakan kata kunci pencarian yang lain.'
                  : descs[_selectedTab],
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const OrderFlowScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Mulai Cuci Sekarang',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  BOTTOM NAV BAR
  // ══════════════════════════════════════════════
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
            spreadRadius: -2,
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
    final isActive = index == 3; // Riwayat is active
    return InkWell(
      onTap: () {
        if (index == 0) {
          _navigateToHome();
        } else if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderFlowScreen()),
          );
        } else if (index == 2) {
          final activeOrder = _orders.firstWhere(
            (o) =>
                o.status == OrderStatus.active ||
                o.status == OrderStatus.washing ||
                o.status == OrderStatus.drying,
            orElse: () => _orders.first,
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderTrackingPage(orderId: activeOrder.id),
            ),
          );
        } else if (index == 3) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } else if (index == 4) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
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
                color: isActive ? _blueLight : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isActive ? _blue : _textHint,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isActive ? _blue : _textHint,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────
  //  Helpers
  // ──────────────────────────
  String _formatPrice(int amount) {
    final s = amount.toString();
    final buffer = StringBuffer('Rp ');
    int offset = s.length % 3;
    if (offset > 0) {
      buffer.write(s.substring(0, offset));
      if (offset < s.length) buffer.write('.');
    }
    for (int i = offset; i < s.length; i += 3) {
      buffer.write(s.substring(i, i + 3));
      if (i + 3 < s.length) buffer.write('.');
    }
    return buffer.toString();
  }

  String _formatDate(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  _StatusInfo _statusInfo(OrderStatus status) {
    switch (status) {
      case OrderStatus.active:
      case OrderStatus.washing:
        return const _StatusInfo(
          label: 'Dicuci',
          textColor: Color(0xFF0077E6),
          bgColor: Color(0xFFEFF6FF),
        );
      case OrderStatus.drying:
        return const _StatusInfo(
          label: 'Dikeringkan',
          textColor: Color(0xFFD97706),
          bgColor: Color(0xFFFEF3C7),
        );
      case OrderStatus.done:
        return const _StatusInfo(
          label: 'Selesai',
          textColor: Color(0xFF16A34A),
          bgColor: Color(0xFFDCFCE7),
        );
      case OrderStatus.cancelled:
        return const _StatusInfo(
          label: 'Dibatalkan',
          textColor: Color(0xFFDC2626),
          bgColor: Color(0xFFFEE2E2),
        );
    }
  }
}

class _StatusInfo {
  final String label;
  final Color textColor;
  final Color bgColor;

  const _StatusInfo({
    required this.label,
    required this.textColor,
    required this.bgColor,
  });
}

// ─────────────────────────────────────────────
//  Pulsing Dot (for active order badge)
// ─────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
