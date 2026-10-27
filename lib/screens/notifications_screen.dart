import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'order_history_screen.dart';

const _blue = Color(0xFF0077E6);
const _blueLight = Color(0xFFEFF6FF);
const _surface = Color(0xFFF8FAFC);
const _bgOuter = Color(0xFFEDF2F7);
const _textDark = Color(0xFF0F172A);
const _textMid = Color(0xFF334155);
const _textLight = Color(0xFF64748B);
const _textHint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);

/// Ikon & warna notifikasi sesuai status pesanan yang memicunya
(IconData, Color) notificationStyle(String? status) {
  switch (status) {
    case 'washing':
      return (Icons.local_laundry_service_rounded, const Color(0xFF0284C7));
    case 'drying':
      return (Icons.iron_rounded, const Color(0xFFD97706));
    case 'done':
      return (Icons.inventory_2_rounded, const Color(0xFF16A34A));
    case 'delivered':
      return (Icons.check_circle_rounded, const Color(0xFF7C3AED));
    case 'cancelled':
      return (Icons.cancel_rounded, const Color(0xFFDC2626));
    default:
      return (Icons.receipt_long_rounded, const Color(0xFF64748B));
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final String? _userId = AuthService().currentUser?.id;
  Stream<List<NotificationModel>>? _stream;
  bool _openingOrder = false;

  @override
  void initState() {
    super.initState();
    if (_userId != null) _stream = _supabaseService.getUserNotifications(_userId);
  }

  Future<void> _openNotification(NotificationModel notif) async {
    if (_openingOrder) return;
    if (!notif.isRead) _supabaseService.markNotificationRead(notif.id);

    final messenger = ScaffoldMessenger.of(context);
    if (notif.orderId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Pesanan ini sudah dihapus oleh outlet.', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _openingOrder = true);
    final order = await _supabaseService.getOrderById(notif.orderId!);
    if (!mounted) return;
    setState(() => _openingOrder = false);

    if (order == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Pesanan ini sudah tidak tersedia.', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await openOrderTracking(context, order);
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
            child: StreamBuilder<List<NotificationModel>>(
              stream: _stream,
              builder: (context, snapshot) {
                final notifs = snapshot.data ?? const <NotificationModel>[];
                final unread = notifs.where((n) => !n.isRead).length;

                return Column(
                  children: [
                    _buildHeader(unread),
                    if (_openingOrder) const LinearProgressIndicator(minHeight: 2, color: _blue),
                    Expanded(child: _buildBody(snapshot, notifs)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int unread) {
    return SafeArea(
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
                unread > 0 ? 'Notifikasi ($unread baru)' : 'Notifikasi',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark),
              ),
            ),
            IconButton(
              tooltip: 'Tandai semua dibaca',
              onPressed: unread == 0 || _userId == null
                  ? null
                  : () => _supabaseService.markAllNotificationsRead(_userId),
              icon: Icon(Icons.done_all_rounded, color: unread == 0 ? _textHint : _blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AsyncSnapshot<List<NotificationModel>> snapshot, List<NotificationModel> notifs) {
    if (_stream == null) {
      return _buildEmpty('Silakan login untuk melihat notifikasi.');
    }
    if (snapshot.hasError) {
      return _buildEmpty('Gagal memuat notifikasi. Periksa koneksi internet Anda.');
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (notifs.isEmpty) {
      return _buildEmpty('Belum ada notifikasi.\nKabar status pesananmu akan muncul di sini.');
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: notifs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildItem(notifs[i]),
    );
  }

  Widget _buildItem(NotificationModel notif) {
    final (icon, color) = notificationStyle(notif.status);
    return InkWell(
      onTap: () => _openNotification(notif),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead ? Colors.white : _blueLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: notif.isRead ? _border : _blue.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                            color: _textDark,
                          ),
                        ),
                      ),
                      if (!notif.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notif.body,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMid, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(notif.createdAt),
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textHint),
                  ),
                ],
              ),
            ),
          ],
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
            const Icon(Icons.notifications_none_rounded, size: 56, color: _textHint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textLight, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
