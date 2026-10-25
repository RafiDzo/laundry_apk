import 'package:flutter/material.dart';
import 'dart:ui';
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
      'name': 'Sepatu',
      'desc': 'Deep cleaning',
      'price': 45000,
      'icon': Icons.roller_skating,
    },
    {
      'name': 'Jas / Blazer',
      'desc': 'Dry clean only',
      'price': 35000,
      'icon': Icons.dry_cleaning,
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

    // Initialize quantities for selected services
    _quantities = List.generate(widget.selectedServices.length, (_) => 2);
    _unitQuantities = List.generate(_unitServices.length, (_) => 0);

    // Entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Pulse animation for total price
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
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

    total += _serviceFee;
    return total;
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final result = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      result.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        result.write('.');
      }
    }
    return 'Rp ${result.toString().split('').reversed.join('')}';
  }

  void _animateTotal() {
    _pulseController.forward().then((_) => _pulseController.reverse());
  }

  Widget _buildStaggeredChild({required int index, required Widget child}) {
    final begin = (index * 0.12).clamp(0.0, 0.7);
    final end = (begin + 0.3).clamp(0.0, 1.0);

    final slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020617), Color(0xFF02629b), Color(0xFF08a2ea)],
            stops: [0.0, 0.6, 1.0],
          ),
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shop info
                        _buildStaggeredChild(
                          index: 0,
                          child: _buildShopInfoCard(),
                        ),
                        const SizedBox(height: 24),

                        // Detail Layanan
                        _buildStaggeredChild(
                          index: 1,
                          child: _buildServiceDetailSection(),
                        ),
                        const SizedBox(height: 24),

                        // Layanan Satuan
                        _buildStaggeredChild(
                          index: 2,
                          child: _buildUnitServicesSection(),
                        ),
                        const SizedBox(height: 24),

                        // Catatan Khusus
                        _buildStaggeredChild(
                          index: 3,
                          child: _buildNotesSection(),
                        ),
                        const SizedBox(height: 24),

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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: const CircleBorder(),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Order Detail',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 48), // balance
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildShopInfoCard() {
    return _buildGlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.laundry['name'] as String? ?? 'Laundry',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.storefront,
                      size: 16,
                      color: const Color(0xFF0EA5E9),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Selected Shop',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Shop icon placeholder
          Container(
            width: 72,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Center(
              child: Icon(
                widget.laundry['icon'] as IconData? ??
                    Icons.local_laundry_service,
                color: Colors.white.withValues(alpha: 0.6),
                size: 28,
              ),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCounterButton(
            icon: Icons.remove,
            onTap: onRemove,
            isHighlighted: false,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: SizedBox(
              key: ValueKey<int>(quantity),
              width: 32,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          _buildCounterButton(
            icon: Icons.add,
            onTap: onAdd,
            isHighlighted: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isHighlighted,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isHighlighted
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildServiceDetailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detail Layanan',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(widget.selectedServices.length, (index) {
          final service = widget.selectedServices[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < widget.selectedServices.length - 1 ? 12 : 0,
            ),
            child: _buildGlassCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      service['icon'] as IconData? ??
                          Icons.local_laundry_service,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${service['price']} ${service['unit']}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final priceStr = (service['price'] as String)
                                .replaceAll('Rp ', '')
                                .replaceAll('.', '')
                                .trim();
                            final unitPrice = int.tryParse(priceStr) ?? 0;
                            final subtotal = unitPrice * _quantities[index];
                            return Text(
                              '${_quantities[index]} ${service['unit'] == '/ kg' ? 'kg' : 'pcs'} × ${service['price']} = ${_formatPrice(subtotal)}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF38BDF8),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  _buildQuantityControl(
                    quantity: _quantities[index],
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
        Text(
          'Layanan Satuan',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_unitServices.length, (index) {
          final service = _unitServices[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _unitServices.length - 1 ? 12 : 0,
            ),
            child: _buildGlassCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      service['icon'] as IconData,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          service['desc'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildQuantityControl(
                    quantity: _unitQuantities[index],
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
            const Icon(Icons.edit_note, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              'Catatan Khusus',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    'Contoh: Pisahkan baju putih, gunakan pelembut pakaian...',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white, width: 1),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  color: const Color(0xFF0EA5E9),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ringkasan Pesanan',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

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
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  Text(
                    _formatPrice(subtotal),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
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
                    '${service['name']} (${_unitQuantities[index]})',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  Text(
                    _formatPrice(subtotal),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }),

          // Service fee
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Biaya Layanan',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
                Text(
                  _formatPrice(_serviceFee),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
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
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      ScaleTransition(
                        scale: _pulseController.drive(
                          Tween(begin: 1.0, end: 1.0),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            _formatPrice(_totalPrice),
                            key: ValueKey<int>(_totalPrice),
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Button
                Expanded(
                  flex: 3,
                  child: GestureDetector(
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
                            unit: service['unit'] ?? 'pcs'));
                      }
                      for (int i = 0; i < _unitServices.length; i++) {
                        if (_unitQuantities[i] > 0) {
                          final service = _unitServices[i];
                          final unitPrice = service['price'] as int;
                          items.add(OrderItem(
                              name: service['name'],
                              qty: _unitQuantities[i],
                              price: unitPrice,
                              unit: 'pcs'));
                        }
                      }

                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  LogisticsScreen(
                                    laundry: widget.laundry,
                                    items: items,
                                    totalAmount: _totalPrice,
                                    notes: _notesController.text,
                                  ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                final curve = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                );
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(1.0, 0.0),
                                    end: Offset.zero,
                                  ).animate(curve),
                                  child: FadeTransition(
                                    opacity: Tween<double>(
                                      begin: 0.5,
                                      end: 1.0,
                                    ).animate(curve),
                                    child: child,
                                  ),
                                );
                              },
                          transitionDuration: const Duration(milliseconds: 400),
                        ),
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Lanjutkan Pemesanan',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF020617),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward,
                            color: Color(0xFF020617),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
