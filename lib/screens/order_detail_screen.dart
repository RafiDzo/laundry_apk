import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'logistics_screen.dart';
import '../models/order_model.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> laundry;
  final List<Map<String, dynamic>> selectedServices;

  const OrderDetailScreen({
    super.key,
    required this.laundry,
    required this.selectedServices,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;

  // Track quantities for each service
  late List<int> _quantities;

  // Additional unit services
  final List<Map<String, dynamic>> _unitServices = [
    {
      'name': 'Sepatu Sneakers',
      'desc': 'Deep cleaning sol & upper',
      'price': 35000,
      'icon': Icons.skateboarding_rounded,
    },
    {
      'name': 'Jas / Blazer',
      'desc': 'Dry clean only & hanger',
      'price': 35000,
      'icon': Icons.dry_cleaning_rounded,
    },
    {
      'name': 'Bed Cover King',
      'desc': 'Pembersihan tebal & anti-tungau',
      'price': 25000,
      'icon': Icons.bed_rounded,
    },
  ];
  late List<int> _unitQuantities;

  // Notes
  final TextEditingController _notesController = TextEditingController();

  // Service fee
  final int _serviceFee = 2000;

  @override
  void initState() {
    super.initState();

    // Initialize quantities for selected services (default 2kg or 1pcs)
    _quantities = List.generate(
      widget.selectedServices.length,
      (i) => (widget.selectedServices[i]['unit'] == '/ kg' ? 2 : 1),
    );
    _unitQuantities = List.generate(_unitServices.length, (_) => 0);

    // Entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Pulse animation for total price
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _totalPrice {
    int total = 0;

    // Selected services total
    for (int i = 0; i < widget.selectedServices.length; i++) {
      final priceStr = (widget.selectedServices[i]['price'] as String)
          .replaceAll('Rp ', '')
          .replaceAll('.', '')
          .trim();
      final price = int.tryParse(priceStr) ?? 0;
      total += price * _quantities[i];
    }

    // Unit services total
    for (int i = 0; i < _unitServices.length; i++) {
      total += (_unitServices[i]['price'] as int) * _unitQuantities[i];
    }

    return total + _serviceFee;
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  void _animateTotal() {
    _pulseController.forward().then((_) => _pulseController.reverse());
  }

  Widget _buildStaggeredChild({required int index, required Widget child}) {
    final begin = (index * 0.1).clamp(0.0, 0.7);
    final end = (begin + 0.3).clamp(0.0, 1.0);

    final slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
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
                // Scrollable content
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildHeader(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Shop info
                            _buildStaggeredChild(
                              index: 0,
                              child: _buildShopInfoCard(),
                            ),
                            const SizedBox(height: 18),

                            // Detail Layanan
                            _buildStaggeredChild(
                              index: 1,
                              child: _buildServiceDetailSection(),
                            ),
                            const SizedBox(height: 18),

                            // Layanan Tambahan Satuan
                            _buildStaggeredChild(
                              index: 2,
                              child: _buildUnitServicesSection(),
                            ),
                            const SizedBox(height: 18),

                            // Catatan Khusus
                            _buildStaggeredChild(
                              index: 3,
                              child: _buildNotesSection(),
                            ),
                            const SizedBox(height: 18),

                            // Ringkasan Pesanan
                            _buildStaggeredChild(
                              index: 4,
                              child: _buildOrderSummary(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom bar
                _buildBottomBar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Color(0xFF0F172A),
                    size: 20,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Detail & Bobot Pesanan',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 36), // balance
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildShopInfoCard() {
    final name = widget.laundry['name'] as String? ?? 'CleanPro Kemang';
    final address = widget.laundry['address'] as String? ?? 'Jl. Kemang Raya No. 12A';

    return _buildCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFFF0F7FF),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: const Center(
              child: Icon(
                Icons.storefront_rounded,
                color: Color(0xFF0077E6),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Outlet Terpilih',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  address,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityControl({
    required int quantity,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
    String unit = 'kg',
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCounterButton(
            icon: Icons.remove_rounded,
            onTap: onRemove,
            isEnabled: quantity > 0,
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$quantity $unit',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
          _buildCounterButton(
            icon: Icons.add_rounded,
            onTap: onAdd,
            isEnabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isEnabled,
  }) {
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isEnabled ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
        ),
        child: Icon(
          icon,
          color: isEnabled ? Colors.white : const Color(0xFF94A3B8),
          size: 16,
        ),
      ),
    );
  }

  Widget _buildServiceDetailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Layanan Utama Dipilih',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Atur Estimasi Bobot',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0077E6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(widget.selectedServices.length, (index) {
          final service = widget.selectedServices[index];
          final priceStr = (service['price'] as String)
              .replaceAll('Rp ', '')
              .replaceAll('.', '')
              .trim();
          final unitPrice = int.tryParse(priceStr) ?? 0;
          final subtotal = unitPrice * _quantities[index];
          final isKg = service['unit'] == '/ kg';

          return Padding(
            padding: EdgeInsets.only(
              bottom: index < widget.selectedServices.length - 1 ? 10 : 0,
            ),
            child: _buildCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFF0F7FF),
                        ),
                        child: Icon(
                          service['icon'] as IconData? ?? Icons.local_laundry_service_rounded,
                          color: const Color(0xFF0077E6),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['name'] as String,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${service['price']} ${service['unit']}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildQuantityControl(
                        quantity: _quantities[index],
                        unit: isKg ? 'kg' : 'pcs',
                        onAdd: () {
                          setState(() {
                            _quantities[index]++;
                            _animateTotal();
                          });
                        },
                        onRemove: () {
                          setState(() {
                            if (_quantities[index] > 1) {
                              _quantities[index]--;
                              _animateTotal();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtotal Layanan (${_quantities[index]} ${isKg ? 'kg' : 'pcs'} × ${service['price']}):',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          _formatPrice(subtotal),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0077E6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildUnitServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tambah Layanan Satuan',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Opsional',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(_unitServices.length, (index) {
          final service = _unitServices[index];
          final price = service['price'] as int;
          final qty = _unitQuantities[index];

          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _unitServices.length - 1 ? 10 : 0,
            ),
            child: _buildCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: qty > 0 ? const Color(0xFFF0F7FF) : const Color(0xFFF8FAFC),
                      border: Border.all(
                        color: qty > 0 ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      service['icon'] as IconData,
                      color: qty > 0 ? const Color(0xFF0077E6) : const Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] as String,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '${_formatPrice(price)} / pcs',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0077E6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildQuantityControl(
                    quantity: qty,
                    unit: 'pcs',
                    onAdd: () {
                      setState(() {
                        _unitQuantities[index]++;
                        _animateTotal();
                      });
                    },
                    onRemove: () {
                      setState(() {
                        if (_unitQuantities[index] > 0) {
                          _unitQuantities[index]--;
                          _animateTotal();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.note_alt_rounded, color: Color(0xFF0077E6), size: 18),
            const SizedBox(width: 6),
            Text(
              'Instruksi / Catatan Khusus',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesController,
          maxLines: 3,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: 'Contoh: Baju putih dipisahkan, jangan gunakan pelembut ekstra, dll...',
            hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF94A3B8)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFF0077E6), size: 20),
              const SizedBox(width: 8),
              Text(
                'Ringkasan Estimasi Biaya',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // Selected services
          ...List.generate(widget.selectedServices.length, (index) {
            final service = widget.selectedServices[index];
            final priceStr = (service['price'] as String)
                .replaceAll('Rp ', '')
                .replaceAll('.', '')
                .trim();
            final unitPrice = int.tryParse(priceStr) ?? 0;
            final subtotal = unitPrice * _quantities[index];
            final unit = service['unit'] == '/ kg' ? 'kg' : 'pcs';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${service['name']} (${_quantities[index]} $unit)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  Text(
                    _formatPrice(subtotal),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Unit services (only show if quantity > 0)
          ...List.generate(_unitServices.length, (index) {
            if (_unitQuantities[index] == 0) return const SizedBox.shrink();

            final service = _unitServices[index];
            final subtotal = (service['price'] as int) * _unitQuantities[index];

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${service['name']} (${_unitQuantities[index]} pcs)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  Text(
                    _formatPrice(subtotal),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Service fee
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Biaya Layanan & Aplikasi',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
                  ],
                ),
                Text(
                  _formatPrice(_serviceFee),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Estimasi',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                _formatPrice(_totalPrice),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0077E6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: Color(0xFFE2E8F0)),
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
            // Total
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total Estimasi',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  ScaleTransition(
                    scale: _pulseController.drive(
                      Tween(begin: 1.0, end: 1.0),
                    ),
                    child: Text(
                      _formatPrice(_totalPrice),
                      key: ValueKey<int>(_totalPrice),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0077E6),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Button
            Expanded(
              flex: 3,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    List<OrderItem> items = [];
                    for (int i = 0; i < widget.selectedServices.length; i++) {
                      final service = widget.selectedServices[i];
                      final priceStr = (service['price'] as String)
                          .replaceAll('Rp ', '')
                          .replaceAll('.', '')
                          .trim();
                      final unitPrice = int.tryParse(priceStr) ?? 0;
                      items.add(OrderItem(
                        name: service['name'],
                        qty: _quantities[i],
                        price: unitPrice,
                        unit: service['unit'] ?? 'pcs',
                      ));
                    }
                    for (int i = 0; i < _unitServices.length; i++) {
                      if (_unitQuantities[i] > 0) {
                        final service = _unitServices[i];
                        final unitPrice = service['price'] as int;
                        items.add(OrderItem(
                          name: service['name'],
                          qty: _unitQuantities[i],
                          price: unitPrice,
                          unit: 'pcs',
                        ));
                      }
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LogisticsScreen(
                          laundry: widget.laundry,
                          items: items,
                          totalAmount: _totalPrice,
                          notes: _notesController.text,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pilih Pengiriman',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
