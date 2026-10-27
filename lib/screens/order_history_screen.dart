import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/order_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'dropoff_tracking_page.dart';
import 'order_tracking_page.dart';

const _blue = Color(0xFF0077E6);
const _surface = Color(0xFFF8FAFC);
const _bgOuter = Color(0xFFEDF2F7);
const _textDark = Color(0xFF0F172A);
const _textLight = Color(0xFF64748B);
const _textHint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);

const Map<String, Color> _statusColors = {
  'pending': Color(0xFF64748B),
  'washing': Color(0xFF0284C7),
  'drying': Color(0xFFD97706),
  'done': Color(0xFF16A34A),
  'delivered': Color(0xFF7C3AED),
  'cancelled': Color(0xFFDC2626),
};

String _formatRupiah(int amount) =>
    'Rp ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

String _formatDateTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${months[d.month - 1]} ${d.year} • '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Buka halaman pelacakan yang sesuai jenis pengiriman pesanan
Future<void> openOrderTracking(BuildContext context, OrderModel order) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => order.isDropoff
          ? DropoffTrackingPage(orderId: order.id)
          : OrderTrackingPage(orderId: order.id),
    ),
  );
}

/// Tombol "Lacak": buka pesanan aktif milik user.
/// 0 aktif → info + tawarkan Riwayat, 1 aktif → langsung buka, >1 → pilih dulu.
Future<void> openActiveOrderTracking(BuildContext context) async {
  final user = AuthService().currentUser;
  if (user == null) return;

  final messenger = ScaffoldMessenger.of(context);
  final orders = await SupabaseService().fetchUserOrders(user.id);
  if (!context.mounted) return;

  final active = orders.where((o) => o.isActive).toList();
  if (active.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Tidak ada pesanan aktif yang sedang diproses.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Riwayat',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
          ),
        ),
      ),
    );
    return;
  }

  if (active.length == 1) {
    await openOrderTracking(context, active.first);
    return;
  }

  final picked = await showModalBottomSheet<OrderModel>(
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
                decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Pilih Pesanan untuk Dilacak (${active.length})',
                style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800, color: _textDark),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: active.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => OrderCard(order: active[i], onTap: () => Navigator.pop(ctx, active[i])),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (picked != null && context.mounted) await openOrderTracking(context, picked);
}

/// Kartu ringkas satu pesanan (dipakai di Riwayat & pemilih pesanan Lacak)
class OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const OrderCard({super.key, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[order.status] ?? _textLight;
    final firstItem = order.items.isNotEmpty ? order.items.first.name : 'Layanan laundry';
    final extra = order.items.length > 1 ? ' +${order.items.length - 1} layanan' : '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: order.isCancelled ? color.withValues(alpha: 0.3) : _border),
          boxShadow: [
            BoxShadow(
              color: _textDark.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    order.isDropoff ? Icons.storefront_rounded : Icons.local_shipping_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.shopName.isEmpty ? 'Outlet Laundry' : order.shopName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark),
                      ),
                      Text(
                        _formatDateTime(order.createdAt),
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textHint),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.statusLabel,
                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$firstItem$extra',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatRupiah(order.totalPrice),
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: _blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Halaman Riwayat: semua pesanan user, realtime, dengan filter status
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  static const _filters = ['Semua', 'Aktif', 'Selesai', 'Dibatalkan'];
  String _activeFilter = 'Semua';
  Stream<List<OrderModel>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) _ordersStream = SupabaseService().getUserOrders(user.id);
  }

  List<OrderModel> _applyFilter(List<OrderModel> orders) {
    switch (_activeFilter) {
      case 'Aktif':
        return orders.where((o) => o.isActive).toList();
      case 'Selesai':
        return orders.where((o) => o.status == 'delivered').toList();
      case 'Dibatalkan':
        return orders.where((o) => o.isCancelled).toList();
      default:
        return orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgOuter,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            color: _surface,
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: _border)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
                        ),
                        Expanded(
                          child: Text(
                            'Riwayat Pesanan',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    children: _filters.map((f) {
                      final isSelected = f == _activeFilter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _activeFilter = f),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : _textLight,
                          ),
                          selectedColor: _blue,
                          backgroundColor: Colors.white,
                          side: BorderSide(color: isSelected ? _blue : _border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: _ordersStream == null
                      ? _buildEmpty('Silakan login untuk melihat riwayat pesanan.')
                      : StreamBuilder<List<OrderModel>>(
                          stream: _ordersStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return _buildEmpty('Gagal memuat pesanan. Periksa koneksi internet Anda.');
                            }
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator(color: _blue));
                            }
                            final orders = _applyFilter(snapshot.data!);
                            if (orders.isEmpty) {
                              return _buildEmpty(
                                _activeFilter == 'Semua'
                                    ? 'Belum ada pesanan. Yuk pesan laundry pertamamu!'
                                    : 'Tidak ada pesanan di kategori ini.',
                              );
                            }
                            return ListView.separated(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: orders.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => OrderCard(
                                order: orders[i],
                                onTap: () => openOrderTracking(context, orders[i]),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_rounded, size: 56, color: _textHint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textLight),
            ),
          ],
        ),
      ),
    );
  }
}
