import 'dart:async';
import '../utils/tap_guard.dart';
import '../widgets/quick_snackbar.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'outlet_settings_screen.dart';
import 'revenue_report_screen.dart';
import 'today_transactions_screen.dart';
import 'service_history_screen.dart';
import 'owner_promo_screen.dart';
import 'chat_room_screen.dart';
import 'owner_reviews_screen.dart';
import 'receipt_print_screen.dart';
import 'wallet_screen.dart';
import '../services/wallet_service.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/washora_logo.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/evidence_models.dart';
import '../models/order_model.dart';
import '../models/service_model.dart';
import '../models/shop_model.dart';
import '../services/auth_service.dart';
import '../services/evidence_service.dart';
import '../services/supabase_service.dart';
import 'owner_claims_screen.dart';
import 'owner_evidence_sheets.dart';
import 'role_selection_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  final AuthService _authService = AuthService();
  final SupabaseService _supabaseService = SupabaseService();

  bool _isLoading = true;
  String? _loadError;
  String? _shopLoadErrorDetail;
  String _activeFilter = 'Semua';

  ShopModel? _shop;
  int _walletRefresh = 0;
  List<OrderModel> _orders = [];
  StreamSubscription<List<OrderModel>>? _ordersSub;

  // Klaim kerusakan dari pelanggan (realtime) — ditampilkan sebagai banner di atas Recent Order
  final EvidenceService _evidenceService = EvidenceService();
  Stream<List<DamageClaim>>? _claimsStream;

  // Realtime Supabase tidak mengirim event DELETE ke stream yang difilter
  // (.eq('shop_id', ...)), jadi pesanan yang dihapus dicatat di sini agar
  // tidak muncul lagi saat stream mengirim data berikutnya.
  final Set<String> _deletedOrderIds = {};

  void _removeOrdersLocally(Iterable<String> ids) {
    _deletedOrderIds.addAll(ids);
    setState(() => _orders = _orders.where((o) => !_deletedOrderIds.contains(o.id)).toList());
  }

  // Sambung ulang otomatis saat koneksi realtime terputus (mis. internet putus sesaat)
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _isReconnecting = false;

  // Form "Daftarkan Outlet" (tampil jika akun belum punya outlet)
  final _shopFormKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _shopAddressCtrl = TextEditingController();
  final _shopPriceCtrl = TextEditingController(text: '10000');
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 21, minute: 0);
  bool _is24Hours = false;
  bool _isRegisteringShop = false;
  String? _registerShopError;

  // Status DB → label & warna tampilan
  static const List<String> _statusOrder = ['pending', 'washing', 'drying', 'done', 'delivered'];
  static const Map<String, String> _statusLabels = {
    'pending': 'Antrean',
    'washing': 'Pencucian',
    'drying': 'Pengeringan',
    'done': 'Selesai',
    'delivered': 'Diantar',
    'cancelled': 'Dibatalkan',
  };
  static const Map<String, Color> _statusColors = {
    'pending': Color(0xFF64748B),
    'washing': Color(0xFF0284C7),
    'drying': Color(0xFFF59E0B),
    'done': Color(0xFF10B981),
    'delivered': Color(0xFF7C3AED),
    'cancelled': Color(0xFFEF4444),
  };

  // Layanan kasir walk-in: label, harga, satuan
  static const List<Map<String, dynamic>> _walkInServices = [
    {'name': 'REGULER CUCI SETRIKA', 'label': 'Reguler Cuci Setrika (Rp 10.000/Kg)', 'price': 10000, 'unit': 'kg'},
    {'name': 'CUCI KERING LIPAT', 'label': 'Cuci Kering Lipat (Rp 8.000/Kg)', 'price': 8000, 'unit': 'kg'},
    {'name': 'EXPRESS CUCI SETRIKA', 'label': 'Express 6 Jam (Rp 15.000/Kg)', 'price': 15000, 'unit': 'kg'},
    {'name': 'BED COVER & SELIMUT', 'label': 'Bed Cover / Satuan (Rp 25.000/Pcs)', 'price': 25000, 'unit': 'pcs'},
  ];

  /// Layanan kasir walk-in = layanan aktif dari "Tarif Layanan" outlet.
  /// Jika outlet belum mengatur katalog, pakai daftar bawaan di atas.
  List<Map<String, dynamic>> _walkInServiceOptions() {
    final active = (_shop?.services ?? const <ServiceModel>[]).where((s) => s.isActive && s.price > 0).toList();
    if (active.isEmpty) return _walkInServices;
    return active.map((s) {
      final unit = s.unit.replaceAll('/', '').trim().toLowerCase(); // '/ kg' → 'kg'
      final unitLabel = unit.isEmpty ? '' : '${unit[0].toUpperCase()}${unit.substring(1)}';
      return <String, dynamic>{
        'name': s.name.toUpperCase(),
        'label': '${s.name} (${_formatRupiah(s.price)}/$unitLabel)',
        'price': s.price,
        'unit': unit.isEmpty ? 'kg' : unit,
      };
    }).toList();
  }


  @override
  void initState() {
    super.initState();
    _loadShopAndOrders();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _ordersSub?.cancel();
    _shopNameCtrl.dispose();
    _shopAddressCtrl.dispose();
    _shopPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShopAndOrders() async {
    if (mounted && _loadError != null) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    ShopModel? shop;
    Object? lastError;
    // Dicoba hingga 3x: koneksi HP sering belum stabil sesaat setelah login
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        shop = await _supabaseService.fetchMyShopStrict();
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('Gagal memuat outlet (percobaan ${attempt + 1}): $e');
        await Future.delayed(Duration(seconds: 1 + attempt * 2));
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    if (lastError != null) {
      setState(() {
        _isLoading = false;
        _loadError = 'shop_error';
        _shopLoadErrorDetail = '$lastError';
      });
      return;
    }
    if (shop == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'no_shop';
      });
      return;
    }

    setState(() => _shop = shop);
    _listenOrders(shop);
  }

  void _listenOrders(ShopModel shop) {
    _claimsStream ??= _evidenceService.getShopClaims(shop.id);
    _reconnectTimer?.cancel();
    _ordersSub?.cancel();
    _ordersSub = _supabaseService.getShopOrders(shop.id).listen(
      (orders) {
        _reconnectAttempt = 0;
        if (mounted) {
          setState(() {
            _orders = orders.where((o) => !_deletedOrderIds.contains(o.id)).toList();
            _isLoading = false;
            _isReconnecting = false;
            _loadError = null;
          });
        }
      },
      onError: (e) {
        debugPrint('Error stream pesanan toko: $e');
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _isReconnecting = true;
          // Pesanan yang sudah tampil tetap dipertahankan; error hanya jika belum ada data
          if (_orders.isEmpty) {
            _loadError = 'Koneksi terputus. Menyambungkan ulang...';
          }
        });
        _scheduleReconnect(shop);
      },
    );
  }

  /// Coba sambung ulang dengan jeda bertahap: 2, 4, 8, 16, lalu maks. 30 detik
  void _scheduleReconnect(ShopModel shop) {
    _reconnectTimer?.cancel();
    final delay = Duration(seconds: math.min(30, 2 << _reconnectAttempt));
    _reconnectAttempt = math.min(_reconnectAttempt + 1, 5);
    _reconnectTimer = Timer(delay, () {
      if (mounted && _shop?.id == shop.id) _listenOrders(shop);
    });
  }

  String _getMonthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return (m >= 1 && m <= 12) ? months[m - 1] : '';
  }

  String _formatDate(DateTime d) => '${d.day} ${_getMonthName(d.month)} ${d.year}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _formatRupiah(num amount) {
    return 'Rp. ${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}';
  }

  String _formatQty(num qty) =>
      qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(1);

  String _statusLabel(String status) => _statusLabels[status] ?? 'Antrean';

  Color _statusColor(String status) => _statusColors[status] ?? const Color(0xFF64748B);

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isActive(OrderModel o) =>
      o.status != 'done' && o.status != 'delivered' && o.status != 'cancelled';

  String _customerName(OrderModel o) =>
      (o.customerName != null && o.customerName!.trim().isNotEmpty) ? o.customerName! : 'Pelanggan';

  String _orderCode(OrderModel o) => o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id;

  String _serviceName(OrderModel o) => o.items.isNotEmpty ? o.items.first.name.toUpperCase() : 'CUCI REGULER';

  String _itemsSummary(OrderModel o) {
    if (o.items.isEmpty) return '';
    final first = o.items.first;
    final unit = first.unit.replaceAll('/', '').trim();
    final extra = o.items.length > 1 ? ' +${o.items.length - 1}' : '';
    return '${_formatQty(first.qty)} ${unit.isEmpty ? '' : unit[0].toUpperCase() + unit.substring(1)}$extra'.trim();
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Konfirmasi Keluar', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin keluar dari Dashboard Mitra?', style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Keluar', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  /// Ubah 08xx / +628xx menjadi 628xx untuk tautan wa.me
  String? _normalizePhone(String? phone) {
    if (phone == null) return null;
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('0')) digits = '62${digits.substring(1)}';
    return digits;
  }

  Future<void> _sendWhatsAppNota(OrderModel order) async {
    final phone = _normalizePhone(order.customerPhone);
    if (phone == null) {
      _showSnack('Nomor WhatsApp pelanggan belum tersedia untuk pesanan ini.', color: const Color(0xFFEF4444));
      return;
    }

    final lines = <String>[
      'Halo ${_customerName(order)}, berikut nota laundry Anda:',
      '',
      '*${_shop?.name ?? 'Washora'}*',
      'No. Nota: ${_orderCode(order)}',
      'Tanggal: ${_formatDate(order.createdAt)} ${_formatTime(order.createdAt)}',
      '',
      ...order.items.map((i) => '- ${i.name} (${_formatQty(i.qty)} ${i.unit.replaceAll('/', '').trim()})'),
      '',
      'Total: ${_formatRupiah(order.totalPrice)}',
      'Status: ${_statusLabel(order.status)}',
      '',
      'Terima kasih!',
    ];

    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(lines.join('\n'))}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('Tidak dapat membuka WhatsApp.', color: const Color(0xFFEF4444));
    }
  }

  // ================= MODAL DIALOGS =================

  // 1. Order Baru (Kasir Walk-In)
  void _showNewOrderDialog() {
    final shop = _shop;
    if (shop == null) {
      _showSnack('Akun belum terhubung ke outlet.', color: const Color(0xFFEF4444));
      return;
    }

    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final weightCtrl = TextEditingController(text: '3.0');
    final walkInServices = _walkInServiceOptions();
    Map<String, dynamic> selectedService = walkInServices.first;
    bool isSaving = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final double weight = double.tryParse(weightCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final int pricePerUnit = selectedService['price'] as int;
          final int estPrice = (weight * pricePerUnit).round();

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_shopping_cart_rounded, color: Color(0xFF0077B6)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Input Pesanan Baru (Kasir)',
                            style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nama Pelanggan',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Nomor WhatsApp',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: walkInServices.indexOf(selectedService),
                    decoration: InputDecoration(
                      labelText: 'Pilihan Layanan',
                      prefixIcon: const Icon(Icons.local_laundry_service_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < walkInServices.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(walkInServices[i]['label'] as String, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setModalState(() => selectedService = walkInServices[val]);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: selectedService['unit'] == 'kg' ? 'Berat Cucian (Kg)' : 'Jumlah (${selectedService['unit']})',
                      prefixIcon: const Icon(Icons.scale_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimasi Biaya:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF166534))),
                        Text(_formatRupiah(estPrice), style: GoogleFonts.quicksand(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF15803D))),
                      ],
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0077B6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final phone = phoneCtrl.text.trim();
                              if (name.isEmpty) {
                                setModalState(() => errorText = 'Nama pelanggan wajib diisi.');
                                return;
                              }
                              if (weight <= 0) {
                                setModalState(() => errorText = 'Berat / jumlah harus lebih dari 0.');
                                return;
                              }
                              setModalState(() {
                                isSaving = true;
                                errorText = null;
                              });

                              final order = OrderModel(
                                id: '',
                                userId: '',
                                shopId: shop.id,
                                shopName: shop.name,
                                items: [
                                  OrderItem(
                                    name: selectedService['name'] as String,
                                    qty: weight,
                                    price: pricePerUnit,
                                    unit: selectedService['unit'] as String,
                                  ),
                                ],
                                status: 'pending',
                                totalPrice: estPrice,
                                serviceFee: 0,
                                paymentMethod: 'cash',
                                createdAt: DateTime.now(),
                                customerName: name,
                                customerPhone: phone.isEmpty ? null : phone,
                              );

                              try {
                                await _supabaseService.createOrder(order);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  _showSnack('Pesanan untuk $name berhasil ditambahkan!', color: const Color(0xFF10B981));
                                }
                              } catch (e) {
                                setModalState(() {
                                  isSaving = false;
                                  errorText = 'Gagal menyimpan pesanan: $e';
                                });
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Text(
                              'Simpan & Buat Nota',
                              style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
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

  // 2. Update Status Pesanan Modal
  void _showOrderActionModal(OrderModel order) {
    final statusColor = _statusColor(order.status);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _customerName(order),
                        style: GoogleFonts.quicksand(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        '${_orderCode(order)} • ${_serviceName(order)}',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Catatan: ${order.notes}',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155)),
              ),
            ],
            const Divider(height: 32),
            Text(
              'Ubah Tahapan Proses Cucian:',
              style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statusOrder.map((s) => _buildStatusButton(s, order, ctx)).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPrintScreen(orderId: order.id)));
                },
                icon: const Icon(Icons.print_rounded),
                label: Text('Cetak Resi', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _sendWhatsAppNota(order);
                    },
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                    label: Text(
                      'Kirim WA Nota',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF25D366)),
                    ),
                  ),
                ),
                // Chat di aplikasi hanya untuk pelanggan yang punya akun (bukan walk-in)
                if (order.userId.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF0077B6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        openChatForOrder(context, order.id);
                      },
                      icon: const Icon(Icons.forum_outlined, color: Color(0xFF0077B6)),
                      label: Text(
                        'Chat Pelanggan',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF0077B6)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (order.status != 'cancelled') ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: const Color(0xFFFEF2F2),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCancelOrderConfirmation(order);
                  },
                  icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
                  label: Text(
                    'Batalkan Pesanan Ini',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                  ),
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    Text(
                      'Pesanan ini telah Dibatalkan',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showDeleteOrderConfirmation(order);
                  },
                  icon: const Icon(Icons.delete_forever_rounded, size: 20),
                  label: Text(
                    'Hapus Pesanan dari Daftar',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCancelOrderConfirmation(OrderModel order) {
    String selectedReason = 'Permintaan Pelanggan';
    final customReasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Batalkan Pesanan?',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apakah Anda yakin ingin membatalkan pesanan ${_orderCode(order)} atas nama ${_customerName(order)}?',
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pilih Alasan Pembatalan:',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Permintaan Pelanggan', child: Text('Permintaan Pelanggan')),
                    DropdownMenuItem(value: 'Salah Input Pesanan', child: Text('Salah Input Pesanan')),
                    DropdownMenuItem(value: 'Kendala Mesin / Operasional', child: Text('Kendala Mesin / Operasional')),
                    DropdownMenuItem(value: 'Bahan Cuci Habis', child: Text('Bahan Cuci Habis')),
                    DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDlgState(() => selectedReason = val);
                    }
                  },
                ),
                if (selectedReason == 'Lainnya') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: customReasonCtrl,
                    decoration: InputDecoration(
                      hintText: 'Tuliskan alasan...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('Kembali', style: GoogleFonts.inter(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final reason = selectedReason == 'Lainnya' && customReasonCtrl.text.trim().isNotEmpty
                    ? customReasonCtrl.text.trim()
                    : selectedReason;
                Navigator.pop(dlgCtx);
                final success = await _supabaseService.updateOrderStatus(order.id, 'cancelled');
                if (mounted) {
                  _showSnack(
                    success ? 'Pesanan ${_orderCode(order)} berhasil dibatalkan ($reason)' : _statusUpdateFailMessage(),
                    color: success ? const Color(0xFFEF4444) : Colors.grey,
                  );
                }
              },
              child: Text(
                'Ya, Batalkan Pesanan',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteOrderConfirmation(OrderModel order) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Hapus Pesanan?',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Pesanan #${_orderCode(order)} atas nama ${_customerName(order)} akan dihapus permanen dari sistem database.\n\nTindakan ini tidak dapat dibatalkan.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: Text('Batal', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              final messenger = ScaffoldMessenger.of(context);
              final success = await _supabaseService.deleteOrder(order.id);
              if (success && mounted) _removeOrdersLocally([order.id]);
              if (mounted) {
                messenger.showQuickSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Pesanan #${_orderCode(order)} berhasil dihapus permanen.'
                        : 'Gagal menghapus pesanan.'),
                    backgroundColor: success ? const Color(0xFFEF4444) : Colors.grey,
                  ),
                );
              }
            },
            child: Text(
              'Hapus Permanen',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }


  /// Pesan gagal ubah status yang menjelaskan penyebabnya. Penyebab paling umum:
  /// sesi login di browser berganti ke akun lain (mis. login pengguna di tab lain
  /// pada jendela yang sama), sehingga database menolak karena bukan pemilik outlet.
  String _statusUpdateFailMessage() {
    final user = _authService.currentUser;
    if (user == null) {
      return 'Sesi login berakhir. Silakan keluar lalu login ulang sebagai mitra.';
    }
    final ownerId = _shop?.ownerId;
    if (ownerId != null && user.id != ownerId) {
      return 'Browser ini sekarang login sebagai ${user.email ?? 'akun lain'}, bukan pemilik outlet. '
          'Keluar lalu login ulang sebagai mitra (pakai jendela Incognito untuk akun pengguna).';
    }
    return 'Gagal mengubah status. Periksa koneksi lalu coba lagi.';
  }

  Widget _buildStatusButton(String status, OrderModel order, BuildContext ctx) {
    final bool isCurrent = order.status == status;
    final color = _statusColor(status);
    return GestureDetector(
      onTap: () async {
        if (isCurrent) return;
        final messenger = ScaffoldMessenger.of(context);

        // Serah terima: status "Diantar" hanya lewat kode pelanggan + foto
        if (status == 'delivered') {
          if (ctx.mounted) Navigator.pop(ctx);
          if (order.status != 'done') {
            messenger.showQuickSnackBar(const SnackBar(
              content: Text('Ubah status ke "Selesai" dulu sebelum serah terima ke pelanggan.'),
            ));
            return;
          }
          final ok = await showHandoverSheet(context, order);
          if (ok) {
            messenger.showQuickSnackBar(const SnackBar(
              content: Text('Serah terima tercatat. Pesanan diterima pelanggan.'),
              backgroundColor: Color(0xFF10B981),
            ));
          }
          return;
        }

        // Bukti penerimaan: foto kondisi wajib sebelum cucian mulai diproses
        if (order.status == 'pending' && status != 'cancelled' && order.intakeAt == null) {
          if (ctx.mounted) Navigator.pop(ctx);
          final ok = await showIntakeSheet(context, order);
          if (!ok) return;
        }

        final success = await _supabaseService.updateOrderStatus(order.id, status);
        if (ctx.mounted) Navigator.pop(ctx);
        messenger.showQuickSnackBar(
          SnackBar(
            content: Text(success
                ? 'Status pesanan diubah ke ${_statusLabel(status)}'
                : _statusUpdateFailMessage()),
            backgroundColor: success ? null : const Color(0xFFEF4444),
            duration: Duration(seconds: success ? 3 : 6),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: isCurrent ? 1.0 : 0.4)),
        ),
        child: Text(
          _statusLabel(status),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isCurrent ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  // 3. Petty Cash Modal
  bool _pettyOpening = false;

  Future<void> _showPettyCashModal() async {
    if (_pettyOpening) return;
    _pettyOpening = true;
    try {
      await _showPettyCashModalInner();
    } finally {
      _pettyOpening = false;
    }
  }

  Future<void> _showPettyCashModalInner() async {
    final shop = _shop;
    if (shop == null) {
      _showSnack('Akun belum terhubung ke outlet.', color: const Color(0xFFEF4444));
      return;
    }

    var pettyCashList = await _supabaseService.getPettyCash(shop.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final balance = pettyCashList.fold<int>(
            0,
            (sum, item) => sum + ((item['type'] == 'in' ? 1 : -1) * (item['amount'] as int)),
          );

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD97706)),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Petty Cash (Kas Kecil)',
                          style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sisa Saldo Kasir:', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_formatRupiah(balance), style: GoogleFonts.quicksand(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0077B6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final added = await _showAddPettyCashDialog(shop.id);
                          if (added) {
                            final refreshed = await _supabaseService.getPettyCash(shop.id);
                            setModalState(() => pettyCashList = refreshed);
                          }
                        },
                        child: const Text('+ Catat Kas'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Riwayat Transaksi Kasir:', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                Expanded(
                  child: pettyCashList.isEmpty
                      ? Center(child: Text('Belum ada catatan kas', style: GoogleFonts.inter(color: Colors.grey)))
                      : ListView.separated(
                          itemCount: pettyCashList.length,
                          separatorBuilder: (context, index) => const Divider(height: 16),
                          itemBuilder: (context, idx) {
                            final item = pettyCashList[idx];
                            final isOut = item['type'] == 'out';
                            final createdAt = item['created_at'] != null
                                ? DateTime.parse(item['created_at']).toLocal()
                                : DateTime.now();
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isOut ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                                        radius: 18,
                                        child: Icon(
                                          isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                          size: 18,
                                          color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['title'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                                            Text(_formatDate(createdAt), style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isOut ? '-' : '+'}${_formatRupiah(item['amount'] as int)}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Dialog input kas masuk/keluar. Mengembalikan true jika berhasil disimpan.
  Future<bool> _showAddPettyCashDialog(String shopId) async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'out';
    bool isSaving = false;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Catat Kas', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'out', label: Text('Keluar'), icon: Icon(Icons.arrow_upward_rounded)),
                  ButtonSegment(value: 'in', label: Text('Masuk'), icon: Icon(Icons.arrow_downward_rounded)),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDialogState(() => type = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Keterangan',
                  hintText: 'Mis. Beli deterjen 5L',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nominal (Rp)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(errorText!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444))),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
              child: Text('Batal', style: GoogleFonts.inter(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0077B6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final title = titleCtrl.text.trim();
                      final amount = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      if (title.isEmpty || amount <= 0) {
                        setDialogState(() => errorText = 'Isi keterangan dan nominal dengan benar.');
                        return;
                      }
                      setDialogState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await _supabaseService.addPettyCash(shopId: shopId, title: title, type: type, amount: amount);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() {
                          isSaving = false;
                          errorText = 'Gagal menyimpan: $e';
                        });
                      }
                    },
              child: Text('Simpan', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  // 5. Modal Daftar Customer (diringkas dari pesanan toko)
  void _showCustomerModal() {
    final Map<String, Map<String, dynamic>> customers = {};
    for (final o in _orders) {
      final name = _customerName(o);
      final key = o.userId.isNotEmpty ? o.userId : '${name.toLowerCase()}|${o.customerPhone ?? ''}';
      final entry = customers.putIfAbsent(key, () => {
            'name': name,
            'phone': o.customerPhone,
            'orders': 0,
            'total': 0,
            'last': o.createdAt,
          });
      entry['orders'] = (entry['orders'] as int) + 1;
      entry['total'] = (entry['total'] as int) + o.totalPrice;
      entry['phone'] ??= o.customerPhone;
    }
    final list = customers.values.toList()
      ..sort((a, b) => (b['orders'] as int).compareTo(a['orders'] as int));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.people_alt_rounded, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Customer (${list.length})',
                      style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                  ],
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('Belum ada customer', style: GoogleFonts.inter(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (context, index) => const Divider(height: 16),
                      itemBuilder: (context, idx) {
                        final c = list[idx];
                        final name = c['name'] as String;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFE0F2FE),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, color: const Color(0xFF0284C7)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text(
                                    '${c['orders']} pesanan • ${_formatRupiah(c['total'] as int)}',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  _customerPhoneRow(c['phone'] as String?, name),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nomor WA pelanggan + tombol salin & chat (untuk keperluan mendesak)
  Widget _customerPhoneRow(String? phone, String name) {
    final raw = phone?.trim() ?? '';
    final wa = _normalizePhone(raw);
    if (wa == null) {
      return Text('Nomor WA belum ada (pesanan lama / tidak diisi)',
          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8), fontStyle: FontStyle.italic));
    }
    return Row(
      children: [
        const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF16A34A)),
        const SizedBox(width: 4),
        Flexible(
          child: SelectableText(raw,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Salin nomor',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF64748B)),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: raw));
            _showSnack('Nomor $name disalin');
          },
        ),
        IconButton(
          tooltip: 'Chat WhatsApp',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF16A34A)),
          onPressed: () async {
            final ok = await launchUrl(Uri.parse('https://wa.me/$wa'), mode: LaunchMode.externalApplication);
            if (!ok && mounted) _showSnack('WhatsApp tidak bisa dibuka', color: const Color(0xFFEF4444));
          },
        ),
      ],
    );
  }

  // ================= MAIN UI BUILD =================

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _orders.where((o) {
      if (_activeFilter == 'Antrean') return o.status == 'pending';
      if (_activeFilter == 'Proses') return o.status == 'washing' || o.status == 'drying';
      if (_activeFilter == 'Selesai') return o.status == 'done' || o.status == 'delivered';
      if (_activeFilter == 'Siap Diambil') return o.status == 'done';
      if (_activeFilter == 'Dibatalkan') return o.status == 'cancelled';
      if (_activeFilter == 'Deadline') {
        final now = DateTime.now();
        return (o.status == 'pending' || o.status == 'washing' || o.status == 'drying') &&
            (o.items.any((i) => i.name.toLowerCase().contains('express')) ||
                now.difference(o.createdAt).inHours >= 18);
      }
      return true;
    }).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFEDF2F7),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              color: const Color(0xFFF8FAFC),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. HEADER SECTION
                      _buildHeader(),

                      if (_loadError == 'no_shop')
                        _buildRegisterShopForm()
                      else if (_loadError == 'shop_error')
                        _buildShopLoadError()
                      else ...[
                        // 2. QUICK METRIC STATS
                        _buildMetricsRow(),

                        const SizedBox(height: 16),

                        // 2b. SALDO KOMISI
                        _buildWalletCard(),

                        const SizedBox(height: 12),

                        // 3. MENU GRID
                        _buildMenuGrid(),

                        const SizedBox(height: 12),

                        // 3b. LAPORAN & RIWAYAT
                        _buildReportShortcuts(),


                        const SizedBox(height: 18),

                        // 4. QUICK STATUS SUMMARY CARDS (GAMBAR 1)
                        _buildStatusSummaryCards(),

                        const SizedBox(height: 18),

                        // 5. STATUS CUCIAN SECTION WITH STEPPER TIMELINE (GAMBAR 2)
                        _buildStatusCucianSection(filteredOrders),
                      ],

                      const SizedBox(height: 96),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: _shop == null
            ? null
            : FloatingActionButton.extended(
                backgroundColor: const Color(0xFF0077B6),
                elevation: 4,
                onPressed: _showNewOrderDialog,
                icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
                label: Text(
                  '+ Order Baru (POS)',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
      ),
    );
  }

  /// Data outlet gagal dimuat (bukan berarti belum punya outlet)
  Widget _buildShopLoadError() {
    final detail = _shopLoadErrorDetail ?? '';
    final offline = RegExp(r'Socket|host lookup|Connection|timed out|Network', caseSensitive: false).hasMatch(detail);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, color: const Color(0xFFDC2626)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Data outlet gagal dimuat',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              offline
                  ? 'HP tidak bisa terhubung ke server. Periksa koneksi internet (data seluler / Wi-Fi), lalu coba lagi.'
                  : 'Outlet Anda tetap aman, hanya gagal dibaca. Coba lagi; jika terus gagal, kirim pesan di bawah ke admin.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                child: SelectableText(detail,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFF334155))),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _loadShopAndOrders,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= DAFTARKAN OUTLET =================

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isOpen}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? _openTime : _closeTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  Future<void> _submitRegisterShop() async {
    if (!_shopFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isRegisteringShop = true;
      _registerShopError = null;
    });

    try {
      final shop = await _supabaseService.createMyShop(
        name: _shopNameCtrl.text.trim(),
        address: _shopAddressCtrl.text.trim(),
        openHours: _is24Hours ? '24 Jam' : '${_formatTimeOfDay(_openTime)} - ${_formatTimeOfDay(_closeTime)}',
        pricePerKg: int.parse(_shopPriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')),
      );
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _loadError = null;
        _isLoading = true;
        _isRegisteringShop = false;
      });
      _listenOrders(shop);
      _showSnack('Outlet "${shop.name}" berhasil didaftarkan!', color: const Color(0xFF10B981));
    } catch (e) {
      debugPrint('Error createMyShop: $e');
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _isRegisteringShop = false;
        _registerShopError = msg.contains('row-level security') || msg.contains('42501')
            ? 'Akun ini belum diizinkan mendaftarkan outlet. Pastikan akun terdaftar sebagai Mitra dan migrasi database sudah dijalankan.'
            : 'Gagal mendaftarkan outlet: $msg';
      });
    }
  }

  InputDecoration _shopInputDecoration(String label, IconData icon, {String? hint, String? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _buildTimeField({required String label, required TimeOfDay time, required bool isOpen}) {
    return Expanded(
      child: InkWell(
        onTap: _is24Hours ? null : () => _pickTime(isOpen: isOpen),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _is24Hours ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: _is24Hours ? Colors.grey : const Color(0xFF0077B6)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                  Text(
                    _formatTimeOfDay(time),
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _is24Hours ? Colors.grey : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterShopForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _shopFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Color(0xFF0077B6)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daftarkan Outlet',
                        style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      Text(
                        'Satu langkah lagi sebelum mulai menerima pesanan',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _shopNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _shopInputDecoration('Nama Outlet', Icons.local_laundry_service_outlined, hint: 'Mis. Berkah Laundry'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Nama outlet minimal 3 karakter' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shopAddressCtrl,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: _shopInputDecoration('Alamat Lengkap', Icons.location_on_outlined, hint: 'Jalan, nomor, kecamatan, kota'),
              validator: (v) => (v == null || v.trim().length < 5) ? 'Alamat outlet wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shopPriceCtrl,
              keyboardType: TextInputType.number,
              decoration: _shopInputDecoration('Harga Cuci Kiloan per Kg', Icons.payments_outlined, prefix: 'Rp '),
              validator: (v) {
                final price = int.tryParse((v ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
                if (price == null || price < 1000) return 'Masukkan harga minimal Rp 1.000';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jam Operasional',
                  style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                ),
                Row(
                  children: [
                    Text('Buka 24 Jam', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    Switch(
                      value: _is24Hours,
                      activeThumbColor: const Color(0xFF0077B6),
                      onChanged: (v) => setState(() => _is24Hours = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTimeField(label: 'Buka', time: _openTime, isOpen: true),
                const SizedBox(width: 12),
                _buildTimeField(label: 'Tutup', time: _closeTime, isOpen: false),
              ],
            ),
            if (_registerShopError != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _registerShopError!,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626), fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isRegisteringShop ? null : _submitRegisterShop,
                child: _isRegisteringShop
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(
                        'Daftarkan & Mulai Terima Pesanan',
                        style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Foto, layanan & tarif lain bisa diatur nanti.',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // ── 1. BLUE HEADER BACKGROUND WITH DECORATIVE BUBBLES ──
        Container(
          width: double.infinity,
          height: topPadding + 140,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF00C6FF), // Bright vibrant cyan
                Color(0xFF0099FF), // Sky blue
                Color(0xFF0077B6), // Ocean blue
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Bubble 1 (top right)
              Positioned(
                top: -30,
                right: -20,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
              // Bubble 2 (top left)
              Positioned(
                top: 15,
                left: -25,
                child: Container(
                  width: 75,
                  height: 75,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              // Bubble 3 (center small)
              Positioned(
                top: 10,
                left: 110,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
              ),
              // Bubble 4 (lower right)
              Positioned(
                bottom: 20,
                right: 70,
                child: Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),

              // Logo & Action Row
              Padding(
                padding: EdgeInsets.only(
                  top: topPadding + 10,
                  left: 20,
                  right: 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Washora Logo (matching user screenshot)
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: WashoraLogo(size: 30),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'WASHORA',
                              style: GoogleFonts.quicksand(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              'Mitra Laundry',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Chat pelanggan + Logout
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    ChatInboxButton(
                      asOwner: true,
                      onDark: true,
                      onNewMessage: (c) => _showSnack(
                        'Pesan baru dari ${c.partnerName(c.ownerId)} (Pesanan #${c.orderCode})',
                        color: const Color(0xFF0077B6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handleLogout,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.logout_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Keluar',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 2. WHITE OVERLAPPING DASHBOARD CARD ──
        Container(
          margin: EdgeInsets.only(
            top: topPadding + 76,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0077B6).withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Owner info & Topup Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Owner Tag + Date + Shop Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Owner',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0284C7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(now),
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _shop?.name ?? (_isLoading ? 'Memuat outlet...' : 'Alfa Bravo Laundry'),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // Pesanan yang dibatalkan tidak dihitung sebagai omzet
    final todayOmzet = _orders
        .where((o) => o.status != 'cancelled' && _isSameDay(o.createdAt, now))
        .fold<int>(0, (sum, o) => sum + o.totalPrice);
    final yesterdayOmzet = _orders
        .where((o) => o.status != 'cancelled' && _isSameDay(o.createdAt, yesterday))
        .fold<int>(0, (sum, o) => sum + o.totalPrice);

    String omzetSubtitle;
    if (yesterdayOmzet > 0) {
      final pct = ((todayOmzet - yesterdayOmzet) / yesterdayOmzet * 100).round();
      omzetSubtitle = '${pct >= 0 ? '+' : ''}$pct% vs kemarin';
    } else {
      omzetSubtitle = 'Belum ada data kemarin';
    }

    final activeOrders = _orders.where(_isActive).toList();
    final activeKg = activeOrders
        .expand((o) => o.items)
        .where((i) => i.unit.toLowerCase().contains('kg'))
        .fold<num>(0, (sum, i) => sum + i.qty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              title: 'Omzet Hari Ini',
              value: _formatRupiah(todayOmzet),
              subtitle: omzetSubtitle,
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF0077B6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetricCard(
              title: 'Cucian Aktif',
              value: '${activeOrders.length} Nota',
              subtitle: '${_formatQty(activeKg)} Kg aktif',
              icon: Icons.local_mall_outlined,
              color: const Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.quicksand(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menu',
                style: GoogleFonts.quicksand(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Operasional',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              // Warna = kelompok fungsi: biru transaksi, kuning keuangan,
              // ungu outlet
              _buildMenuItem(
                title: 'Order',
                icon: Icons.add_shopping_cart_rounded,
                color: _menuBlue,
                onTap: _showNewOrderDialog,
              ),
              _buildMenuItem(
                title: 'Customer',
                icon: Icons.people_alt_outlined,
                color: _menuBlue,
                onTap: _showCustomerModal,
              ),
              StreamBuilder<List<DamageClaim>>(
                stream: _claimsStream,
                builder: (context, snap) => _buildMenuItem(
                  title: 'Klaim',
                  icon: Icons.assignment_late_outlined,
                  color: _menuBlue,
                  badge: (snap.data ?? const <DamageClaim>[]).where((c) => c.isPending).length,
                  onTap: () {
                    final shop = _shop;
                    if (shop == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OwnerClaimsScreen(shopId: shop.id)),
                    );
                  },
                ),
              ),
              _buildMenuItem(
                title: 'Petty Cash',
                icon: Icons.account_balance_wallet_outlined,
                color: _menuAmber,
                onTap: _showPettyCashModal,
              ),
              _buildMenuItem(
                title: 'Promo',
                icon: Icons.loyalty_outlined,
                color: _menuAmber,
                onTap: () {
                  final shop = _shop;
                  if (shop == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OwnerPromoScreen(shop: shop)),
                  );
                },
              ),
              _buildMenuItem(
                title: 'Info Outlet',
                icon: Icons.storefront_outlined,
                color: _menuViolet,
                onTap: _openOutletSettings,
              ),
              _buildMenuItem(
                title: 'Pengaturan',
                icon: Icons.tune_rounded,
                color: _menuViolet,
                onTap: () => _showShopSettingsModal(initialTab: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Kartu ringkas saldo komisi. Warna mengikuti status: biru masa pengenalan,
  /// hijau aman, kuning menipis/minus, merah outlet berhenti menerima pesanan.
  Widget _buildWalletCard() {
    final shop = _shop;
    if (shop == null) return const SizedBox.shrink();
    return FutureBuilder<WalletSummary>(
      key: ValueKey('wallet-${shop.id}-$_walletRefresh'),
      future: WalletService().summary(shop.id),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final s = snap.data!;
        final (color, soft, title, desc) = walletStateStyle(s);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => WalletScreen(shop: shop)));
                if (mounted) setState(() => _walletRefresh++);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.account_balance_wallet_outlined, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Saldo komisi ${_formatRupiah(s.balance)}',
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                          Text(title, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
                        ],
                      ),
                    ),
                    Text(s.state == WalletState.ok || s.state == WalletState.intro ? 'Lihat' : 'Isi saldo',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0077B6))),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Pintasan Laporan Omzet, Transaksi Hari Ini, Riwayat Layanan.
  /// Keterangan tiap baris memakai angka asli dari pesanan outlet.
  Widget _buildReportShortcuts() {
    final shop = _shop;
    if (shop == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = _orders.where((o) => _isSameDay(o.createdAt, now)).toList();
    final todayOmzet = today.where((o) => o.status != 'cancelled').fold<int>(0, (s, o) => s + o.totalPrice);
    final weekStart = DateTime(now.year, now.month, now.day - 6);
    final weekOmzet = _orders
        .where((o) => o.status != 'cancelled' && !o.createdAt.isBefore(weekStart))
        .fold<int>(0, (s, o) => s + o.totalPrice);
    final served = _orders.where((o) => o.status == 'done' || o.status == 'delivered').length;

    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    Widget row(IconData icon, Color color, String title, String caption, VoidCallback onTap, {bool last = false}) {
      final deep = Color.lerp(color, Colors.black, 0.18)!;
      return Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.03)],
                ),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [color, deep],
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                          const SizedBox(height: 2),
                          Text(caption,
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color.lerp(color, const Color(0xFF334155), 0.5)),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Text('Laporan & Riwayat',
                style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          ),
          row(Icons.insert_chart_outlined_rounded, const Color(0xFF0077B6), 'Laporan Omzet',
              '7 hari terakhir ${_formatRupiah(weekOmzet)}', () => open(RevenueReportScreen(shop: shop))),
          row(Icons.receipt_long_outlined, const Color(0xFFD97706), 'Transaksi Hari Ini',
              today.isEmpty ? 'Belum ada transaksi hari ini' : '${today.length} transaksi · ${_formatRupiah(todayOmzet)}',
              () => open(TodayTransactionsScreen(shop: shop))),
          row(Icons.history_rounded, const Color(0xFF15803D), 'Riwayat Layanan',
              served == 0 ? 'Belum ada layanan selesai' : '$served layanan selesai dilayani',
              () => open(ServiceHistoryScreen(shop: shop))),
          row(Icons.star_rounded, const Color(0xFFD97706), 'Rating & Ulasan',
              shop.reviewCount == 0
                  ? 'Belum ada ulasan'
                  : '${shop.rating.toStringAsFixed(1).replaceAll('.', ',')} dari ${shop.reviewCount} ulasan · balas & pantau',
              () => open(OwnerReviewsScreen(shop: shop)), last: true),
        ],
      ),
    );
  }

  static const _menuBlue = Color(0xFF0077B6);
  static const _menuAmber = Color(0xFFD97706);
  static const _menuViolet = Color(0xFF7C3AED);

  Widget _buildMenuItem({
    required String title,
    required IconData icon,
    required Color color,
    required FutureOr<void> Function() onTap,
    int badge = 0,
  }) {
    final deep = Color.lerp(color, Colors.black, 0.18)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: TapGuard.wrap(onTap),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0.04)],
            ),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, deep],
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 21),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color.lerp(color, const Color(0xFF0F172A), 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. QUICK STATUS SUMMARY CARDS (GAMBAR 1 - Antrian, Proses, Siap Diambil, Deadline)
  // =========================================================================

  Widget _buildStatusSummaryCards() {
    final antrianCount = _orders.where((o) => o.status == 'pending').length;
    final prosesCount = _orders.where((o) => o.status == 'washing' || o.status == 'drying').length;
    final readyCount = _orders.where((o) => o.status == 'done').length;

    final now = DateTime.now();
    final deadlineCount = _orders.where((o) {
      if (o.status == 'done' || o.status == 'delivered' || o.status == 'cancelled') return false;
      final isExpress = o.items.any((i) => i.name.toLowerCase().contains('express'));
      final hoursPassed = now.difference(o.createdAt).inHours;
      return isExpress || hoursPassed >= 18;
    }).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryCardItem(
                label: 'Antrian',
                count: antrianCount,
                icon: Icons.event_note_rounded,
                color: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFFFBEB),
                borderColor: const Color(0xFFFDE68A),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCardItem(
                label: 'Proses',
                count: prosesCount,
                icon: Icons.local_laundry_service_rounded,
                color: const Color(0xFF0284C7),
                bgColor: const Color(0xFFF0F9FF),
                borderColor: const Color(0xFFBAE6FD),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCardItem(
                label: 'Siap Diambil',
                count: readyCount,
                icon: Icons.shopping_bag_outlined,
                color: const Color(0xFF10B981),
                bgColor: const Color(0xFFECFDF5),
                borderColor: const Color(0xFFA7F3D0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryCardItem(
                label: 'Deadline',
                count: deadlineCount,
                icon: Icons.access_time_rounded,
                color: const Color(0xFFE11D48),
                bgColor: const Color(0xFFFFF1F2),
                borderColor: const Color(0xFFFECDD3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCardItem({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          // Warna lembut sesuai status (bukan abu-abu datar)
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgColor, Colors.white],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(color, Colors.white, 0.18)!, color],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 21),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
          ],
        ),
      );
  }

  // =========================================================================
  // 2. STATUS CUCIAN SECTION WITH STEPPER PROGRESS BAR (GAMBAR 2)
  // =========================================================================

  Widget _buildStatusCucianSection(List<OrderModel> orders) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildClaimsBanner(),

          // Header Row: "Status Cucian" + "Lihat Semua"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Status Cucian',
                style: GoogleFonts.quicksand(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() => _activeFilter = 'Semua');
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Lihat Semua',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0077B6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter Tab Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Semua', 'Antrean', 'Proses', 'Selesai', 'Deadline', 'Dibatalkan'].map((tab) {
                final isSelected = _activeFilter == tab;
                return GestureDetector(
                  onTap: () => setState(() => _activeFilter = tab),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0077B6) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF0077B6) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      tab,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          if (_isReconnecting && _orders.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Koneksi terputus, menyambungkan ulang... Data di bawah mungkin belum terbaru.',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF92400E), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_loadError != null)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(_loadError!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: const Color(0xFFEF4444))),
            )
          else if (orders.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Tidak ada pesanan di kategori ini',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              itemCount: orders.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final order = orders[idx];
                return _buildStatusCucianCard(order);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCucianCard(OrderModel order) {
    int currentStep = 0;
    if (order.status == 'washing') {
      currentStep = 1;
    } else if (order.status == 'drying') {
      currentStep = 2;
    } else if (order.status == 'done' || order.status == 'delivered') {
      currentStep = 3;
    }

    final isCancelled = order.status == 'cancelled';

    Color pillBg;
    Color pillText;
    String pillLabel;

    if (order.status == 'washing') {
      pillBg = const Color(0xFFE0F2FE);
      pillText = const Color(0xFF0284C7);
      pillLabel = 'Dicuci';
    } else if (order.status == 'drying') {
      pillBg = const Color(0xFFFFF7ED);
      pillText = const Color(0xFFEA580C);
      pillLabel = 'Dikeringkan';
    } else if (order.status == 'done') {
      pillBg = const Color(0xFFDCFCE7);
      pillText = const Color(0xFF16A34A);
      pillLabel = 'Selesai';
    } else if (order.status == 'delivered') {
      pillBg = const Color(0xFFEDE9FE);
      pillText = const Color(0xFF7C3AED);
      pillLabel = 'Diserahkan';
    } else if (isCancelled) {
      pillBg = const Color(0xFFFEE2E2);
      pillText = const Color(0xFFDC2626);
      pillLabel = 'Dibatalkan';
    } else {
      pillBg = const Color(0xFFFEF3C7);
      pillText = const Color(0xFFD97706);
      pillLabel = 'Diterima';
    }

    final serviceSummary = _itemsSummary(order).isNotEmpty ? _itemsSummary(order) : 'Layanan Laundry';
    final serviceTitle = _serviceName(order);

    return InkWell(
      onTap: () => _showOrderActionModal(order),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Squircle icon, Code & Service info, Status Pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ikon berwarna sesuai status: tahap cucian terbaca sekilas dari warnanya
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(pillText, Colors.white, 0.18)!, pillText],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Icon(
                      _statusCardIcon(order.status),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Code & Service weight
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#LK${_orderCode(order)}',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '(${_customerName(order)})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$serviceTitle • $serviceSummary',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status Pill (matching Gambar 2)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: pillText.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: pillText, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        pillLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: pillText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (!isCancelled) ...[
              const SizedBox(height: 16),
              // Stepper Progress Bar (matching Gambar 2)
              _buildOrderStepperTimeline(order, currentStep),
            ],

            // Langkah terakhir setelah "Selesai": serah terima ke pelanggan
            if (order.status == 'done') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _handleStepTap(order, 'delivered'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFFC4B5FD)),
                    backgroundColor: const Color(0xFFF5F3FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: Text(
                    'Serahkan ke Pelanggan',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ] else if (order.status == 'delivered' && order.receivedAt != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diterima pelanggan ${_formatDate(order.receivedAt!)} ${_formatTime(order.receivedAt!)}',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6D28D9)),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Bottom bar: Date & Total Price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatDate(order.createdAt)} ${_formatTime(order.createdAt)}',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                ),
                Text(
                  _formatRupiah(order.totalPrice),
                  style: GoogleFonts.quicksand(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0077B6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusCardIcon(String status) {
    switch (status) {
      case 'washing':
        return Icons.local_laundry_service_rounded;
      case 'drying':
        return Icons.dry_rounded;
      case 'done':
        return Icons.shopping_bag_rounded;
      case 'delivered':
        return Icons.home_rounded;
      case 'cancelled':
        return Icons.block_rounded;
      default:
        return Icons.inventory_2_rounded; // pending: cucian baru diterima, menunggu diproses
    }
  }

  Widget _buildOrderStepperTimeline(OrderModel order, int currentStep) {
    const steps = [
      {'label': 'Diterima', 'status': 'pending'},
      {'label': 'Dicuci', 'status': 'washing'},
      {'label': 'Dikeringkan', 'status': 'drying'},
      {'label': 'Selesai', 'status': 'done'},
    ];

    final isDelivered = order.status == 'delivered';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length, (index) {
        final isCompleted = currentStep > index || (currentStep == 3 && index == 3) || isDelivered;
        final isCurrent = currentStep == index && !isDelivered;

        // Hanya langkah tepat setelah status sekarang yang bisa ditekan (status tidak bisa mundur)
        final isNext = !isDelivered && order.status != 'cancelled' && index == currentStep + 1;

        final stepColor = isCompleted
            ? const Color(0xFF10B981)
            : (isCurrent
                ? const Color(0xFF0077B6)
                : (isNext ? const Color(0xFF0077B6) : const Color(0xFFCBD5E1)));

        return Expanded(
          child: InkWell(
            onTap: () {
              if (isNext) {
                _handleStepTap(order, steps[index]['status'] as String);
              } else if (index < currentStep) {
                _showSnack('Status tidak bisa dimundurkan.');
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                Row(
                  children: [
                    // Left connecting line
                    Expanded(
                      child: index == 0
                          ? const SizedBox.shrink()
                          : Container(
                              height: 3,
                              color: currentStep >= index
                                  ? (currentStep > index ? const Color(0xFF10B981) : const Color(0xFF0077B6))
                                  : const Color(0xFFE2E8F0),
                            ),
                    ),
                    // Node circle (matching Gambar 2)
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? const Color(0xFF10B981)
                            : (isCurrent ? const Color(0xFF0077B6) : Colors.white),
                        border: Border.all(
                          color: stepColor,
                          width: (isCurrent || isNext) ? 2 : 1.5,
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF0077B6).withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                            : (isCurrent
                                ? Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  )
                                : (isNext
                                    ? const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF0077B6))
                                    : null)),
                      ),
                    ),
                    // Right connecting line
                    Expanded(
                      child: index == steps.length - 1
                          ? const SizedBox.shrink()
                          : Container(
                              height: 3,
                              color: currentStep > index
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFE2E8F0),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  steps[index]['label'] as String,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: (isCompleted || isCurrent || isNext) ? FontWeight.w700 : FontWeight.w500,
                    color: (isCompleted || isCurrent)
                        ? const Color(0xFF0F172A)
                        : (isNext ? const Color(0xFF0077B6) : const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _handleStepTap(OrderModel order, String targetStatus) async {
    if (order.status == targetStatus) return;

    if (targetStatus == 'delivered') {
      if (order.status != 'done') {
        _showSnack('Ubah status ke "Selesai" dulu sebelum serah terima ke pelanggan.');
        return;
      }
      final ok = await showHandoverSheet(context, order);
      if (ok) {
        _showSnack('Serah terima tercatat. Pesanan diterima pelanggan.', color: const Color(0xFF10B981));
      }
      return;
    }

    if (order.status == 'pending' && targetStatus != 'cancelled' && order.intakeAt == null) {
      final ok = await showIntakeSheet(context, order);
      if (!ok) return;
    }

    final success = await _supabaseService.updateOrderStatus(order.id, targetStatus);
    if (success && mounted) {
      _showSnack('Status pesanan diubah ke ${_statusLabel(targetStatus)}', color: const Color(0xFF10B981));
    } else if (mounted) {
      _showSnack(_statusUpdateFailMessage(), color: const Color(0xFFEF4444));
    }
  }

  // =========================================================================
  // 3. PENGATURAN MITRA & OUTLET (Layanan, Harga, Jam Buka, Antar Jemput)
  // =========================================================================

  static List<ServiceModel> _defaultServiceCatalog(int basePrice) => [
    ServiceModel(
      id: 'srv_komplit',
      name: 'Cuci Komplit',
      description: 'Cuci, pengering & setrika rapi wangi',
      price: basePrice > 0 ? basePrice : 8000,
      unit: '/ kg',
      iconName: 'local_laundry_service',
      isActive: true,
      duration: '2 Hari',
    ),
    ServiceModel(
      id: 'srv_kering',
      name: 'Cuci Kering Lipat',
      description: 'Cuci & pengering lipat tanpa setrika',
      price: ((basePrice > 0 ? basePrice : 8000) * 0.75).round(),
      unit: '/ kg',
      iconName: 'dry_cleaning',
      isActive: true,
      duration: '1 Hari',
    ),
    ServiceModel(
      id: 'srv_setrika',
      name: 'Setrika Saja',
      description: 'Setrika rapi & packing plastik higienis',
      price: ((basePrice > 0 ? basePrice : 8000) * 0.65).round(),
      unit: '/ kg',
      iconName: 'iron',
      isActive: true,
      duration: '1 Hari',
    ),
    ServiceModel(
      id: 'srv_bedcover',
      name: 'Bedcover & Selimut',
      description: 'Pencucian khusus linen tebal & selimut',
      price: 25000,
      unit: '/ pcs',
      iconName: 'bed',
      isActive: true,
      duration: '2-3 Hari',
    ),
    ServiceModel(
      id: 'srv_sepatu',
      name: 'Sepatu & Helm',
      description: 'Deep clean treatment sepatu & helm anti bau',
      price: 20000,
      unit: '/ pcs',
      iconName: 'sports_motorsports',
      isActive: true,
      duration: '2 Hari',
    ),
    ServiceModel(
      id: 'srv_karpet',
      name: 'Karpet & Gorden',
      description: 'Pembersihan debu & noda karpet / gorden',
      price: 15000,
      unit: '/ meter',
      iconName: 'curtains',
      isActive: false,
      duration: '3 Hari',
    ),
    ServiceModel(
      id: 'srv_express',
      name: 'Express 6 Jam',
      description: 'Layanan kilat prioritas selesai dalam 6 jam',
      price: (basePrice > 0 ? basePrice : 8000) + 7000,
      unit: '/ kg',
      iconName: 'bolt',
      isActive: true,
      duration: '6 Jam',
    ),
  ];

  void _showShopSettingsModal({int initialTab = 0}) {
    final shop = _shop;
    if (shop == null) {
      _showSnack('Akun belum terhubung ke outlet.', color: const Color(0xFFEF4444));
      return;
    }

    int activeTab = initialTab;
    int basePricePerKg = shop.pricePerKg > 0 ? shop.pricePerKg : 8000;
    final basePriceCtrl = TextEditingController(text: basePricePerKg.toString());

    // Services list copy
    List<ServiceModel> currentServices = shop.services.isNotEmpty
        ? List<ServiceModel>.from(shop.services)
        : _defaultServiceCatalog(basePricePerKg);

    // Operational hours
    bool isOpen = shop.isOpen;
    bool is24Hours = shop.openHours.toLowerCase().contains('24 jam');
    TimeOfDay openTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay closeTime = const TimeOfDay(hour: 21, minute: 0);

    final parts = shop.openHours.split('-');
    if (parts.length == 2) {
      final p1 = parts[0].trim().split(':');
      final p2 = parts[1].trim().split(':');
      if (p1.length == 2) {
        openTime = TimeOfDay(hour: int.tryParse(p1[0]) ?? 8, minute: int.tryParse(p1[1]) ?? 0);
      }
      if (p2.length == 2) {
        closeTime = TimeOfDay(hour: int.tryParse(p2[0]) ?? 21, minute: int.tryParse(p2[1]) ?? 0);
      }
    }

    // Days
    final daysList = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    Set<String> selectedDays = _parseOperationalDays(shop.operationalDays, daysList);

    // Delivery settings
    bool isDeliveryEnabled = shop.isDeliveryAvailable;
    String deliveryFeeType = shop.deliveryFeeType;
    int deliveryFee = shop.deliveryFee;
    final deliveryFeeCtrl = TextEditingController(text: deliveryFee.toString());
    double deliveryRadiusKm = shop.deliveryRadiusKm;
    int minDeliveryOrder = shop.minDeliveryOrder;
    bool isSaving = false;
    String? saveError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // Top Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Modal Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.store_mall_directory_rounded, color: Color(0xFF0077B6), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pengaturan Mitra Laundry',
                              style: GoogleFonts.quicksand(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              shop.name,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),

                // Tab Selector (Layanan & Tarif, Jam Buka, Antar Jemput)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _buildSettingsTabButton(
                        label: 'Layanan & Tarif',
                        icon: Icons.local_offer_outlined,
                        isActive: activeTab == 0,
                        onTap: () => setModalState(() => activeTab = 0),
                      ),
                      _buildSettingsTabButton(
                        label: 'Jam Buka',
                        icon: Icons.schedule_rounded,
                        isActive: activeTab == 1,
                        onTap: () => setModalState(() => activeTab = 1),
                      ),
                      _buildSettingsTabButton(
                        label: 'Antar Jemput',
                        icon: Icons.delivery_dining_rounded,
                        isActive: activeTab == 2,
                        onTap: () => setModalState(() => activeTab = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Tab Content Body
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: activeTab == 0
                        ? _buildLayananTarifTab(
                            basePriceCtrl: basePriceCtrl,
                            services: currentServices,
                            onServiceChanged: (updated) => setModalState(() => currentServices = updated),
                            onAddService: (newService) => setModalState(() => currentServices.add(newService)),
                          )
                        : (activeTab == 1
                            ? _buildJamOperasionalTab(
                                isOpen: isOpen,
                                onOpenToggle: (val) => setModalState(() => isOpen = val),
                                openTime: openTime,
                                closeTime: closeTime,
                                is24Hours: is24Hours,
                                on24HoursToggle: (val) => setModalState(() => is24Hours = val),
                                onPickOpenTime: () async {
                                  final p = await showTimePicker(context: context, initialTime: openTime);
                                  if (p != null) setModalState(() => openTime = p);
                                },
                                onPickCloseTime: () async {
                                  final p = await showTimePicker(context: context, initialTime: closeTime);
                                  if (p != null) setModalState(() => closeTime = p);
                                },
                                daysList: daysList,
                                selectedDays: selectedDays,
                                onDayToggle: (day) {
                                  setModalState(() {
                                    if (selectedDays.contains(day)) {
                                      if (selectedDays.length > 1) selectedDays.remove(day);
                                    } else {
                                      selectedDays.add(day);
                                    }
                                  });
                                },
                                onQuickDaysSelect: (preset) {
                                  setModalState(() {
                                    if (preset == 'all') {
                                      selectedDays = Set.from(daysList);
                                    } else if (preset == 'senin_sabtu') {
                                      selectedDays = {'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'};
                                    } else if (preset == 'weekdays') {
                                      selectedDays = {'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat'};
                                    }
                                  });
                                },
                              )
                            : _buildAntarJemputTab(
                                isDeliveryEnabled: isDeliveryEnabled,
                                onDeliveryToggle: (val) => setModalState(() => isDeliveryEnabled = val),
                                feeType: deliveryFeeType,
                                onFeeTypeChange: (val) => setModalState(() => deliveryFeeType = val),
                                feeCtrl: deliveryFeeCtrl,
                                radiusKm: deliveryRadiusKm,
                                onRadiusChange: (val) => setModalState(() => deliveryRadiusKm = val),
                                minOrder: minDeliveryOrder,
                                onMinOrderChange: (val) => setModalState(() => minDeliveryOrder = val),
                              )),
                  ),
                ),

                // Sticky Bottom Save Button
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: const Color(0xFFE2E8F0))),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                    if (saveError != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          saveError!,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFB91C1C)),
                        ),
                      ),
                    SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0077B6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final parsedBase = int.tryParse(basePriceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                              final parsedFee = int.tryParse(deliveryFeeCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

                              // Validasi sebelum dikirim ke database
                              String? invalid;
                              if (parsedBase <= 0) {
                                invalid = 'Isi tarif dasar per kg (lebih dari Rp 0).';
                              } else if (!currentServices.any((s) => s.isActive)) {
                                invalid = 'Aktifkan minimal 1 layanan agar pelanggan bisa memesan.';
                              } else if (!is24Hours &&
                                  _formatTimeOfDay(openTime) == _formatTimeOfDay(closeTime)) {
                                invalid = 'Jam buka dan jam tutup tidak boleh sama. Pakai "24 Jam" jika buka nonstop.';
                              } else if (isDeliveryEnabled && deliveryFeeType != 'free' && parsedFee <= 0) {
                                invalid = 'Isi nominal ongkir, atau pilih "Gratis Ongkir".';
                              }
                              if (invalid != null) {
                                setModalState(() => saveError = invalid);
                                return;
                              }
                              setModalState(() {
                                isSaving = true;
                                saveError = null;
                              });

                              String hoursStr = is24Hours
                                  ? 'Buka 24 Jam'
                                  : '${_formatTimeOfDay(openTime)} - ${_formatTimeOfDay(closeTime)}';

                              final String daysStr = _formatOperationalDays(selectedDays, daysList);

                              final updates = {
                                'price_per_kg': parsedBase,
                                'services': currentServices.map((s) => s.toMap()).toList(),
                                'open_hours': hoursStr,
                                'operational_days': daysStr,
                                'is_open': isOpen,
                                'is_delivery_available': isDeliveryEnabled,
                                'delivery_fee': deliveryFeeType == 'free' ? 0 : parsedFee,
                                'delivery_fee_type': deliveryFeeType,
                                'delivery_radius_km': deliveryRadiusKm,
                                'min_delivery_order': minDeliveryOrder,
                              };

                              final error = await _supabaseService.updateShop(shop.id, updates);
                              if (error != null) {
                                // Jangan tutup lembar & jangan ubah tampilan: data belum tersimpan
                                if (ctx.mounted) {
                                  setModalState(() {
                                    isSaving = false;
                                    saveError = error;
                                  });
                                }
                                return;
                              }

                              if (mounted) {
                                setState(() {
                                  _shop = _shop?.copyWith(
                                    pricePerKg: parsedBase,
                                    services: currentServices,
                                    openHours: hoursStr,
                                    operationalDays: daysStr,
                                    isOpen: isOpen,
                                    isDeliveryAvailable: isDeliveryEnabled,
                                    deliveryFee: deliveryFeeType == 'free' ? 0 : parsedFee,
                                    deliveryFeeType: deliveryFeeType,
                                    deliveryRadiusKm: deliveryRadiusKm,
                                    minDeliveryOrder: minDeliveryOrder,
                                  );
                                });
                              }

                              if (ctx.mounted) Navigator.pop(ctx);
                              _showSnack('Pengaturan outlet tersimpan. Pelanggan langsung melihat perubahannya.',
                                  color: const Color(0xFF10B981));
                            },
                      icon: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                            )
                          : const Icon(Icons.check_circle_rounded, color: Colors.white),
                      label: Text(
                        isSaving ? 'Menyimpan...' : 'Simpan Pengaturan Outlet',
                        style: GoogleFonts.quicksand(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
    );
  }

  /// "Setiap Hari (Senin - Minggu)" / "Senin - Sabtu" / "Senin, Rabu, Jumat" → himpunan hari
  static Set<String> _parseOperationalDays(String text, List<String> daysList) {
    final t = text.toLowerCase();
    if (t.isEmpty || t.contains('setiap hari')) return Set.from(daysList);
    final rangeMatch = RegExp(r'^(\w+)\s*-\s*(\w+)$').firstMatch(text.trim());
    if (rangeMatch != null) {
      final from = daysList.indexWhere((d) => d.toLowerCase() == rangeMatch.group(1)!.toLowerCase());
      final to = daysList.indexWhere((d) => d.toLowerCase() == rangeMatch.group(2)!.toLowerCase());
      if (from >= 0 && to >= from) return Set.from(daysList.sublist(from, to + 1));
    }
    final picked = daysList.where((d) => t.contains(d.toLowerCase())).toSet();
    return picked.isEmpty ? Set.from(daysList) : picked;
  }

  /// Kebalikan dari _parseOperationalDays; urutan hari selalu Senin → Minggu
  static String _formatOperationalDays(Set<String> selected, List<String> daysList) {
    final ordered = daysList.where(selected.contains).toList();
    if (ordered.length == 7) return 'Setiap Hari (Senin - Minggu)';
    // Hari berurutan tanpa celah ditulis sebagai rentang, misal "Senin - Sabtu"
    final first = daysList.indexOf(ordered.first);
    final last = daysList.indexOf(ordered.last);
    if (ordered.length >= 3 && last - first + 1 == ordered.length) {
      return '${ordered.first} - ${ordered.last}';
    }
    return ordered.join(', ');
  }

  Widget _buildSettingsTabButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? const Color(0xFF0077B6) : const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive ? const Color(0xFF0077B6) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 1: LAYANAN & TARIF
  Widget _buildLayananTarifTab({
    required TextEditingController basePriceCtrl,
    required List<ServiceModel> services,
    required ValueChanged<List<ServiceModel>> onServiceChanged,
    required ValueChanged<ServiceModel> onAddService,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Base Price Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.scale_rounded, color: Color(0xFF0077B6), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tarif Dasar Kiloan (/ Kg)',
                      style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Harga acuan untuk pesanan kiloan reguler',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: basePriceCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0077B6)),
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    prefixStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0077B6), width: 1.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Services list header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Katalog Layanan Outlet',
                  style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                ),
                Text(
                  'Centang layanan yang ingin Anda sediakan',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => _showAddServiceDialog(onAddService),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Color(0xFF0077B6)),
              label: Text(
                'Tambah',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0077B6)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Services cards
        ...services.asMap().entries.map((entry) {
          final idx = entry.key;
          final srv = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: srv.isActive ? Colors.white : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: srv.isActive ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: srv.isActive ? const Color(0xFF0077B6).withValues(alpha: 0.1) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _serviceIcon(srv.iconName),
                    color: srv.isActive ? const Color(0xFF0077B6) : Colors.grey,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              srv.name,
                              style: GoogleFonts.quicksand(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: srv.isActive ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              srv.duration,
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatRupiah(srv.price)} ${srv.unit}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: srv.isActive ? const Color(0xFF0284C7) : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
                  tooltip: 'Ubah Harga & Info',
                  onPressed: () {
                    _showEditServicePriceDialog(srv, (updated) {
                      final list = List<ServiceModel>.from(services);
                      list[idx] = updated;
                      onServiceChanged(list);
                    });
                  },
                ),
                Switch.adaptive(
                  value: srv.isActive,
                  activeThumbColor: const Color(0xFF0077B6),
                  onChanged: (val) {
                    final list = List<ServiceModel>.from(services);
                    list[idx] = srv.copyWith(isActive: val);
                    onServiceChanged(list);
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // TAB 2: JAM OPERASIONAL
  Widget _buildJamOperasionalTab({
    required bool isOpen,
    required ValueChanged<bool> onOpenToggle,
    required TimeOfDay openTime,
    required TimeOfDay closeTime,
    required bool is24Hours,
    required ValueChanged<bool> on24HoursToggle,
    required VoidCallback onPickOpenTime,
    required VoidCallback onPickCloseTime,
    required List<String> daysList,
    required Set<String> selectedDays,
    required ValueChanged<String> onDayToggle,
    required ValueChanged<String> onQuickDaysSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Buka Sekarang Toggle Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOpen ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isOpen ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
                child: Icon(isOpen ? Icons.check_circle_rounded : Icons.pause_circle_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOpen ? 'Outlet Sedang Buka' : 'Outlet Tutup Sementara',
                      style: GoogleFonts.quicksand(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isOpen ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      ),
                    ),
                    Text(
                      isOpen ? 'Menerima pesanan masuk dari pelanggan' : 'Pelanggan tidak dapat membuat pesanan baru',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isOpen ? const Color(0xFF047857) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isOpen,
                activeThumbColor: const Color(0xFF10B981),
                onChanged: onOpenToggle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Jam Kerja Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Jam Operasional Harian',
                    style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                  ),
                  Row(
                    children: [
                      Text('24 Jam', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                      const SizedBox(width: 4),
                      Switch.adaptive(
                        value: is24Hours,
                        activeThumbColor: const Color(0xFF0077B6),
                        onChanged: on24HoursToggle,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (!is24Hours) ...[
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onPickOpenTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Jam Buka', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF0077B6)),
                                  const SizedBox(width: 6),
                                  Text(_formatTimeOfDay(openTime), style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: onPickCloseTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Jam Tutup', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_filled_rounded, size: 16, color: Color(0xFFD97706)),
                                  const SizedBox(width: 6),
                                  Text(_formatTimeOfDay(closeTime), style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.all_inclusive_rounded, color: Color(0xFF0284C7), size: 18),
                      const SizedBox(width: 10),
                      Text('Outlet buka 24 jam nonstop', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0284C7))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Hari Buka Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hari Buka Operasional',
                style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 10),
              // Quick Presets
              Row(
                children: [
                  _buildDayPresetChip('Setiap Hari', selectedDays.length == 7, () => onQuickDaysSelect('all')),
                  const SizedBox(width: 6),
                  _buildDayPresetChip('Sen - Sab', selectedDays.length == 6 && !selectedDays.contains('Minggu'), () => onQuickDaysSelect('senin_sabtu')),
                  const SizedBox(width: 6),
                  _buildDayPresetChip('Hari Kerja', selectedDays.length == 5 && !selectedDays.contains('Sabtu') && !selectedDays.contains('Minggu'), () => onQuickDaysSelect('weekdays')),
                ],
              ),
              const SizedBox(height: 12),
              // Day Toggle Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: daysList.map((day) {
                  final isSelected = selectedDays.contains(day);
                  return FilterChip(
                    label: Text(day),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: const Color(0xFF0077B6),
                    backgroundColor: const Color(0xFFF1F5F9),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: isSelected ? const Color(0xFF0077B6) : const Color(0xFFE2E8F0)),
                    onSelected: (_) => onDayToggle(day),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayPresetChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0077B6).withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF0077B6) : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? const Color(0xFF0077B6) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // TAB 3: LAYANAN ANTAR JEMPUT
  Widget _buildAntarJemputTab({
    required bool isDeliveryEnabled,
    required ValueChanged<bool> onDeliveryToggle,
    required String feeType,
    required ValueChanged<String> onFeeTypeChange,
    required TextEditingController feeCtrl,
    required double radiusKm,
    required ValueChanged<double> onRadiusChange,
    required int minOrder,
    required ValueChanged<int> onMinOrderChange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Layanan Antar Jemput
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDeliveryEnabled ? const Color(0xFF0077B6).withValues(alpha: 0.1) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.delivery_dining_rounded, color: isDeliveryEnabled ? const Color(0xFF0077B6) : Colors.grey, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Layanan Antar Jemput',
                      style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      isDeliveryEnabled ? 'Kurir outlet siap antar jemput cucian' : 'Hanya menerima drop-off langsung ke outlet',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isDeliveryEnabled,
                activeThumbColor: const Color(0xFF0077B6),
                onChanged: onDeliveryToggle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (isDeliveryEnabled) ...[
          // Skema Tarif Ongkir Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skema Tarif Ongkos Kirim',
                  style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 12),

                _buildFeeTypeRadio('flat', 'Tarif Flat (Tetap per Pesanan)', 'Biaya kirim sama untuk semua jarak dalam radius', feeType, onFeeTypeChange),
                const SizedBox(height: 8),
                _buildFeeTypeRadio('per_km', 'Tarif Berdasarkan Jarak (/ KM)', 'Biaya dihitung otomatis per kilometer jarak pelanggan', feeType, onFeeTypeChange),
                const SizedBox(height: 8),
                _buildFeeTypeRadio('free', 'Gratis Ongkir (Free Delivery)', 'Tanpa biaya tambahan untuk meningkatkan pesanan', feeType, onFeeTypeChange),

                if (feeType != 'free') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        feeType == 'flat' ? 'Nominal Ongkir Flat:' : 'Biaya per KM:',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: feeCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0077B6)),
                          decoration: InputDecoration(
                            prefixText: 'Rp ',
                            prefixStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                            suffixText: feeType == 'per_km' ? ' / Km' : '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0077B6))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Batas & Ketentuan Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Radius Maksimal Pengantaran',
                  style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [3.0, 5.0, 8.0, 10.0, 15.0].map((r) {
                    final isSel = (radiusKm - r).abs() < 0.1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${r.toInt()} Km'),
                        selected: isSel,
                        onSelected: (_) => onRadiusChange(r),
                        selectedColor: const Color(0xFF0077B6),
                        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isSel ? Colors.white : const Color(0xFF334155)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                Text(
                  'Minimal Pesanan untuk Antar Jemput',
                  style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [15000, 20000, 30000, 50000].map((m) {
                    final isSel = minOrder == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('Rp ${(m / 1000).toInt()}k'),
                        selected: isSel,
                        onSelected: (_) => onMinOrderChange(m),
                        selectedColor: const Color(0xFF0077B6),
                        labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isSel ? Colors.white : const Color(0xFF334155)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeeTypeRadio(String val, String title, String subtitle, String currentVal, ValueChanged<String> onChanged) {
    final isSelected = val == currentVal;
    return InkWell(
      onTap: () => onChanged(val),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0077B6).withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF0077B6) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFF0077B6) : const Color(0xFF94A3B8),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddServiceDialog(ValueChanged<ServiceModel> onAdd) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '10000');
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '1-2 Hari');
    String unit = '/ kg';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Tambah Layanan Baru', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Layanan (misal: Cuci Sepatu)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Harga (Rp)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        items: const [
                          DropdownMenuItem(value: '/ kg', child: Text('/ Kg')),
                          DropdownMenuItem(value: '/ pcs', child: Text('/ Pcs')),
                          DropdownMenuItem(value: '/ meter', child: Text('/ Meter')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => unit = val);
                        },
                        decoration: const InputDecoration(labelText: 'Satuan'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: durationCtrl,
                  decoration: const InputDecoration(labelText: 'Estimasi Durasi (misal: 1 Hari)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Keterangan Singkat'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0077B6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                final price = int.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 10000;
                final newSrv = ServiceModel(
                  id: 'srv_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : 'Layanan cucian',
                  price: price,
                  unit: unit,
                  iconName: 'local_laundry_service',
                  isActive: true,
                  duration: durationCtrl.text.trim().isNotEmpty ? durationCtrl.text.trim() : '1 Hari',
                );
                onAdd(newSrv);
                Navigator.pop(ctx);
              },
              child: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditServicePriceDialog(ServiceModel srv, ValueChanged<ServiceModel> onSave) {
    final priceCtrl = TextEditingController(text: srv.price.toString());
    final durationCtrl = TextEditingController(text: srv.duration);
    final descCtrl = TextEditingController(text: srv.description);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Ubah ${srv.name}', style: GoogleFonts.quicksand(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Harga Tarif (${srv.unit})',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: durationCtrl,
              decoration: const InputDecoration(labelText: 'Estimasi Durasi (misal: 2 Hari)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Deskripsi Singkat Layanan'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077B6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newPrice = int.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? srv.price;
              onSave(srv.copyWith(
                price: newPrice,
                duration: durationCtrl.text.trim().isNotEmpty ? durationCtrl.text.trim() : srv.duration,
                description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : srv.description,
              ));
              Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Buka Info Outlet (foto profil, nama, kontak, alamat & lokasi)
  Future<void> _openOutletSettings() async {
    final shop = _shop;
    if (shop == null) {
      _showSnack('Daftarkan outlet terlebih dahulu');
      return;
    }
    final updated = await Navigator.push<ShopModel>(
      context,
      MaterialPageRoute(builder: (_) => OutletSettingsScreen(shop: shop)),
    );
    if (updated != null && mounted) setState(() => _shop = updated);
  }

  IconData _serviceIcon(String name) {
    switch (name.toLowerCase()) {
      case 'dry_cleaning':
      case 'cuci_kering':
        return Icons.dry_cleaning_rounded;
      case 'iron':
      case 'setrika':
        return Icons.iron_rounded;
      case 'bed':
      case 'bedcover':
        return Icons.bed_rounded;
      case 'sports_motorsports':
      case 'sepatu':
        return Icons.sports_motorsports_rounded;
      case 'curtains':
      case 'karpet':
        return Icons.curtains_rounded;
      case 'child_care':
      case 'baby':
        return Icons.child_care_rounded;
      case 'bolt':
      case 'express':
        return Icons.bolt_rounded;
      default:
        return Icons.local_laundry_service_rounded;
    }
  }

  Widget _buildClaimsBanner() {
    final shop = _shop;
    if (shop == null || _claimsStream == null) return const SizedBox.shrink();
    return StreamBuilder<List<DamageClaim>>(
      stream: _claimsStream,
      builder: (context, snap) {
        final claims = snap.data ?? const <DamageClaim>[];
        if (claims.isEmpty) return const SizedBox.shrink();
        final pending = claims.where((c) => c.isPending).length;
        final urgent = pending > 0;
        final color = urgent ? const Color(0xFFD97706) : const Color(0xFF64748B);
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OwnerClaimsScreen(shopId: shop.id)),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: urgent ? const Color(0xFFFFFBEB) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: urgent ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(urgent ? Icons.report_problem_rounded : Icons.fact_check_outlined, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    urgent
                        ? '$pending klaim kerusakan menunggu verifikasi'
                        : 'Riwayat klaim kerusakan (${claims.length})',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        );
      },
    );
  }
}
