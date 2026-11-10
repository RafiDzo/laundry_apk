import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../widgets/review_sheet.dart';
import '../widgets/review_widgets.dart';
import '../services/review_service.dart';
import 'shop_reviews_screen.dart';
import '../widgets/quick_snackbar.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_detail_screen.dart';
import '../services/wallet_service.dart';
import '../services/promo_service.dart';
import '../models/shop_promo_model.dart';
import 'chat_room_screen.dart';
import '../services/chat_service.dart';
import '../models/chat_models.dart';

class ShopDetailScreen extends StatefulWidget {
  final Map<String, dynamic> laundry;

  const ShopDetailScreen({super.key, required this.laundry});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen>
    with SingleTickerProviderStateMixin {
  final Set<int> _selectedServiceIndices = {0}; // Default select first service
  bool _isFavorite = false;
  String _selectedCategory = 'Semua';
  String _selectedSpeed = 'Reguler'; // 'Reguler' or 'Express'

  late AnimationController _selectionPulseController;

  // ── Ulasan (dari tabel reviews di Supabase) ───────────────────
  List<ReviewModel> _reviews = [];
  ReviewSummary? _summary;
  bool _loadingReviews = true;

  String get _shopId => widget.laundry['id']?.toString() ?? '';

  /// Rata-rata & jumlah ulasan: dari data ulasan, atau dari kolom outlet
  double get _avgRating {
    final s = _summary;
    if (s != null && s.count > 0) return s.average;
    if (_reviews.isNotEmpty) {
      return _reviews.fold<int>(0, (s, r) => s + r.rating) / _reviews.length;
    }
    return (widget.laundry['rating'] as num?)?.toDouble() ?? 0;
  }

  int get _reviewCount {
    final s = _summary;
    if (s != null && s.count > 0) return s.count;
    final stored = (widget.laundry['reviewCount'] as num?)?.toInt() ?? 0;
    return _reviews.length > stored ? _reviews.length : stored;
  }

  String get _ratingText {
    if (_reviewCount == 0 && _avgRating == 0) return 'Belum ada ulasan';
    if (_reviewCount == 0) return _avgRating.toStringAsFixed(1).replaceAll('.', ',');
    return '${_avgRating.toStringAsFixed(1).replaceAll('.', ',')} ($_reviewCount Ulasan)';
  }

  // Diisi di initState: dari layanan outlet di database, atau katalog default
  late final List<Map<String, dynamic>> _allServices;
  late final List<String> _categories;

  // Katalog cadangan untuk outlet yang belum punya daftar layanan
  static final List<Map<String, dynamic>> _defaultServices = [
    {
      'id': 'srv_1',
      'name': 'Cuci Komplit (Wash & Fold)',
      'desc': 'Cuci bersih, pewangi premium & setrika uap rapi',
      'price': 'Rp 8.000',
      'priceRaw': 8000,
      'unit': '/ kg',
      'category': 'Kiloan',
      'duration': '1-2 Hari',
      'icon': Icons.local_laundry_service_rounded,
      'badge': 'Terpopuler',
    },
    {
      'id': 'srv_2',
      'name': 'Setrika Uap Only',
      'desc': 'Pelicin pakaian antibakteri & setrika presisi',
      'price': 'Rp 5.000',
      'priceRaw': 5000,
      'unit': '/ kg',
      'category': 'Kiloan',
      'duration': '24 Jam',
      'icon': Icons.iron_rounded,
      'badge': null,
    },
    {
      'id': 'srv_3',
      'name': 'Cuci Kering Lipat (No Iron)',
      'desc': 'Cuci higienis, pengering mesin & lipat rapi',
      'price': 'Rp 6.000',
      'priceRaw': 6000,
      'unit': '/ kg',
      'category': 'Kiloan',
      'duration': '24 Jam',
      'icon': Icons.dry_rounded,
      'badge': null,
    },
    {
      'id': 'srv_4',
      'name': 'Dry Clean Jas & Blazer',
      'desc': 'Pembersihan serat kimia khusus jas + premium hanger',
      'price': 'Rp 35.000',
      'priceRaw': 35000,
      'unit': '/ pcs',
      'category': 'Satuan',
      'duration': '2 Hari',
      'icon': Icons.dry_cleaning_rounded,
      'badge': 'Spesialis',
    },
    {
      'id': 'srv_5',
      'name': 'Gaun Pesta / Gamis Sutra',
      'desc': 'Cuci tangan lembut khusus kain bordir & manik-manik',
      'price': 'Rp 30.000',
      'priceRaw': 30000,
      'unit': '/ pcs',
      'category': 'Satuan',
      'duration': '2-3 Hari',
      'icon': Icons.checkroom_rounded,
      'badge': null,
    },
    {
      'id': 'srv_6',
      'name': 'Bed Cover King / Queen',
      'desc': 'Cuci kapasitas besar, penghilang tungau & plastik zipper',
      'price': 'Rp 25.000',
      'priceRaw': 25000,
      'unit': '/ pcs',
      'category': 'Rumah',
      'duration': '2 Hari',
      'icon': Icons.bed_rounded,
      'badge': 'Best Value',
    },
    {
      'id': 'srv_7',
      'name': 'Sprei & Sarung Bantal Set',
      'desc': 'Pencucian higienis wangi tahan lama bebas alergen',
      'price': 'Rp 15.000',
      'priceRaw': 15000,
      'unit': '/ set',
      'category': 'Rumah',
      'duration': '1-2 Hari',
      'icon': Icons.hotel_rounded,
      'badge': null,
    },
    {
      'id': 'srv_8',
      'name': 'Deep Clean Sneakers / Canvas',
      'desc': 'Pembersihan sol, upper & unyellowing anti jamur',
      'price': 'Rp 35.000',
      'priceRaw': 35000,
      'unit': '/ pasang',
      'category': 'Sepatu & Tas',
      'duration': '2 Hari',
      'icon': Icons.skateboarding_rounded,
      'badge': 'Garansi Bersih',
    },
    {
      'id': 'srv_9',
      'name': 'Tas & Ransel Laptop',
      'desc': 'Pembersihan interior, kompartemen & bahan waterproof',
      'price': 'Rp 30.000',
      'priceRaw': 30000,
      'unit': '/ pcs',
      'category': 'Sepatu & Tas',
      'duration': '2-3 Hari',
      'icon': Icons.backpack_rounded,
      'badge': null,
    },
  ];

  @override
  void initState() {
    super.initState();
    _allServices = _buildServicesForShop();
    if (_allServices.isEmpty) _selectedServiceIndices.clear();
    _categories = [
      'Semua',
      ..._allServices.map((s) => s['category'] as String).toSet(),
    ];
    _selectionPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadReviews();
    _loadPromos();
    WalletService().shopAcceptingOrders(_shopId).then((ok) {
      if (mounted && !ok) setState(() => _acceptingOrders = false);
    });
  }

  /// false jika saldo komisi outlet melewati batas kredit
  bool _acceptingOrders = true;

  /// Promo aktif yang dibuat mitra untuk outlet ini (tabel shop_promos)
  List<ShopPromoModel> _promos = [];

  Future<void> _loadPromos() async {
    if (_shopId.isEmpty || _shopId.startsWith('dummy-')) return;
    final list = await PromoService().getActiveCustomerPromos(_shopId);
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _promos = list
          .where((p) => p.type != ShopPromoType.cashback && !p.isUpcoming)
          .where((p) => p.activeDays.isEmpty || p.activeDays.contains(now.weekday))
          .toList();
    });
  }

  Future<void> _loadReviews() async {
    if (_shopId.isEmpty || _shopId.startsWith('dummy-')) {
      setState(() => _loadingReviews = false);
      return;
    }
    final service = ReviewService();
    List<ReviewModel> list = [];
    ReviewSummary? summary;
    try {
      list = await service.fetchPage(_shopId, page: 0);
    } catch (_) {
      list = await SupabaseService().getShopReviews(_shopId);
    }
    try {
      summary = await service.fetchSummary(_shopId);
    } catch (_) {
      summary = ReviewSummary.fromReviews(list);
    }
    if (!mounted) return;
    setState(() {
      _reviews = list;
      _summary = summary;
      _loadingReviews = false;
    });
  }

  @override
  void dispose() {
    _selectionPulseController.dispose();
    super.dispose();
  }

  static String _formatRupiah(int amount) =>
      'Rp ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  static IconData _iconFromName(String name) {
    switch (name) {
      case 'bolt':
        return Icons.bolt_rounded;
      case 'iron':
        return Icons.iron_rounded;
      case 'dry_cleaning':
        return Icons.dry_cleaning_rounded;
      case 'checkroom':
        return Icons.checkroom_rounded;
      case 'bed':
        return Icons.bed_rounded;
      case 'dry':
        return Icons.dry_rounded;
      case 'sports_motorsports':
        return Icons.sports_motorsports_rounded;
      case 'curtains':
        return Icons.curtains_rounded;
      case 'child_care':
        return Icons.child_care_rounded;
      default:
        return Icons.local_laundry_service_rounded;
    }
  }

  /// Layanan yang dijual outlet ini (kolom `services` di tabel shops).
  /// Jika outlet belum punya daftar layanan, pakai katalog default dengan
  /// harga cuci kiloan disesuaikan ke harga per kg outlet.
  List<Map<String, dynamic>> _buildServicesForShop() {
    final raw = widget.laundry['services'];
    if (raw is List && raw.isNotEmpty) {
      // Layanan yang dimatikan mitra di "Tarif Layanan" tidak ditampilkan ke pelanggan
      final active = raw.whereType<Map>().where((s) => (s['isActive'] ?? s['is_active'] ?? true) == true);
      return active.map((s) {
        final price = (s['price'] as num?)?.toInt() ?? 0;
        final unit = (s['unit'] as String?)?.isNotEmpty == true ? s['unit'] as String : '/ kg';
        final duration = (s['duration'] as String?)?.isNotEmpty == true
            ? s['duration'] as String
            : (unit.contains('kg') ? '1-2 Hari' : '2 Hari');
        return <String, dynamic>{
          'id': s['id'] ?? '',
          'name': s['name'] ?? 'Layanan',
          'desc': s['description'] ?? '',
          'price': _formatRupiah(price),
          'priceRaw': price,
          'unit': unit,
          'category': unit.contains('kg') ? 'Kiloan' : 'Satuan',
          'duration': duration,
          'icon': _iconFromName(s['iconName'] as String? ?? ''),
          'badge': null,
        };
      }).toList();
    }

    final pricePerKg = (widget.laundry['pricePerKg'] as num?)?.toInt() ?? 0;
    return _defaultServices.asMap().entries.map((e) {
      final s = Map<String, dynamic>.from(e.value);
      if (e.key == 0 && pricePerKg > 0) {
        s['priceRaw'] = pricePerKg;
        s['price'] = _formatRupiah(pricePerKg);
      }
      return s;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredServices {
    if (_selectedCategory == 'Semua') {
      return _allServices;
    }
    return _allServices.where((s) => s['category'] == _selectedCategory).toList();
  }

  void _toggleService(int originalIndex) {
    setState(() {
      if (_selectedServiceIndices.contains(originalIndex)) {
        if (_selectedServiceIndices.length > 1) {
          _selectedServiceIndices.remove(originalIndex);
        } else {
          _showToast('Pilih minimal 1 layanan laundry');
        }
      } else {
        _selectedServiceIndices.add(originalIndex);
      }
    });
    _selectionPulseController.forward().then((_) => _selectionPulseController.reverse());
  }

  int get _calculateEstimatedSubtotal {
    int sum = 0;
    for (final idx in _selectedServiceIndices) {
      if (idx >= 0 && idx < _allServices.length) {
        sum += (_allServices[idx]['priceRaw'] as int? ?? 8000);
      }
    }
    if (_selectedSpeed == 'Express') {
      sum += 10000; // Flat express priority surcharge
    }
    return sum;
  }

  /// Chat selalu terikat pesanan: buka percakapan untuk pesanan terakhir
  /// pelanggan di outlet ini, atau beri tahu jika belum pernah memesan.
  Future<void> _openShopChat() async {
    if (_shopId.isEmpty) return;
    ChatConversation? conv;
    try {
      conv = await ChatService.instance.openLatestForShop(_shopId);
    } catch (e) {
      if (!mounted) return;
      // Pesan penjelasan agak panjang: tampilkan lebih lama dari toast biasa
      ScaffoldMessenger.of(context).showQuickSnackBar(
        SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
        duration: const Duration(seconds: 7),
      );
      return;
    }
    if (!mounted || conv == null) return;
    final c = conv;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: c)));
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(milliseconds: 2200),
      ),
    );
  }

  void _navigateToOrderDetail() {
    if (!_acceptingOrders) {
      _showToast('Outlet ini sedang tidak menerima pesanan aplikasi. Coba outlet lain.');
      return;
    }
    if (widget.laundry['isOpen'] == false) {
      _showToast('Outlet sedang tutup sementara. Coba lagi nanti atau pilih outlet lain.');
      return;
    }
    if (_selectedServiceIndices.isEmpty) {
      _showToast('Pilih minimal 1 layanan terlebih dahulu!');
      return;
    }

    final selectedServices = _selectedServiceIndices.map((idx) {
      final s = _allServices[idx];
      return {
        'name': s['name'],
        'desc': s['desc'],
        'price': s['price'],
        'unit': s['unit'],
        'icon': s['icon'],
      };
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailScreen(
          laundry: widget.laundry,
          selectedServices: selectedServices,
        ),
      ),
    );
  }

  void _showContactModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Hubungi ${widget.laundry['name'] ?? 'Outlet'}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ada pertanyaan seputar jenis cucian, antrean, atau lokasi?',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              // Chat internal: terikat pada pesanan terakhir pelanggan di outlet ini
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.forum_rounded, color: Color(0xFF0077B6), size: 22),
                ),
                title: Text(
                  'Chat di Aplikasi',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Tentang pesanan terakhir Anda di outlet ini',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openShopChat();
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF16A34A), size: 22),
                ),
                title: Text(
                  'Chat WhatsApp Kasir',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Respons cepat • 0812-9876-5432',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showToast('Membuka WhatsApp ke customer service...');
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.phone_rounded, color: Color(0xFF0077E6), size: 22),
                ),
                title: Text(
                  'Telepon Langsung',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Jam buka 08:00 - 21:00 WIB',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showToast('Memanggil nomor telepon outlet...');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Neutral background for web/desktop
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
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
                // Scrollable main content
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroHeader(context),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              _buildOutletInfoCard(),
                              const SizedBox(height: 14),
                              if (_promos.isNotEmpty) ...[
                                _buildVoucherBanner(),
                                const SizedBox(height: 4),
                              ],
                              const SizedBox(height: 14),
                              _buildSpeedSelector(),
                              const SizedBox(height: 22),
                              _buildCategorySelector(),
                              const SizedBox(height: 16),
                              _buildServicesList(),
                              const SizedBox(height: 24),
                              _buildCustomerReviews(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Sticky Bottom Booking Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomActionBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  1. HERO COVER HEADER WITH OUTLET PHOTO
  // ═══════════════════════════════════════════════
  Widget _buildHeroHeader(BuildContext context) {
    final name = widget.laundry['name'] as String? ?? 'CleanPro Kemang';
    final imageUrl = widget.laundry['imageUrl'] as String? ??
        'https://images.unsplash.com/photo-1545173168-9f1947eebb7f?w=800&auto=format&fit=crop&q=80';

    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0077E6), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.local_laundry_service_rounded,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.50),
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Top Navigation Bar (Back, Wishlist, Share)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGlassActionButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      _buildGlassActionButton(
                        icon: _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: _isFavorite ? const Color(0xFFEF4444) : Colors.white,
                        onTap: () {
                          setState(() => _isFavorite = !_isFavorite);
                          _showToast(
                            _isFavorite
                                ? 'Ditambahkan ke laundry favorit Anda'
                                : 'Dihapus dari laundry favorit',
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildGlassActionButton(
                        icon: Icons.share_rounded,
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                            text: '$name - Layanan Laundry Terbaik di Washora App',
                          ));
                          _showToast('Tautan outlet disalin ke clipboard');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Outlet Name & Badges on bottom of Hero
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Buka Sekarang',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF16A34A),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 3),
                          Text(
                            _ratingText,
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
                const SizedBox(height: 6),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  2. OUTLET INFO CARD
  // ═══════════════════════════════════════════════
  Widget _buildOutletInfoCard() {
    final address = widget.laundry['address'] as String? ??
        'Jl. Kemang Raya No. 12A, Mampang Prapatan, Jakarta Selatan';
    final distance = widget.laundry['distance'] as String? ?? '350 m';
    final openHoursRaw = widget.laundry['openHours'] as String?;
    final openHours = (openHoursRaw == null || openHoursRaw.isEmpty) ? '08:00 - 21:00 WIB' : openHoursRaw;
    final operationalDays = widget.laundry['operationalDays'] as String?;
    final isOpen = widget.laundry['isOpen'] != false;
    final queueTextRaw = widget.laundry['queueText'] as String?;
    final queueText = !isOpen
        ? 'Tutup Sementara'
        : ((queueTextRaw == null || queueTextRaw.isEmpty) ? 'Buka' : queueTextRaw);
    final queueColor = isOpen ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Address & Distance
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF0077E6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lokasi Outlet',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            distance,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0077E6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      address,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),

          // Operating hours & Queue
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openHours,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          if (operationalDays != null && operationalDays.isNotEmpty)
                            Text(
                              operationalDays,
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: queueColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    queueText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: queueColor,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Contact Outlet Quick Button
          InkWell(
            onTap: _showContactModal,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.headset_mic_rounded, size: 16, color: Color(0xFF0077E6)),
                  const SizedBox(width: 6),
                  Text(
                    'Tanya Kasir / Customer Service Outlet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0077E6),
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

  // ═══════════════════════════════════════════════
  //  3. VOUCHER PROMO BANNER (RECOMMENDED FEATURE)
  // ═══════════════════════════════════════════════
  /// Promo asli dari mitra (bukan kupon contoh). Disembunyikan jika outlet tidak punya promo.
  Widget _buildVoucherBanner() {
    final shown = _promos.take(3).toList();
    return Column(
      children: [
        for (final p in shown) ...[
          _promoTile(p),
          const SizedBox(height: 10),
        ],
        if (_promos.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '+${_promos.length - shown.length} promo lainnya, terlihat saat pembayaran',
              style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
          ),
      ],
    );
  }

  Widget _promoTile(ShopPromoModel p) {
    final code = (p.code ?? '').trim();
    final until = p.endAt == null
        ? null
        : 'Berlaku s.d. ${p.endAt!.day.toString().padLeft(2, '0')}/${p.endAt!.month.toString().padLeft(2, '0')}';
    final info = [p.summaryDescription, ?until].join(' • ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.type.lightColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.type.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.type.color, borderRadius: BorderRadius.circular(10)),
            child: Icon(p.type.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.title} · ${p.type == ShopPromoType.freeDelivery ? 'Gratis Ongkir' : p.valueDisplay}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  code.isEmpty ? 'Otomatis terpakai saat pembayaran • $info' : 'Kode $code • $info',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF475569)),
                ),
              ],
            ),
          ),
          if (code.isNotEmpty)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                _showToast('Kode $code disalin. Tempel di halaman pembayaran.');
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.type.color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Salin',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.type.color),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  4. SPEED SELECTOR (REGULER VS EXPRESS)
  // ═══════════════════════════════════════════════
  Widget _buildSpeedSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Kecepatan Pengerjaan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'SLA Terjamin',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSpeedCard(
                type: 'Reguler',
                title: 'Reguler',
                subtitle: 'Selesai 24-48 Jam',
                priceTag: 'Tarif Standar',
                icon: Icons.access_time_rounded,
                isSelected: _selectedSpeed == 'Reguler',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSpeedCard(
                type: 'Express',
                title: 'Express Kilat',
                subtitle: 'Selesai 6-8 Jam',
                priceTag: '+Rp 10.000',
                icon: Icons.bolt_rounded,
                isSelected: _selectedSpeed == 'Express',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedCard({
    required String type,
    required String title,
    required String subtitle,
    required String priceTag,
    required IconData icon,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedSpeed = type),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F7FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0077E6).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? const Color(0xFF0077E6) : const Color(0xFF64748B),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    priceTag,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF0077E6) : const Color(0xFF0F172A),
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  5. CATEGORY TABS
  // ═══════════════════════════════════════════════
  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pilih Layanan Laundry',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_selectedServiceIndices.length} dipilih',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0077E6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              return InkWell(
                onTap: () => setState(() => _selectedCategory = cat),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF0077E6) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0077E6).withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      cat,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  6. SERVICES LIST
  // ═══════════════════════════════════════════════
  Widget _buildServicesList() {
    final list = _filteredServices;
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          'Tidak ada layanan dalam kategori ini.',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
        ),
      );
    }

    return Column(
      children: list.map((service) {
        final originalIndex = _allServices.indexOf(service);
        final isSelected = _selectedServiceIndices.contains(originalIndex);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleService(originalIndex),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFF0F7FF) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.6 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? const Color(0xFF0077E6).withValues(alpha: 0.08)
                          : const Color(0xFF0F172A).withValues(alpha: 0.03),
                      blurRadius: isSelected ? 12 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Icon Box
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        service['icon'] as IconData,
                        color: isSelected ? Colors.white : const Color(0xFF0077E6),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Service Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  service['name'] as String,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (service['badge'] != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    service['badge'] as String,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0077E6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            service['desc'] as String,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                service['price'] as String,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0077E6),
                                ),
                              ),
                              Text(
                                ' ${service['unit']}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text('•', style: TextStyle(color: Colors.grey.shade400)),
                              const SizedBox(width: 10),
                              Text(
                                service['duration'] as String,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Checkbox Circle
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0077E6) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFCBD5E1),
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════
  //  7. CUSTOMER REVIEWS SECTION
  // ═══════════════════════════════════════════════

  /// Ulasan hanya bisa ditulis untuk pesanan di outlet ini yang sudah selesai
  Future<void> _writeReview() async {
    final user = AuthService().currentUser;
    if (user == null) {
      _showToast('Login dulu untuk menulis ulasan');
      return;
    }
    final service = SupabaseService();
    final orders = await service.fetchUserOrders(user.id);
    final reviewed = await service.getMyReviewsByOrder(user.id);
    if (!mounted) return;
    final eligible = orders
        .where((o) => o.shopId == _shopId && o.status == 'delivered' && !reviewed.containsKey(o.id))
        .toList();
    if (eligible.isEmpty) {
      final hasReviewed = orders.any((o) => o.shopId == _shopId && reviewed.containsKey(o.id));
      _showToast(hasReviewed
          ? 'Semua pesananmu di outlet ini sudah kamu ulas. Terima kasih!'
          : 'Ulasan bisa ditulis setelah pesananmu di outlet ini selesai.');
      return;
    }
    final sent = await showReviewSheet(context, eligible.first);
    if (sent && mounted) {
      _loadReviews();
    }
  }

  Widget _buildCustomerReviews() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ulasan Pelanggan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Text(
                  _ratingText,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0077E6))),
          )
        else if (_reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(Icons.rate_review_outlined, size: 36, color: Color(0xFFCBD5E1)),
                const SizedBox(height: 8),
                Text('Belum ada ulasan',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text('Jadilah yang pertama mengulas outlet ini setelah pesananmu selesai.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF94A3B8))),
              ],
            ),
          )
        else ...[
          RatingSummaryCard(summary: _summary ?? ReviewSummary.fromReviews(_reviews)),
          const SizedBox(height: 12),
          for (final r in _reviews.take(3)) ...[
            ReviewCard(review: r, shopName: widget.laundry['name']?.toString()),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopReviewsScreen(
                    shopId: _shopId,
                    shopName: widget.laundry['name']?.toString() ?? 'Outlet',
                    summary: _summary,
                  ),
                ),
              ),
              child: Text(
                'Lihat semua ulasan (${_summary?.count ?? _reviews.length})',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _writeReview,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: Text(
              'Tulis Ulasan Kamu',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0077E6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  8. STICKY BOTTOM ACTION BAR
  // ═══════════════════════════════════════════════
  Widget _buildBottomActionBar() {
    final count = _selectedServiceIndices.length;
    final subtotal = _calculateEstimatedSubtotal;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Price Estimate Summary
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Layanan Dipilih ($_selectedSpeed)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Rp ${subtotal.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0077E6),
                      ),
                    ),
                    Text(
                      ' / est',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Action Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _navigateToOrderDetail,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
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
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      'Lanjut Pesan',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
