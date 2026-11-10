import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/washora_logo.dart';
import '../widgets/quick_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'order_tracking_page.dart';
import 'dropoff_tracking_page.dart';
import '../models/order_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/promo_service.dart';
import '../models/shop_promo_model.dart';
import '../models/promo_checkout.dart';
import '../widgets/promo_checkout_card.dart';
import '../models/membership_models.dart';
import '../services/membership_service.dart';

class PaymentMethodPage extends StatefulWidget {
  final bool isDropoff;
  final Map<String, dynamic> laundry;
  final List<OrderItem> items;
  final int totalAmount;
  final String notes;

  /// Ongkir kurir yang sudah termasuk di [totalAmount] (untuk promo gratis ongkir)
  final int deliveryFee;

  const PaymentMethodPage({
    super.key,
    this.isDropoff = false,
    required this.laundry,
    required this.items,
    required this.totalAmount,
    required this.notes,
    this.deliveryFee = 0,
  });

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  String _selectedMethod = 'dana';
  bool _isProcessing = false;

  // ── Promo outlet ──
  List<PromoQuote> _quotes = [];
  PromoQuote? _applied;
  bool _promoLoading = true;

  // ── Benefit member (gratis ongkir & poin) ──
  MemberBenefits _benefits = MemberBenefits.none;
  bool _useFreeDelivery = false;
  bool _usePoints = false;

  int get _itemsSubtotal => widget.items.fold<num>(0, (s, i) => s + i.price * i.qty).round();

  /// Gratis ongkir member hanya untuk antar-jemput yang memang berongkir
  bool get _freeDeliveryEligible => !widget.isDropoff && widget.deliveryFee > 0 && _benefits.canUseFreeDelivery;
  int get _memberDelivery => _useFreeDelivery && _freeDeliveryEligible ? widget.deliveryFee : 0;
  int get _discount => _applied?.discount ?? 0;

  /// Poin dipakai sebesar-besarnya tanpa melebihi saldo, harga layanan, atau sisa tagihan
  int get _pointsUsed {
    if (!_usePoints || _benefits.pointsBalance <= 0) return 0;
    final remaining = widget.totalAmount - _discount - _memberDelivery;
    return [_benefits.pointsBalance, _itemsSubtotal, remaining < 0 ? 0 : remaining].reduce((a, b) => a < b ? a : b);
  }

  int get _payable =>
      (widget.totalAmount - _discount - _memberDelivery - _pointsUsed).clamp(0, widget.totalAmount);

  // ── Nomor WhatsApp pelanggan (agar mitra bisa menghubungi bila mendesak) ──
  final _waCtrl = TextEditingController();
  String? _waError;
  static const _kFakeDefaultPhone = '0812-3456-7890';

  @override
  void initState() {
    super.initState();
    _loadBenefitsThenPromos();
    _loadSavedPhone();
  }

  @override
  void dispose() {
    _waCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('pref_phone') ?? '';
      if (mounted && saved.isNotEmpty && saved != _kFakeDefaultPhone && _waCtrl.text.isEmpty) {
        _waCtrl.text = saved;
      }
    } catch (_) {}
  }

  /// null = valid; selain itu pesan error
  static String? validateWhatsApp(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Nomor WhatsApp wajib diisi agar outlet bisa menghubungi Anda.';
    final local = digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
    if (!local.startsWith('08')) return 'Gunakan nomor HP Indonesia, diawali 08 atau +62.';
    if (local.length < 10 || local.length > 13) return 'Panjang nomor HP tidak sesuai (10–13 digit).';
    return null;
  }

  Future<void> _loadBenefitsThenPromos({String? keepId}) async {
    final b = await MembershipService().fetchBenefits();
    if (!mounted) return;
    setState(() {
      _benefits = b;
      // Gratis ongkir member otomatis dipakai jika berhak
      _useFreeDelivery = _freeDeliveryEligible;
      if (b.pointsBalance <= 0) _usePoints = false;
    });
    await _loadPromos(keepId: keepId);
  }

  /// Ambil promo aktif outlet lalu hitung potongannya untuk keranjang ini.
  /// [keepId] = pertahankan promo yang sedang dipilih jika masih berlaku.
  Future<void> _loadPromos({String? keepId}) async {
    final shopId = widget.laundry['id']?.toString() ?? '';
    if (shopId.isEmpty || shopId.startsWith('dummy-')) {
      if (mounted) setState(() => _promoLoading = false);
      return;
    }
    final promos = await PromoService().getActiveCustomerPromos(shopId);
    if (!mounted) return;
    final quotes = promos
        .where((p) => p.type != ShopPromoType.cashback)
        .map((p) => quotePromo(
              p,
              items: widget.items,
              shopServices: (widget.laundry['services'] as List?) ?? const [],
              // Ongkir yang sudah digratiskan member tidak bisa digratiskan lagi oleh promo
              deliveryFee: widget.isDropoff || _memberDelivery > 0 ? 0 : widget.deliveryFee,
              isDropoff: widget.isDropoff,
            ))
        .toList();
    setState(() {
      _quotes = quotes;
      _promoLoading = false;
      _applied = keepId != null
          ? quotes.where((q) => q.promo.id == keepId && q.usable).firstOrNull
          : bestAutoPromo(quotes);
    });
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  // ── Payment method data ──
  static const List<_PaymentCategory> _categories = [
    _PaymentCategory(
      title: 'QRIS (Semua E-Wallet & Bank)',
      methods: [
        _PaymentMethod(
          id: 'qris',
          name: 'QRIS Nasional',
          subtitle: 'Scan cepat via BCA, Mandiri, BRI, DANA, GoPay, OVO, ShopeePay',
          icon: Icons.qr_code_scanner_rounded,
          badge: 'Instan Bebas Admin',
        ),
      ],
    ),
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
      final shopId = widget.laundry['id']?.toString();

      // Tanpa user & outlet yang valid, pesanan tidak akan pernah sampai ke mitra
      if (user == null) {
        throw 'Sesi login berakhir. Silakan login ulang lalu pesan kembali.';
      }
      if (shopId == null || shopId.isEmpty || shopId.startsWith('dummy-')) {
        throw 'Outlet tidak valid. Silakan pilih outlet dari Beranda.';
      }

      final phone = _waCtrl.text.trim();
      final waErr = validateWhatsApp(phone);
      if (waErr != null) {
        setState(() => _waError = waErr);
        throw waErr;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pref_phone', phone);
      } catch (_) {}

      final order = OrderModel(
        id: '',
        userId: user.id,
        customerPhone: phone,
        shopId: shopId,
        shopName: widget.laundry['name'] ?? 'CleanPro Kemang',
        items: widget.items,
        status: 'pending',
        totalPrice: _payable,
        serviceFee: 2000,
        notes: widget.notes.isEmpty ? null : widget.notes,
        paymentMethod: _selectedMethod,
        createdAt: DateTime.now(),
        deliveryType: widget.isDropoff ? 'dropoff' : 'pickup',
        promoId: _applied?.promo.id,
        promoTitle: _applied?.promo.title,
        discountAmount: _discount,
        memberFreeDelivery: _memberDelivery > 0,
        pointsUsed: _pointsUsed,
      );

      String orderId;
      try {
        orderId = await SupabaseService().createOrder(order);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('tidak menerima pesanan')) {
          throw 'Outlet ini sedang tidak menerima pesanan aplikasi. Coba outlet lain.';
        }
        // Benefit member ditolak server (kuota habis, poin kurang, langganan berakhir)
        final memberReason = RegExp(r'(Kuota gratis ongkir[^,)]*|Gratis ongkir member[^,)]*|Poin [^,)]*)').firstMatch(msg)?.group(0);
        if (memberReason != null) {
          await _loadBenefitsThenPromos(keepId: _applied?.promo.id);
          throw '${memberReason.trim()}. Periksa total, lalu konfirmasi lagi.';
        }
        if ((_memberDelivery > 0 || _pointsUsed > 0) &&
            (msg.contains('member_free_delivery') || msg.contains('points_used'))) {
          setState(() {
            _useFreeDelivery = false;
            _usePoints = false;
          });
          throw 'Benefit member belum aktif di database. Benefit dilepas, silakan konfirmasi lagi.';
        }
        if (_applied != null) {
          // Kolom promo belum dibuat di database
          if (msg.contains('promo_id') || msg.contains('discount_amount')) {
            setState(() => _applied = null);
            throw 'Promo belum aktif di database outlet. Promo dilepas, silakan konfirmasi lagi.';
          }
          // Ditolak server: kuota habis, kedaluwarsa, minimal belanja, dll.
          final reason = RegExp(r'(Promo[^,)]*|Kuota promo[^,)]*|Belum memenuhi minimal[^,)]*|Potongan promo tidak valid)')
              .firstMatch(msg)
              ?.group(0);
          if (reason != null) {
            await _loadPromos(keepId: _applied?.promo.id);
            throw '${reason.trim()}. Periksa promo & total, lalu konfirmasi lagi.';
          }
        }
        throw 'Pesanan gagal dikirim ke outlet. Periksa koneksi lalu coba lagi.';
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
        ScaffoldMessenger.of(context).showQuickSnackBar(
          SnackBar(
            content: Text(e is String ? e : 'Gagal membuat pesanan: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
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
                              if (_benefits.active || _benefits.pointsBalance > 0) ...[
                                _buildMemberCard(),
                                const SizedBox(height: 14),
                              ],
                              PromoCheckoutCard(
                                loading: _promoLoading,
                                quotes: _quotes,
                                applied: _applied,
                                onChanged: (q) => setState(() => _applied = q),
                              ),
                              const SizedBox(height: 14),
                              _buildWhatsAppCard(),
                              const SizedBox(height: 14),
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

  // ══════════════════════════════════════════
  //  BENEFIT MEMBER
  // ══════════════════════════════════════════
  Widget _buildMemberCard() {
    final b = _benefits;
    final left = b.freeDeliveryLeft;
    final String deliverySub;
    if (!b.active) {
      deliverySub = 'Khusus member aktif';
    } else if (widget.isDropoff) {
      deliverySub = 'Hanya untuk antar-jemput kurir';
    } else if (widget.deliveryFee <= 0) {
      deliverySub = 'Ongkir pesanan ini sudah gratis';
    } else if (!b.canUseFreeDelivery) {
      deliverySub = 'Kuota bulan ini sudah habis';
    } else {
      deliverySub = 'Hemat ${_formatPrice(widget.deliveryFee)} · ${left == null ? 'tanpa batas' : 'sisa $left bulan ini'}';
    }
    final pointsValue = _usePoints ? _pointsUsed : [_benefits.pointsBalance, _itemsSubtotal].reduce((a, c) => a < c ? a : c);

    Widget row({required IconData icon, required String title, required String sub, required bool value, ValueChanged<bool>? onChanged}) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: onChanged == null ? const Color(0xFFCBD5E1) : const Color(0xFF0F172A)),
        title: Text(title,
            style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700,
                color: onChanged == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A))),
        subtitle: Text(sub, style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF64748B))),
        value: value,
        onChanged: onChanged,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFFB7791F)),
              const SizedBox(width: 8),
              Text(b.active ? 'Benefit member ${b.planName ?? ''}' : 'Poin kamu',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
            ],
          ),
          if (b.active)
            row(
              icon: Icons.local_shipping_outlined,
              title: 'Gratis ongkir member',
              sub: deliverySub,
              value: _memberDelivery > 0,
              onChanged: _freeDeliveryEligible
                  ? (v) {
                      setState(() => _useFreeDelivery = v);
                      _loadPromos(keepId: _applied?.promo.id);
                    }
                  : null,
            ),
          if (b.pointsBalance > 0)
            row(
              icon: Icons.savings_outlined,
              title: 'Pakai poin (saldo ${b.pointsBalance})',
              sub: _usePoints ? 'Memotong ${_formatPrice(_pointsUsed)}' : 'Bisa memotong hingga ${_formatPrice(pointsValue)} · 1 poin = Rp 1',
              value: _usePoints,
              onChanged: (v) => setState(() => _usePoints = v),
            ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _waError != null ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              Text('Nomor WhatsApp',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 4),
          Text('Dipakai outlet untuk menghubungi Anda bila ada hal mendesak tentang cucian.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          const SizedBox(height: 10),
          TextField(
            controller: _waCtrl,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (_) {
              if (_waError != null) setState(() => _waError = null);
            },
            decoration: InputDecoration(
              hintText: '08xx-xxxx-xxxx',
              prefixIcon: const Icon(Icons.phone_rounded),
              errorText: _waError,
              errorMaxLines: 2,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
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
                _formatPrice(_payable),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
              if (method.id == 'qris' && isSelected) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFDBEAFE)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'QRIS',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'PEMBAYARAN RESMI BERLISENSI BI',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 160,
                        height: 160,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.qr_code_2_rounded,
                              size: 144,
                              color: Color(0xFF0F172A),
                            ),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF0077E6), width: 1.5),
                              ),
                              child: const WashoraLogo(size: 18),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'NMID: ID102003928192801',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF475569),
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Buka m-Banking atau E-Wallet apa saja lalu scan kode QR di atas.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                  _formatPrice(_payable),
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

/// Akses validasi nomor WA untuk unit test
class PaymentMethodPageStateTest {
  static String? validate(String input) => _PaymentMethodPageState.validateWhatsApp(input);
}
