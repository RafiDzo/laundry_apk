import 'package:flutter/material.dart';
import 'dart:ui';
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
  String _selectedMethod = 'gopay';
  bool _isProcessing = false;

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

  // ── Payment method data ──
  static const List<_PaymentCategory> _categories = [
    _PaymentCategory(
      title: 'E-Wallet',
      methods: [
        _PaymentMethod(
          id: 'gopay',
          name: 'GoPay',
          subtitle: 'Balance: Rp 120.000',
          icon: Icons.account_balance_wallet,
        ),
        _PaymentMethod(
          id: 'ovo',
          name: 'OVO',
          subtitle: 'Connected',
          icon: Icons.payments,
        ),
        _PaymentMethod(
          id: 'shopeepay',
          name: 'ShopeePay',
          subtitle: 'Not connected',
          icon: Icons.shopping_bag,
        ),
      ],
    ),
    _PaymentCategory(
      title: 'Transfer Bank',
      methods: [
        _PaymentMethod(
          id: 'bca',
          name: 'Bank BCA',
          subtitle: 'Virtual Account',
          imageUrl:
              'https://lh3.googleusercontent.com/aida-public/AB6AXuA7hurqfkSG0SE_y5c0v6c12GzbVVYyoN5058poRzaJIZIMmaElbBd1DYfl1QOzb_Pcog0SsT5rCc_oqWvv4kYzhA4F1C8lCcYLC4Kg-MyOczB-WU4ofzEkSNAFRpjR12ib8Go3jb3r9KEbpdWliLuxIdH_kQ10ZCgxqJMLFTxe0Mu3ifMjziLlmKc_Rc8P2vcIAhl2qTg7IB-AGaWlNE4HDfRtFKUWlRLIF1fC1PtjqR7EXv9SUMuv5Kia9yIMO4Nra0Cy9QVpaDc',
        ),
        _PaymentMethod(
          id: 'mandiri',
          name: 'Bank Mandiri',
          subtitle: 'Virtual Account',
          imageUrl:
              'https://lh3.googleusercontent.com/aida-public/AB6AXuB8SBmTZM36MzYv-flGKEJIZsqAZx40UbVuuzAbWayXYhPi2o-o8WPD0bVU-w5-C12y9RNZB97_w5Tla5EM9vQJS7bcJSrPF_ucrLcOg_sOyANav4LbU4i84Af4zfsbP0hNEEy4oCT2qgiLcHvdFc7WmiHCpNco2UEHWPrgVRhN_0sdAC2SPrROqbsaMWpX0z2gOvAloiomOJcBg-kcnrdvEG-XwfNxayvLud5icq4c1Ol37uMccHVf9Bvy29F0uvFs7AdCHtaQr9M',
        ),
        _PaymentMethod(
          id: 'bni',
          name: 'Bank BNI',
          subtitle: 'Virtual Account',
          imageUrl:
              'https://lh3.googleusercontent.com/aida-public/AB6AXuChXE2EZYKlYhGBLmL-b9y5XVxKGS7HDQT2xvRiTv3cJm5iEsCAZx3Vs4aeOAwGneUlIwDLcr03Dy4tHHrr7ET2nXJnIKtRy2-CddKJQ5Mi9NUqsJhnnAIkhXD9QynsXbX88dgk1XHOH4M_THH9Cwe1U2TED3XLiOJjYDFy2KJjBqXxTh-hmxw-hARPiQH2c3UkKCXSeLHBnPr4VHNMACvv3PamzymsHHkSo9Ewo-4K415K8cVbmG2qnhvU9vX6qVkDWjYuDhBNUoY',
        ),
      ],
    ),
    _PaymentCategory(
      title: 'Tunai',
      methods: [
        _PaymentMethod(
          id: 'cod',
          name: 'Cash on Delivery',
          subtitle: 'Pay when laundry is delivered',
          icon: Icons.attach_money,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // ── Background gradient ──
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF0C4A6E),
                  Color(0xFF0EA5E9),
                  Color(0xFF0EA5E9),
                ],
                stops: [0.0, 0.4, 0.8, 1.0],
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 180),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOrderSummaryCard(),
                        const SizedBox(height: 24),
                        ..._buildPaymentSections(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom bar ──
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomBar()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════
  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  'Payment Method',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  ORDER SUMMARY CARD
  // ═══════════════════════════════════════════════
  Widget _buildOrderSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order ID',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Text(
                '#LDR-88219',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Total to Pay',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatPrice(widget.totalAmount),
                style: const TextStyle(
                  color: Color(0xFF7DD3FC),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  PAYMENT SECTIONS
  // ═══════════════════════════════════════════════
  List<Widget> _buildPaymentSections() {
    final widgets = <Widget>[];
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      if (i > 0) widgets.add(const SizedBox(height: 24));

      // Section title
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            category.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

      // Payment method cards
      for (int j = 0; j < category.methods.length; j++) {
        if (j > 0) widgets.add(const SizedBox(height: 12));
        widgets.add(_buildPaymentMethodCard(category.methods[j]));
      }
    }
    return widgets;
  }

  Widget _buildPaymentMethodCard(_PaymentMethod method) {
    final isSelected = _selectedMethod == method.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF020617).withValues(alpha: isSelected ? 0.6 : 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.05),
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            // Icon / Logo
            _buildMethodAvatar(method),
            const SizedBox(width: 16),
            // Name & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Radio indicator
            _buildRadioIndicator(isSelected),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodAvatar(_PaymentMethod method) {
    if (method.imageUrl != null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          method.imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.account_balance,
            color: Colors.white.withValues(alpha: 0.6),
            size: 20,
          ),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Icon(method.icon ?? Icons.payment, color: Colors.white, size: 20),
    );
  }

  Widget _buildRadioIndicator(bool isSelected) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? const Color(0xFF38BDF8)
              : Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF38BDF8),
                ),
              ),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════
  //  BOTTOM BAR
  // ═══════════════════════════════════════════════
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0EA5E9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Pembayaran',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatPrice(widget.totalAmount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : () async {
                      setState(() => _isProcessing = true);
                      try {
                        final user = AuthService().currentUser;
                        if (user == null) {
                          setState(() => _isProcessing = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sesi login habis. Silakan login ulang.',
                              ),
                            ),
                          );
                          return;
                        }

                        final shopId = widget.laundry['id']?.toString() ?? '';
                        if (shopId.isEmpty) {
                          setState(() => _isProcessing = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Data toko tidak valid. Silakan kembali dan pilih toko kembali.',
                              ),
                            ),
                          );
                          return;
                        }

                        final order = OrderModel(
                          id: '',
                          userId: user.id,
                          shopId: shopId,
                          shopName: widget.laundry['name'] ?? 'Laundry Shop',
                          items: widget.items,
                          status: 'pending',
                          totalPrice: widget.totalAmount,
                          serviceFee: 2000,
                          notes: widget.notes.isEmpty ? null : widget.notes,
                          paymentMethod: _selectedMethod,
                          createdAt: DateTime.now(),
                        );
                        final orderId = await SupabaseService().createOrder(
                          order,
                        );

                        if (!mounted) return;

                        final Widget destination = widget.isDropoff
                            ? DropoffTrackingPage(orderId: orderId)
                            : OrderTrackingPage(orderId: orderId);

                        Navigator.pushAndRemoveUntil(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    destination,
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) {
                                  final curve = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  );
                                  return FadeTransition(
                                    opacity: Tween<double>(
                                      begin: 0.0,
                                      end: 1.0,
                                    ).animate(curve),
                                    child: child,
                                  );
                                },
                            transitionDuration: const Duration(
                              milliseconds: 600,
                            ),
                          ),
                          (route) => route.isFirst,
                        );
                      } catch (e) {
                        setState(() => _isProcessing = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal membuat pesanan: $e')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
                elevation: 6,
                shadowColor: const Color(0xFF0C4A6E).withValues(alpha: 0.3),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : const Text(
                      'Konfirmasi Pesanan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
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
  final String? imageUrl;

  const _PaymentMethod({
    required this.id,
    required this.name,
    required this.subtitle,
    this.icon,
    this.imageUrl,
  });
}
