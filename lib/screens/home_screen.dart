import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../models/notification_model.dart';
import '../models/shop_model.dart';
import '../services/seed_data.dart';
import 'shop_detail_screen.dart';
import 'notifications_screen.dart';
import 'order_history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedNavIndex = 0;
  int _selectedFilterIndex = 0;
  int _currentPromoPage = 0;
  late final PageController _promoPageController;
  Timer? _promoTimer;
  late final AnimationController _entranceController;

  final List<String> _filters = [
    'Semua',
    'Kilat Express',
    'Satuan',
    'Setrika Only',
  ];
  final List<IconData> _filterIcons = [
    Icons.apps_rounded,
    Icons.bolt_rounded,
    Icons.local_offer_rounded,
    Icons.iron_rounded,
  ];

  final List<_PromoCard> _promos = [
    const _PromoCard(
      badge: 'PROMO SPESIAL',
      title: 'Diskon 50%',
      subtitle: 'Untuk order cuci & dry clean pertama kamu',
      buttonText: 'Klaim Promo',
      gradientColors: [Color(0xFF0066CC), Color(0xFF0284C7)],
      buttonTextColor: Color(0xFF0066CC),
    ),
    const _PromoCard(
      badge: 'GRATIS ONGKIR',
      title: 'Antar Jemput Bebas Biaya',
      subtitle: 'Minimal pemesanan Rp 50.000 se-area',
      buttonText: 'Pesan Sekarang',
      gradientColors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
      buttonTextColor: Color(0xFF0284C7),
    ),
    const _PromoCard(
      badge: 'MEMBER REWARD',
      title: 'Double Point Cuci',
      subtitle: 'Kumpulkan poin lebih cepat tiap weekend',
      buttonText: 'Lihat Detail',
      gradientColors: [Color(0xFF0369A1), Color(0xFF0284C7)],
      buttonTextColor: Color(0xFF0369A1),
    ),
  ];

  final SupabaseService _supabaseService = SupabaseService();
  final AuthService _authService = AuthService();

  // Notifikasi status pesanan (lonceng) — realtime dari tabel notifications
  StreamSubscription<List<NotificationModel>>? _notifSub;
  Timer? _notifReconnectTimer;
  int _unreadNotifs = 0;
  Set<String>? _seenNotifIds; // null sampai data pertama diterima

  List<ShopModel> _shops = [];
  bool _isLoadingShops = true;

  // Outlet terdekat cadangan/preview
  final List<ShopModel> _dummyShops = [
    ShopModel(
      id: 'dummy-1',
      name: 'CleanPro Kemang',
      rating: 4.9,
      distance: '350m',
      queueText: 'ANTRIAN: 2 (CEPAT)',
      address: 'Jl. Kemang Raya No. 12A',
      openHours: '08:00 - 21:00',
      imageUrl:
          'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=500&auto=format&fit=crop&q=80',
      pricePerKg: 10000,
      services: [],
    ),
    ShopModel(
      id: 'dummy-2',
      name: 'Lavender Eco Laundry',
      rating: 4.8,
      distance: '450m',
      queueText: 'ANTRIAN: 4 (LANCAR)',
      address: 'Jl. Senopati No. 88, Kebayoran',
      openHours: '07:00 - 22:00',
      imageUrl:
          'https://images.unsplash.com/photo-1521656693074-0ef32e80a5d5?w=500&auto=format&fit=crop&q=80',
      pricePerKg: 12000,
      services: [],
    ),
    ShopModel(
      id: 'dummy-3',
      name: 'QuickWash Express Service',
      rating: 4.9,
      distance: '150m',
      queueText: 'ANTRIAN: 1 (SANGAT CEPAT)',
      address: 'Jl. Jend. Sudirman No. 55',
      openHours: '06:00 - 22:00',
      imageUrl:
          'https://images.unsplash.com/photo-1517677208171-0bc6725a3e60?w=500&auto=format&fit=crop&q=80',
      pricePerKg: 9000,
      services: [],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _promoPageController = PageController(viewportFraction: 0.90);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _entranceController.forward();
    _startPromoAutoScroll();
    _loadData();
    _subscribeNotifications();
  }

  void _subscribeNotifications() {
    final userId = _authService.currentUser?.id;
    if (userId == null) return;

    _notifSub?.cancel();
    _notifSub = _supabaseService.getUserNotifications(userId).listen(
      (notifs) {
        if (!mounted) return;
        // Tampilkan pesan singkat untuk notifikasi baru yang masuk saat layar ini terbuka
        final seen = _seenNotifIds;
        if (seen != null) {
          final fresh = notifs.where((n) => !n.isRead && !seen.contains(n.id)).toList();
          if (fresh.isNotEmpty) _showNotificationToast(fresh.first);
        }
        setState(() {
          _seenNotifIds = notifs.map((n) => n.id).toSet();
          _unreadNotifs = notifs.where((n) => !n.isRead).length;
        });
      },
      onError: (e) {
        print('Error stream notifikasi: $e');
        // Koneksi realtime terputus: sambung ulang otomatis
        _notifReconnectTimer?.cancel();
        _notifReconnectTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _subscribeNotifications();
        });
      },
    );
  }

  void _showNotificationToast(NotificationModel notif) {
    final (icon, color) = notificationStyle(notif.status);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    notif.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Lihat',
          textColor: Colors.white,
          onPressed: _openNotifications,
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
  }

  void _loadData() async {
    try {
      await SeedData.seedShopsIfEmpty();
      final fetchedShops = await _supabaseService.getShops();
      if (mounted) {
        setState(() {
          _shops = fetchedShops.isNotEmpty ? fetchedShops : _dummyShops;
          _isLoadingShops = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _shops = _dummyShops;
          _isLoadingShops = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _notifReconnectTimer?.cancel();
    _notifSub?.cancel();
    _promoTimer?.cancel();
    _promoPageController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _startPromoAutoScroll() {
    _promoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_promoPageController.hasClients) {
        final nextPage = (_currentPromoPage + 1) % _promos.length;
        _promoPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  Widget _buildStaggeredChild({required int index, required Widget child}) {
    final begin = (index * 0.08).clamp(0.0, 0.6);
    final end = (begin + 0.35).clamp(0.0, 1.0);
    final slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(begin, end, curve: Curves.easeOutCubic),
          ),
        );
    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      ),
    );
    return SlideTransition(
      position: slideAnim,
      child: FadeTransition(opacity: fadeAnim, child: child),
    );
  }

  String _getUserGreeting() {
    final metaName = _authService.currentUser?.userMetadata?['name']
        ?.toString();
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim().split(' ').first;
    }
    final email = _authService.currentUser?.email;
    if (email != null && email.contains('@')) {
      final namePart = email.split('@').first;
      return namePart[0].toUpperCase() + namePart.substring(1);
    }
    return 'Pelanggan';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFEDF2F7,
      ), // Neutral background for widescreen canvas
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
                  top: 140,
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
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 110),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStaggeredChild(
                                index: 0,
                                child: _buildGreetingHeader(),
                              ),
                              const SizedBox(height: 14),
                              _buildStaggeredChild(
                                index: 1,
                                child: _buildLocationBar(),
                              ),
                              const SizedBox(height: 16),
                              _buildStaggeredChild(
                                index: 2,
                                child: _buildSearchBar(),
                              ),
                              const SizedBox(height: 18),
                              _buildStaggeredChild(
                                index: 3,
                                child: _buildFilterChips(),
                              ),
                              const SizedBox(height: 20),
                              _buildStaggeredChild(
                                index: 4,
                                child: _buildPromoCarousel(),
                              ),
                              const SizedBox(height: 18),
                              _buildStaggeredChild(
                                index: 5,
                                child: _buildSpecialOfferBanner(),
                              ),
                              const SizedBox(height: 22),
                              _buildStaggeredChild(
                                index: 6,
                                child: _buildNearbyHeader(),
                              ),
                              const SizedBox(height: 12),
                              _buildStaggeredChild(
                                index: 7,
                                child: _buildLaundryList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Navigation Bar locked inside maxWidth
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
  //  1. GREETING HEADER (BLUE & WHITE LIGHT THEME)
  // ═══════════════════════════════════════════════
  Widget _buildGreetingHeader() {
    final userName = _getUserGreeting();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0077E6), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0077E6).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_laundry_service_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Halo, $userName!',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF0F172A),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: Color(0xFF0077E6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Siap mencuci bersih & wangi hari ini?',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Notification Bell
          InkWell(
            onTap: _openNotifications,
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: const Color(0xFF0077E6).withValues(alpha: 0.04),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(
                    _unreadNotifs > 0 ? Icons.notifications_active_rounded : Icons.notifications_outlined,
                    color: _unreadNotifs > 0 ? const Color(0xFF0077E6) : const Color(0xFF334155),
                    size: 22,
                  ),
                ),
                // Badge jumlah notifikasi belum dibaca
                if (_unreadNotifs > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _unreadNotifs > 9 ? '9+' : '$_unreadNotifs',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  2. LOCATION BAR
  // ═══════════════════════════════════════════════
  Widget _buildLocationBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: -1,
            ),
            BoxShadow(
              color: const Color(0xFF0077E6).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF0077E6),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOKASI ANTAR / JEMPUT',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Jl. Merdeka No. 12, Menteng, Jakarta Pusat',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ubah',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF0077E6),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  3. SEARCH BAR
  // ═══════════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 5),
              spreadRadius: -1,
            ),
            BoxShadow(
              color: const Color(0xFF0077E6).withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Cari outlet laundry, kiloan, atau sepatu...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 6),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Color(0xFF0077E6),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  4. FILTER CHIPS
  // ═══════════════════════════════════════════════
  Widget _buildFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return InkWell(
            onTap: () => setState(() => _selectedFilterIndex = index),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0077E6) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF0077E6)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF0077E6,
                          ).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF0284C7,
                          ).withValues(alpha: 0.20),
                          blurRadius: 6,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Icon(
                    _filterIcons[index],
                    size: 16,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _filters[index],
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  5. PROMO CAROUSEL (PAGE VIEW)
  // ═══════════════════════════════════════════════
  Widget _buildPromoCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 156,
          child: PageView.builder(
            controller: _promoPageController,
            onPageChanged: (idx) => setState(() => _currentPromoPage = idx),
            itemCount: _promos.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final promo = _promos[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: promo.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: promo.gradientColors.first.withValues(alpha: 0.36),
                      blurRadius: 22,
                      offset: const Offset(0, 9),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: promo.gradientColors.last.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Ambient watermark curves
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              promo.badge,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                promo.title,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                promo.subtitle,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                promo.buttonText,
                                style: GoogleFonts.plusJakartaSans(
                                  color: promo.buttonTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_promos.length, (idx) {
            final isActive = _currentPromoPage == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF0077E6)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  6. SPECIAL OFFER BANNER
  // ═══════════════════════════════════════════════
  Widget _buildSpecialOfferBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF), // Soft clean blue tint
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0077E6).withValues(alpha: 0.09),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0077E6),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0077E6).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paket Langganan Cuci Hemat',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hemat s.d 35% untuk paket keluarga per bulan',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF93C5FD)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0077E6).withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'Lihat Paket',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF0077E6),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  7. NEARBY OUTLETS HEADER
  // ═══════════════════════════════════════════════
  Widget _buildNearbyHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LAUNDRY TERDEKAT',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF0077E6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Outlet Terbaik di Sekitarmu',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Text(
            'Lihat Semua (${_shops.length})',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF0077E6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Buka detail outlet. ID outlet ikut dibawa sampai pesanan dibuat,
  /// sehingga pesanan masuk ke dashboard mitra pemilik outlet tersebut.
  Future<void> _openShopDetail(ShopModel shop) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopDetailScreen(
          laundry: {
            'id': shop.id,
            'name': shop.name,
            'address': shop.address,
            'rating': shop.rating,
            'distance': shop.distance,
            'imageUrl': shop.imageUrl,
            'queueText': shop.queueText,
            'openHours': shop.openHours,
            'pricePerKg': shop.pricePerKg,
            'services': shop.services.map((s) => s.toMap()).toList(),
          },
        ),
      ),
    );
  }

  /// Tombol "Pesanan" di navigasi bawah: pilih outlet dulu, lalu ke detail outlet
  Future<void> _showOutletPicker() async {
    final shops = _shops.where((s) => !s.id.startsWith('dummy-')).toList();
    if (shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isLoadingShops
                ? 'Daftar outlet masih dimuat, coba sebentar lagi.'
                : 'Belum ada outlet yang bisa dipesan saat ini.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<ShopModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Pilih Outlet Laundry',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Pesananmu akan langsung diterima oleh outlet yang dipilih.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: shops.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final shop = shops[i];
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, shop),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.local_laundry_service_rounded, color: Color(0xFF0077E6)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shop.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    shop.address.isNotEmpty ? shop.address : shop.openHours,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked != null && mounted) await _openShopDetail(picked);
  }

  // ═══════════════════════════════════════════════
  //  8. LAUNDRY LIST ITEMS (WHITE CARDS)
  // ═══════════════════════════════════════════════
  Widget _buildLaundryList() {
    if (_isLoadingShops) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28.0),
          child: CircularProgressIndicator(
            color: Color(0xFF0077E6),
            strokeWidth: 2,
          ),
        ),
      );
    }

    final shopsToShow = _shops.isNotEmpty ? _shops : _dummyShops;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: shopsToShow.length,
      itemBuilder: (context, index) {
        final shop = shopsToShow[index];
        final isFast =
            shop.queueText.toUpperCase().contains('CEPAT') ||
            shop.queueText.toUpperCase().contains('LANCAR');

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: -1,
              ),
              BoxShadow(
                color: const Color(0xFF0077E6).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _openShopDetail(shop),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Outlet Thumbnail
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            shop.imageUrl,
                            width: 74,
                            height: 74,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 74,
                                  height: 74,
                                  color: const Color(0xFFEFF6FF),
                                  child: const Icon(
                                    Icons.local_laundry_service_rounded,
                                    color: Color(0xFF0077E6),
                                    size: 28,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Outlet Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    shop.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF0F172A),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: Color(0xFFD97706),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        shop.rating.toStringAsFixed(1),
                                        style: GoogleFonts.plusJakartaSans(
                                          color: const Color(0xFFB45309),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.near_me_rounded,
                                  size: 13,
                                  color: Color(0xFF0077E6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  shop.distance,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFF0077E6),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '•',
                                  style: TextStyle(color: Colors.grey.shade400),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    shop.address,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Queue Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isFast
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                shop.queueText,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isFast
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFD97706),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 10),
                  // Price and Order Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Rp ${shop.pricePerKg}',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF0F172A),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' / kg',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077E6),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0077E6,
                              ).withValues(alpha: 0.38),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          'Pesan Sekarang',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════
  //  9. BOTTOM NAVIGATION BAR (LOCKED IN CONTAINER)
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
    final isActive = _selectedNavIndex == index;
    return InkWell(
      onTap: () {
        if (index == 4) {
          // Navigate to Profile Screen
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          ).then((_) {
            if (mounted) setState(() => _selectedNavIndex = 0);
          });
        } else if (index == 2) {
          // Lacak pesanan aktif milik user
          openActiveOrderTracking(context).then((_) {
            if (mounted) setState(() => _selectedNavIndex = 0);
          });
        } else if (index == 3) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderHistoryScreen()),
          ).then((_) {
            if (mounted) setState(() => _selectedNavIndex = 0);
          });
        } else if (index == 1) {
          // Pilih outlet dulu agar pesanan masuk ke mitra yang tepat
          _showOutletPicker().then((_) {
            if (mounted) setState(() => _selectedNavIndex = 0);
          });
        } else {
          setState(() => _selectedNavIndex = index);
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
                color: isActive
                    ? const Color(0xFF0077E6)
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isActive
                    ? const Color(0xFF0077E6)
                    : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  DATA MODEL PROMO
// ═══════════════════════════════════════════════════
class _PromoCard {
  final String badge;
  final String title;
  final String subtitle;
  final String buttonText;
  final List<Color> gradientColors;
  final Color buttonTextColor;

  const _PromoCard({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.gradientColors,
    required this.buttonTextColor,
  });
}
