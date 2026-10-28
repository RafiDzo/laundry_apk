import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/evidence_models.dart';
import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../services/auth_service.dart';
import '../services/evidence_service.dart';
import '../services/supabase_service.dart';
import 'owner_claims_screen.dart';
import 'owner_evidence_sheets.dart';
import 'partner/partner_profile_screen.dart';
import 'partner/partner_revenue_screen.dart';
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
  String _activeFilter = 'Semua';

  ShopModel? _shop;
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

  // Token & mesin IoT masih simulasi (belum ada integrasi perangkat)
  int _tokenCount = 857;
  final List<Map<String, dynamic>> _iotMachines = [
    {'name': 'Washer 01 (Front Load)', 'type': 'Cuci', 'status': 'Running', 'time': '18 Menit', 'progress': 0.65},
    {'name': 'Washer 02 (Top Load)', 'type': 'Cuci', 'status': 'Idle', 'time': 'Tersedia', 'progress': 0.0},
    {'name': 'Dryer 01 (Gas 10 Kg)', 'type': 'Kering', 'status': 'Running', 'time': '24 Menit', 'progress': 0.40},
    {'name': 'Dryer 02 (Gas 10 Kg)', 'type': 'Kering', 'status': 'Idle', 'time': 'Tersedia', 'progress': 0.0},
  ];

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
    final shop = await _supabaseService.getMyShop();
    if (!mounted) return;
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
        print('Error stream pesanan toko: $e');
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
    ScaffoldMessenger.of(context).showSnackBar(
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
    Map<String, dynamic> selectedService = _walkInServices.first;
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
                  DropdownButtonFormField<String>(
                    initialValue: selectedService['name'] as String,
                    decoration: InputDecoration(
                      labelText: 'Pilihan Layanan',
                      prefixIcon: const Icon(Icons.local_laundry_service_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    items: _walkInServices
                        .map((s) => DropdownMenuItem(value: s['name'] as String, child: Text(s['label'] as String)))
                        .toList(),
                    onChanged: (val) {
                      setModalState(() {
                        selectedService = _walkInServices.firstWhere((s) => s['name'] == val);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: selectedService['unit'] == 'kg' ? 'Berat Cucian (Kg)' : 'Jumlah (Pcs)',
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
                messenger.showSnackBar(
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

  void _showDeleteAllCancelledConfirmation(List<OrderModel> cancelledOrders) {
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
              child: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Hapus Semua Dibatalkan?',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus semua ${cancelledOrders.length} pesanan yang dibatalkan?\n\nSemua data pesanan ini akan dihapus permanen dari sistem.',
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
              final shop = _shop;
              if (shop == null) return;
              final messenger = ScaffoldMessenger.of(context);
              final cancelledIds = _orders.where((o) => o.status == 'cancelled').map((o) => o.id).toList();
              final deletedCount = await _supabaseService.deleteCancelledOrders(shop.id);
              if (deletedCount > 0 && mounted) _removeOrdersLocally(cancelledIds);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(deletedCount > 0
                        ? '$deletedCount pesanan dibatalkan berhasil dihapus permanen.'
                        : 'Tidak ada pesanan yang dihapus.'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            child: Text(
              'Hapus Semua',
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
            messenger.showSnackBar(const SnackBar(
              content: Text('Ubah status ke "Selesai" dulu sebelum serah terima ke pelanggan.'),
            ));
            return;
          }
          final ok = await showHandoverSheet(context, order);
          if (ok) {
            messenger.showSnackBar(const SnackBar(
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
        messenger.showSnackBar(
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
  Future<void> _showPettyCashModal() async {
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

  // 4. Modal Sistem IoT Mesin (simulasi)
  void _showIoTModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sensors_rounded, color: Color(0xFF0077B6)),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sistem IoT Smart Laundry', style: GoogleFonts.quicksand(fontSize: 17, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text('Mode Simulasi (belum terhubung ke mesin)', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFD97706))),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 20),
              ..._iotMachines.map((m) {
                final isRunning = m['status'] == 'Running';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        m['type'] == 'Cuci' ? Icons.local_laundry_service : Icons.cyclone,
                        color: isRunning ? const Color(0xFF0077B6) : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('Status: ${m['status']} (${m['time']})', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setModalState(() {
                            m['status'] = isRunning ? 'Idle' : 'Running';
                            m['time'] = isRunning ? 'Tersedia' : '30 Menit';
                          });
                        },
                        child: Text(
                          isRunning ? 'Stop Mesin' : 'Nyalakan',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
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
                                    '${c['phone'] ?? 'Tanpa nomor'} • ${c['orders']} pesanan',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatRupiah(c['total'] as int),
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF0077B6)),
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

  // ================= MAIN UI BUILD =================

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _orders.where((o) {
      if (_activeFilter == 'Antrean') return o.status == 'pending';
      if (_activeFilter == 'Proses') return o.status == 'washing' || o.status == 'drying';
      if (_activeFilter == 'Selesai') return o.status == 'done' || o.status == 'delivered';
      if (_activeFilter == 'Dibatalkan') return o.status == 'cancelled';
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
                      else ...[
                        // 2. QUICK METRIC STATS
                        _buildMetricsRow(),

                        const SizedBox(height: 16),

                        // 3. MENU GRID
                        _buildMenuGrid(),

                        const SizedBox(height: 24),

                        // 4. RECENT ORDERS (Live Feed Daftar Pesanan)
                        _buildRecentOrderSection(filteredOrders),
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
      print('Error createMyShop: $e');
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
                            child: Icon(
                              Icons.local_laundry_service_rounded,
                              color: Color(0xFF0091EA),
                              size: 26,
                            ),
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

                    // Logout Button
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

                  // Right: Cash Topup Card (matching user screenshot)
                  GestureDetector(
                    onTap: () {
                      setState(() => _tokenCount += 100);
                      _showSnack('Simulasi: +100 token (belum ada pembayaran sungguhan).');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Topup',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF059669),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 8,
                                    color: Color(0xFF059669),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Token $_tokenCount',
                                style: GoogleFonts.quicksand(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // IoT Shortcut Banner
              GestureDetector(
                onTap: _showIoTModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.wifi_rounded, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Smart Machine Control (Mode Simulasi)',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB45309)),
                    ],
                  ),
                ),
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
              _buildMenuItem(
                title: 'Order',
                icon: Icons.shopping_cart_outlined,
                color: const Color(0xFF0077B6),
                onTap: _showNewOrderDialog,
              ),
              _buildMenuItem(
                title: 'List Order',
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF0284C7),
                onTap: () {
                  setState(() => _activeFilter = 'Semua');
                },
              ),
              _buildMenuItem(
                title: 'Petty Cash',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFD97706),
                onTap: _showPettyCashModal,
              ),
              _buildMenuItem(
                title: 'Report',
                icon: Icons.insert_chart_outlined_rounded,
                color: const Color(0xFF2563EB),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PartnerRevenueScreen()),
                ),
              ),
              _buildMenuItem(
                title: 'Customer',
                icon: Icons.people_alt_outlined,
                color: const Color(0xFF059669),
                onTap: _showCustomerModal,
              ),
              _buildMenuItem(
                title: 'Mesin IoT',
                icon: Icons.sensors_rounded,
                color: const Color(0xFF0D9488),
                onTap: _showIoTModal,
              ),
              _buildMenuItem(
                title: 'Tarif Layanan',
                icon: Icons.local_offer_outlined,
                color: const Color(0xFF7C3AED),
                onTap: _showTarifModal,
              ),
              _buildMenuItem(
                title: 'Pengaturan',
                icon: Icons.tune_rounded,
                color: const Color(0xFF64748B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PartnerProfileScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  void _showTarifModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_offer_outlined, color: Color(0xFF7C3AED), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tarif & Layanan Outlet',
                          style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                        ),
                        Text(
                          _shop?.name ?? 'Katalog Paket Cucian',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildTarifItem('Cuci Komplit', 'Cuci + Pengering + Setrika Rapih', 'Rp 8.000 / Kg', const Color(0xFF0077B6), '2 Hari'),
                  _buildTarifItem('Cuci Kering', 'Cuci + Pengering Lipat (Tanpa Setrika)', 'Rp 6.000 / Kg', const Color(0xFF0284C7), '1 Hari'),
                  _buildTarifItem('Setrika Saja', 'Hanya Setrika & Packing Plastik', 'Rp 5.000 / Kg', const Color(0xFFD97706), '1 Hari'),
                  _buildTarifItem('Bedcover / Selimut', 'Pencucian Khusus Linen Tebal & Bedcover', 'Rp 25.000 / Pcs', const Color(0xFF7C3AED), '2 Hari'),
                  _buildTarifItem('Sepatu / Helm', 'Deep Clean Treatment Sepatu & Helm', 'Rp 20.000 / Pcs', const Color(0xFF059669), '2 Hari'),
                  _buildTarifItem('Express Service', 'Layanan Prioritas Selesai dalam 24 Jam', '+Rp 4.000 / Kg', const Color(0xFFDC2626), '1 Hari'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarifItem(String name, String desc, String price, Color color, String duration) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: GoogleFonts.quicksand(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(duration, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(desc, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          Text(price, style: GoogleFonts.quicksand(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
        ],
      ),
    );
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

  Widget _buildRecentOrderSection(List<OrderModel> orders) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildClaimsBanner(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Order',
                style: GoogleFonts.quicksand(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              if (_activeFilter == 'Dibatalkan' && orders.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onPressed: () => _showDeleteAllCancelledConfirmation(orders),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: Text(
                    'Bersihkan Semua (${orders.length})',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else
                Text(
                  'Total: ${orders.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Semua', 'Antrean', 'Proses', 'Selesai', 'Dibatalkan'].map((tab) {
                final isSelected = _activeFilter == tab;
                return GestureDetector(
                  onTap: () => setState(() => _activeFilter = tab),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
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
              child: Text('Tidak ada pesanan di kategori ini', style: GoogleFonts.inter(color: Colors.grey)),
            )
          else
            ListView.separated(
              itemCount: orders.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final order = orders[idx];
                return _buildOrderCard(order);
              },
            ),
        ],
      ),
    );
  }

  Color _statusSolidColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'washing':
      case 'drying':
        return const Color(0xFF0284C7);
      case 'done':
      case 'delivered':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildOrderCard(OrderModel order) {
    final statusBgColor = _statusSolidColor(order.status);

    return InkWell(
      onTap: () => _showOrderActionModal(order),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Kiri: Nama Customer di atas, Tanggal & No. Nota di bawah
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _customerName(order),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDate(order.createdAt)} - ${_orderCode(order)} • ${_serviceName(order)}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Kanan: Status pill hijau/solid di atas, Nominal Rp di bawah (Sesuai Gambar 2)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: statusBgColor.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatRupiah(order.totalPrice),
                  style: GoogleFonts.quicksand(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            if (order.status == 'cancelled') ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                tooltip: 'Hapus pesanan ini',
                visualDensity: VisualDensity.compact,
                onPressed: () => _showDeleteOrderConfirmation(order),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
