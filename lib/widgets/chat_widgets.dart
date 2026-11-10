import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_models.dart';
import '../screens/chat_inbox_screen.dart';
import '../services/chat_service.dart';
import '../utils/format_id.dart';

/// Token warna chat, sama dengan tema aplikasi
class CC {
  static const brand = Color(0xFF0077B6);
  static const brandSoft = Color(0xFFE0F2FE);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const bg = Color(0xFFF1F5F9);
  static const bad = Color(0xFFB91C1C);
  static const badBg = Color(0xFFFEE2E2);
  static const unread = Color(0xFFDC2626);
}

TextStyle cText(double size, {Color color = CC.body, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Waktu di daftar percakapan: hari ini → jam, kemarin → "Kemarin", lainnya → tanggal
String inboxTime(DateTime t) {
  final now = DateTime.now();
  if (sameDay(t, now)) return jam(t);
  if (sameDay(t, now.subtract(const Duration(days: 1)))) return 'Kemarin';
  return t.year == now.year ? tanggalPendek(t) : tanggal(t);
}

/// Pemisah tanggal di ruang chat
String dayLabel(DateTime t) {
  final now = DateTime.now();
  if (sameDay(t, now)) return 'Hari ini';
  if (sameDay(t, now.subtract(const Duration(days: 1)))) return 'Kemarin';
  return '${kHariSingkat[t.weekday - 1]}, ${tanggal(t)}';
}

class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final IconData? icon;
  const InitialAvatar({super.key, required this.name, this.size = 46, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: CC.brandSoft, borderRadius: BorderRadius.circular(size * 0.32)),
      child: icon != null
          ? Icon(icon, color: CC.brand, size: size * 0.5)
          : Text(
              t.isEmpty ? '?' : t.characters.first.toUpperCase(),
              style: GoogleFonts.quicksand(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: CC.brand),
            ),
    );
  }
}

class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: CC.unread, borderRadius: BorderRadius.circular(10)),
      child: Text(count > 99 ? '99+' : '$count', style: cText(11, color: Colors.white, weight: FontWeight.w800)),
    );
  }
}

/// Tombol chat dengan badge belum dibaca. Membuka kotak masuk chat.
/// [onDark] = di atas header berwarna (dashboard mitra).
/// [onNewMessage] dipanggil saat jumlah belum dibaca bertambah (notifikasi in-app).
class ChatInboxButton extends StatefulWidget {
  final bool asOwner;
  final bool onDark;
  final void Function(ChatConversation latest)? onNewMessage;
  const ChatInboxButton({super.key, required this.asOwner, this.onDark = false, this.onNewMessage});

  @override
  State<ChatInboxButton> createState() => _ChatInboxButtonState();
}

class _ChatInboxButtonState extends State<ChatInboxButton> {
  StreamSubscription<List<ChatConversation>>? _sub;
  Timer? _retry;
  int _unread = 0;
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = ChatService.instance.watchConversations(asOwner: widget.asOwner).listen(
      (list) {
        final me = ChatService.instance.uid ?? '';
        final total = list.where((c) => c.visibleFor(me)).fold<int>(0, (s, c) => s + c.unreadFor(me));
        if (total > 0) ChatService.instance.markDelivered(); // pesan sudah sampai di perangkat
        if (!_first && total > _unread && list.isNotEmpty) widget.onNewMessage?.call(list.first);
        _first = false;
        if (mounted) setState(() => _unread = total);
      },
      onError: (_) {
        // Tabel belum ada / koneksi putus: coba lagi pelan-pelan, badge tetap terakhir
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 20), () {
          if (mounted) _listen();
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.onDark;
    return Tooltip(
      message: _unread > 0 ? 'Chat, $_unread pesan belum dibaca' : 'Chat',
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatInboxScreen(asOwner: widget.asOwner)),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.22) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.35) : CC.border),
              ),
              child: Icon(
                _unread > 0 ? Icons.chat_rounded : Icons.chat_bubble_outline_rounded,
                color: dark ? Colors.white : (_unread > 0 ? CC.brand : CC.body),
                size: 21,
              ),
            ),
            if (_unread > 0)
              Positioned(top: -4, right: -4, child: UnreadBadge(count: _unread)),
          ],
        ),
      ),
    );
  }
}
