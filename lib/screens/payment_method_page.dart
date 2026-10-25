import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_tracking_page.dart';
import 'dropoff_tracking_page.dart';
import '../models/order_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class PaymentMethodPage extends StatefulWidget {
  final bool isDropoff;
  final Map<String, dynamic> laundry;
  final List<OrderItem> items;
  final int totalAmount;
  final String notes;

  const PaymentMethodPage({
    super.key,
    this.isDropoff = false,
    required this.laundry,
    required this.items,
    required this.totalAmount,
    required this.notes,
  });

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  String _selectedMethod = 'dana';
  bool _isProcessing = false;

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  // ── Payment method data ──
  static const List<_PaymentCategory> _categories = [
    _PaymentCategory(
      title: 'E-Wallet Instan',
      methods: [
        _PaymentMethod(
          id: 'dana',
          name: 'DANA',
          subtitle: '0812-3456-7890 • Terhubung',
          icon: Icons.account_balance_wallet_rounded,
          badge: 'Rekomendasi',
        ),
        _PaymentMethod(
          id: 'gopay',
          name: 'GoPay',
          subtitle: 'Saldo mencukupi',
          icon: Icons.wallet_rounded,
        ),
        _PaymentMethod(
          id: 'ovo',
          name: 'OVO',
          subtitle: 'Bebas biaya admin',
          icon: Icons.payments_rounded,
        ),
        _PaymentMethod(
          id: 'shopeepay',
          name: 'ShopeePay',
          subtitle: 'Koin cashback s.d. 10%',
          icon: Icons.shopping_bag_rounded,
        ),
      ],
    ),
    _PaymentCategory(
      title: 'Virtual Account Bank',
      methods: [
        _PaymentMethod(
          id: 'bca',
          name: 'Bank BCA',
          subtitle: 'Virtual Account otomatis',
          icon: Icons.account_balance_rounded,
        ),
        _PaymentMethod(
          id: 'mandiri',
          name: 'Bank Mandiri',
          subtitle: 'Mandiri Livin Virtual Account',
          icon: Icons.account_balance_rounded,
        ),
        _PaymentMethod(
          id: 'bri',
          name: 'Bank BRI',
          subtitle: 'BRIVA verifikasi instan',
          icon: Icons.account_balance_rounded,
        ),
      ],
    ),
    _PaymentCategory(
      title: 'Tunai di Tempat',
      methods: [
        _PaymentMethod(
          id: 'cod',
          name: 'Cash on Delivery (COD)',
          subtitle: 'Bayar tunai ke kurir saat pakaian diantar',
          icon: Icons.money_rounded,
        ),
      ],
    ),
  ];

  Future<void> _handleConfirmOrder() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final user = AuthService().currentUser;
      final shopId = widget.laundry['id']?.toString() ?? 'shop_1';

      final order = OrderModel(
        id: '',
        userId: user?.id ?? 'guest_user',
        shopId: shopId,
        shopName: widget.laundry['name'] ?? 'CleanPro Kemang',
        items: widget.items,
        status: 'pending',
        totalPrice: widget.totalAmount,
        serviceFee: 2000,
        notes: widget.notes.isEmpty ? null : widget.notes,
        paymentMethod: _selectedMethod,
        createdAt: DateTime.now(),
      );

      String orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      try {
        orderId = await SupabaseService().createOrder(order);
      } catch (_) {
        // Fallback gracefully jika offline atau belum login Supabase
      }

      if (!mounted) return;

      final Widget destination = widget.isDropoff
          ? DropoffTrackingPage(orderId: orderId)
          : OrderTrackingPage(orderId: orderId);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => destination),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7), // Neutral canvas for desktop
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
                        _buildHeader(context),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildOrderSummaryCard(),
                              const SizedBox(height: 18),
                              ..._buildPaymentSections(),
                              const SizedBox(height: 16),
                              _buildSecurityGuarantee(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Sticky Bottom Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomBar(),
                ),
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
                onTap: () => Navigator.of(context).maybePop(),
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
                'Metode Pembayaran',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_rounded, size: 16, color: Color(0xFF0077E6)),
                  const SizedBox(width: 6),
                  Text(
                    'No. Pesanan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#WSH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Yang Harus Dibayar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.laundry['name'] as String? ?? 'CleanPro Kemang',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Text(
                _formatPrice(widget.totalAmount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
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

  List<Widget> _buildPaymentSections() {
    final widgets = <Widget>[];
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      if (i > 0) widgets.add(const SizedBox(height: 18));

      // Section title
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            category.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      );

      // Payment method cards
      for (int j = 0; j < category.methods.length; j++) {
        if (j > 0) widgets.add(const SizedBox(height: 8));
        widgets.add(_buildPaymentMethodCard(category.methods[j]));
      }
    }
    return widgets;
  }

  Widget _buildPaymentMethodCard(_PaymentMethod method) {
    final isSelected = _selectedMethod == method.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = method.id),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0F7FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? const Color(0xFF0077E6).withValues(alpha: 0.08)
                    : const Color(0xFF0F172A).withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  method.icon ?? Icons.payment_rounded,
                  color: isSelected ? Colors.white : const Color(0xFF0077E6),
                  size: 20,
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
                          method.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (method.badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              method.badge!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF16A34A),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      method.subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? const Color(0xFF0077E6) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF0077E6) : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityGuarantee() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Transaksi dilindungi enkripsi SSL 256-bit dan garansi pencucian 100%.',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total Pembayaran',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  _formatPrice(widget.totalAmount),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0077E6),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isProcessing ? null : _handleConfirmOrder,
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
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        children: [
                          Text(
                            'Konfirmasi Pesanan',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
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

// ═══════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════

class _PaymentCategory {
  final String title;
  final List<_PaymentMethod> methods;

  const _PaymentCategory({required this.title, required this.methods});
}

class _PaymentMethod {
  final String id;
  final String name;
  final String subtitle;
  final IconData? icon;
  final String? badge;

  const _PaymentMethod({
    required this.id,
    required this.name,
    required this.subtitle,
    this.icon,
    this.badge,
  });
}
