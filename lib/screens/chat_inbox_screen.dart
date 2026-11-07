import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/chat_models.dart';
import '../services/chat_service.dart';
import '../widgets/chat_widgets.dart';
import 'chat_room_screen.dart';

/// Kotak masuk chat. Mitra melihat percakapan dengan pelanggan outletnya,
/// pelanggan melihat percakapan dengan outlet tempat ia memesan.
class ChatInboxScreen extends StatefulWidget {
  final bool asOwner;
  const ChatInboxScreen({super.key, required this.asOwner});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final _service = ChatService.instance;
  final _search = TextEditingController();
  StreamSubscription<List<ChatConversation>>? _sub;
  Timer? _retry;

  List<ChatConversation>? _items;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _listen();
    _service.markDelivered();
  }

  void _listen() {
    _sub?.cancel();
    _retry?.cancel();
    setState(() => _error = null);
    _sub = _service.watchConversations(asOwner: widget.asOwner).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _error = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        final msg = e.toString().contains('chat_conversations')
            ? 'Fitur chat belum aktif. Jalankan supabase_chat.sql di Supabase SQL Editor.'
            : 'Koneksi terputus. Menyambung ulang…';
        setState(() => _error = msg);
        _retry = Timer(const Duration(seconds: 5), () {
          if (mounted) _listen();
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<ChatConversation> _filtered(String me) {
    final q = _query.trim().toLowerCase().replaceAll('#', '');
    // Mitra hanya melihat percakapan yang sudah berisi pesan; pelanggan melihat semua yang ia buka
    final items = (_items ?? const <ChatConversation>[]).where((c) => c.lastMessageAt != null || !c.isOwner(me));
    if (q.isEmpty) return items.toList();
    return items
        .where((c) => c.partnerName(me).toLowerCase().contains(q) || c.orderCode.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final me = _service.uid ?? '';
    final items = _filtered(me);
    final totalUnread = (_items ?? const []).fold<int>(0, (s, c) => s + c.unreadFor(me));

    return Scaffold(
      backgroundColor: CC.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: CC.ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chat', style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.w700, color: CC.ink)),
            Text(
              totalUnread > 0 ? '$totalUnread pesan belum dibaca' : (widget.asOwner ? 'Pelanggan outlet Anda' : 'Outlet tempat Anda memesan'),
              style: cText(11.5, color: CC.muted),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: widget.asOwner ? 'Cari nama pelanggan atau no. pesanan' : 'Cari outlet atau no. pesanan',
                    hintStyle: cText(13, color: CC.faint),
                    prefixIcon: const Icon(Icons.search_rounded, color: CC.muted),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: CC.bg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFFEF3C7),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(_error!, style: cText(12, color: const Color(0xFFB45309))),
                ),
              Expanded(child: _list(items, me)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<ChatConversation> items, String me) {
    if (_items == null) {
      return _error != null
          ? const SizedBox.shrink()
          : const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: CC.brand));
    }
    if (_items!.isEmpty || items.isEmpty && _query.isEmpty) {
      return _empty(
        Icons.forum_outlined,
        'Belum ada percakapan',
        widget.asOwner
            ? 'Pesan dari pelanggan akan muncul di sini. Anda juga bisa memulai chat dari detail pesanan di dashboard.'
            : 'Mulai chat dari halaman lacak pesanan dengan menekan tombol chat di kartu outlet.',
      );
    }
    if (items.isEmpty) {
      return _empty(Icons.search_off_rounded, 'Tidak ditemukan', 'Tidak ada percakapan yang cocok dengan "$_query".');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 74, color: CC.border),
      itemBuilder: (_, i) => _ConversationTile(conversation: items[i], me: me),
    );
  }

  Widget _empty(IconData icon, String title, String message) {
    return ListView(
      children: [
        const SizedBox(height: 64),
        Icon(icon, size: 40, color: CC.faint),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.w700, color: CC.ink)),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
          child: Text(message, textAlign: TextAlign.center, style: cText(12.5, color: CC.muted)),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final String me;
  const _ConversationTile({required this.conversation, required this.me});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unreadFor(me);
    final mine = c.lastSenderId == me;
    final preview = c.lastMessagePreview.isEmpty ? 'Belum ada pesan' : '${mine ? 'Anda: ' : ''}${c.lastMessagePreview}';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: c)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              InitialAvatar(
                name: c.partnerName(me),
                icon: c.isOwner(me) ? null : Icons.local_laundry_service_rounded,
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
                            c.partnerName(me),
                            overflow: TextOverflow.ellipsis,
                            style: cText(14, color: CC.ink, weight: unread > 0 ? FontWeight.w800 : FontWeight.w700),
                          ),
                        ),
                        if (c.lastMessageAt != null)
                          Text(
                            inboxTime(c.lastMessageAt!),
                            style: cText(11, color: unread > 0 ? CC.brand : CC.faint, weight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Pesanan #${c.orderCode}', style: cText(11, color: CC.muted, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (c.isBlocked) ...[
                          const Icon(Icons.block_rounded, size: 13, color: CC.bad),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            c.isBlocked ? 'Percakapan diblokir' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: cText(12.5, color: unread > 0 ? CC.ink : CC.muted, weight: unread > 0 ? FontWeight.w600 : FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UnreadBadge(count: unread),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
