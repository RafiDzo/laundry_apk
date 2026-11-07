import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../models/chat_models.dart';
import '../models/order_model.dart';
import '../services/chat_service.dart';
import '../services/supabase_service.dart';
import '../utils/format_id.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/quick_snackbar.dart';
import '../widgets/report_widgets.dart' show showTransactionDetail;
import 'order_history_screen.dart' show openOrderTracking;

/// Buka chat untuk satu pesanan dari mana saja (halaman lacak, dashboard, notifikasi).
/// [fromOrderPage] = dibuka dari halaman detail pesanan itu sendiri, sehingga
/// mengetuk kartu pesanan cukup kembali ke halaman sebelumnya.
Future<void> openChatForOrder(BuildContext context, String orderId, {bool fromOrderPage = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
  );
  try {
    final conv = await ChatService.instance.openConversation(orderId);
    if (!context.mounted) return;
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conv, fromOrderPage: fromOrderPage)),
    );
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    messenger.showQuickSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: CC.bad));
  }
}

class ChatRoomScreen extends StatefulWidget {
  final ChatConversation conversation;
  final bool fromOrderPage;
  const ChatRoomScreen({super.key, required this.conversation, this.fromOrderPage = false});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with WidgetsBindingObserver {
  final _service = ChatService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  late ChatConversation _conv = widget.conversation;
  late final String _me = _service.uid ?? '';
  bool get _isOwner => _conv.isOwner(_me);

  /// Pesan TERBARU di indeks 0 (ListView terbalik)
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _loadError;
  bool _hasOlder = true;
  bool _loadingOlder = false;

  RealtimeChannel? _channel;
  bool _connected = false;
  Timer? _poll;
  Timer? _readDebounce;
  bool _appVisible = true;

  bool _partnerTyping = false;
  Timer? _partnerTypingTimer;
  DateTime _lastTypingSent = DateTime(2000);
  Timer? _stopTypingTimer;

  bool _showJump = false;
  int _newWhileAway = 0;

  StreamSubscription<OrderModel?>? _orderSub;
  OrderModel? _order;

  List<QuickReply> _quickReplies = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _loadInitial();
    _subscribe();
    _orderSub = SupabaseService().watchOrder(_conv.orderId).listen((o) {
      if (mounted) setState(() => _order = o);
    }, onError: (_) {});
    if (_isOwner) _loadQuickReplies();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    if (_appVisible) _scheduleRead();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final ch = _channel;
    if (ch != null) {
      _service.sendTyping(ch, false);
      _service.unsubscribe(ch);
    }
    _poll?.cancel();
    _readDebounce?.cancel();
    _partnerTypingTimer?.cancel();
    _stopTypingTimer?.cancel();
    _orderSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ===================== DATA =====================

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _service.fetchMessages(_conv.id);
      if (!mounted) return;
      setState(() {
        for (final m in page) {
          _upsert(m, notify: false);
        }
        _hasOlder = page.length == ChatService.pageSize;
        _loading = false;
      });
      _scheduleRead();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    final oldest = _messages.lastWhere((m) => !m.pending && !m.failed, orElse: () => _messages.last);
    setState(() => _loadingOlder = true);
    try {
      final page = await _service.fetchMessages(_conv.id, before: oldest.createdAt);
      if (!mounted) return;
      setState(() {
        for (final m in page) {
          _upsert(m, notify: false);
        }
        _hasOlder = page.length == ChatService.pageSize;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Gabungkan pesan dari server/realtime/optimistic. Dicocokkan lewat id atau client_id.
  /// Harus dipanggil di dalam setState.
  void _upsert(ChatMessage m, {bool notify = true}) {
    final idx = _messages.indexWhere(
      (x) => x.id == m.id || (m.clientId != null && x.clientId == m.clientId),
    );
    if (idx >= 0) {
      // Pertahankan pratinjau lokal gambar sampai URL server siap
      _messages[idx] = m.localBytes == null && _messages[idx].localBytes != null && !m.pending
          ? ChatMessage(
              id: m.id,
              conversationId: m.conversationId,
              senderId: m.senderId,
              type: m.type,
              body: m.body,
              createdAt: m.createdAt,
              imagePath: m.imagePath,
              clientId: m.clientId,
              deliveredAt: m.deliveredAt,
              readAt: m.readAt,
              localBytes: _messages[idx].localBytes,
            )
          : m;
      return;
    }
    // Sisipkan terurut (terbaru di depan)
    var pos = 0;
    while (pos < _messages.length && _messages[pos].createdAt.isAfter(m.createdAt)) {
      pos++;
    }
    _messages.insert(pos, m);
    if (notify && m.senderId != _me) {
      if (_showJump) _newWhileAway++;
      _partnerTyping = false;
    }
  }

  void _subscribe() {
    _channel = _service.subscribeRoom(
      _conv.id,
      onUpsert: (m) {
        if (!mounted) return;
        setState(() => _upsert(m));
        if (m.senderId != _me) _scheduleRead();
      },
      onTyping: (_, typing) {
        if (!mounted) return;
        setState(() => _partnerTyping = typing);
        _partnerTypingTimer?.cancel();
        if (typing) {
          // Jaga-jaga jika sinyal "berhenti mengetik" tidak sampai
          _partnerTypingTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _partnerTyping = false);
          });
        }
      },
      onStatus: (connected) {
        if (!mounted) return;
        setState(() => _connected = connected);
        if (connected) {
          _poll?.cancel();
          _poll = null;
          _refreshLatest(); // ambil pesan yang mungkin terlewat saat terputus
        } else {
          _startPolling();
        }
      },
    );
    // Jika realtime tidak tersambung dalam 8 detik, mulai polling
    Timer(const Duration(seconds: 8), () {
      if (mounted && !_connected) _startPolling();
    });
  }

  /// Cadangan saat WebSocket terputus: ambil pesan terbaru tiap 5 detik
  void _startPolling() {
    if (_poll != null) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshLatest());
  }

  Future<void> _refreshLatest() async {
    try {
      final page = await _service.fetchMessages(_conv.id);
      if (!mounted) return;
      final hadUnread = page.any((m) => m.senderId != _me && m.readAt == null);
      setState(() {
        for (final m in page) {
          _upsert(m);
        }
      });
      if (hadUnread) _scheduleRead();
      final fresh = await _service.getConversation(_conv.id);
      if (fresh != null && mounted) setState(() => _conv = fresh);
    } catch (_) {}
  }

  void _scheduleRead() {
    if (!_appVisible) return;
    if (!_messages.any((m) => m.senderId != _me && m.readAt == null)) return;
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 600), () => _service.markRead(_conv.id));
  }

  Future<void> _loadQuickReplies() async {
    try {
      final list = await _service.fetchQuickReplies();
      if (mounted) setState(() => _quickReplies = list);
    } catch (_) {
      // Template opsional; chat tetap jalan tanpanya
    }
  }

  // ===================== KIRIM =====================

  Future<void> _sendText([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty) return;
    if (text.length > 2000) {
      _snack('Pesan maksimal 2000 karakter.');
      return;
    }
    if (override == null) _input.clear();
    _sendTypingState(false);
    final clientId = ChatService.newClientId();
    final local = ChatMessage(
      id: clientId,
      conversationId: _conv.id,
      senderId: _me,
      type: 'text',
      body: text,
      clientId: clientId,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() => _upsert(local, notify: false));
    _jumpToLatest();
    await _deliver(local);
  }

  Future<void> _deliver(ChatMessage local) async {
    try {
      final saved = local.isImage
          ? await _service.sendImage(
              _conv.id,
              Uint8List.fromList(local.localBytes!),
              clientId: local.clientId!,
              caption: local.body,
              mime: local.imagePath ?? 'image/jpeg',
            )
          : await _service.sendText(_conv.id, local.body, local.clientId!);
      if (mounted) setState(() => _upsert(saved, notify: false));
    } catch (e) {
      if (!mounted) return;
      setState(() => _upsert(local.copyWith(pending: false, failed: true), notify: false));
      _snack(e.toString());
    }
  }

  Future<void> _retry(ChatMessage m) async {
    setState(() => _upsert(m.copyWith(pending: true, failed: false), notify: false));
    await _deliver(m.copyWith(pending: true, failed: false));
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Kompresi sebelum unggah: sisi terpanjang 1280px, kualitas JPEG 70
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > ChatService.maxImageBytes) {
        _snack('Ukuran foto melebihi 3 MB setelah dikompres. Pilih foto lain.');
        return;
      }
      final name = file.name.toLowerCase();
      final mime = file.mimeType ??
          (name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
        _snack('Format foto harus JPG, PNG, atau WEBP.');
        return;
      }
      final caption = _input.text.trim();
      _input.clear();
      final clientId = ChatService.newClientId();
      final local = ChatMessage(
        id: clientId,
        conversationId: _conv.id,
        senderId: _me,
        type: 'image',
        body: caption,
        imagePath: mime, // sementara dipakai menyimpan MIME sampai terunggah
        clientId: clientId,
        createdAt: DateTime.now(),
        pending: true,
        localBytes: bytes,
      );
      setState(() => _upsert(local, notify: false));
      _jumpToLatest();
      await _deliver(local);
    } catch (e) {
      _snack('Foto tidak bisa dibuka: $e');
    }
  }

  void _onInputChanged(String v) {
    final now = DateTime.now();
    if (v.trim().isNotEmpty && now.difference(_lastTypingSent) > const Duration(seconds: 3)) {
      _sendTypingState(true);
    }
    _stopTypingTimer?.cancel();
    _stopTypingTimer = Timer(const Duration(milliseconds: 2500), () => _sendTypingState(false));
    setState(() {}); // ikon kirim aktif/nonaktif
  }

  void _sendTypingState(bool typing) {
    final ch = _channel;
    if (ch == null || !_connected) return;
    if (typing) _lastTypingSent = DateTime.now();
    if (!typing) _lastTypingSent = DateTime(2000);
    _service.sendTyping(ch, typing);
  }

  // ===================== SCROLL =====================

  void _onScroll() {
    final away = _scroll.offset > 320;
    if (away != _showJump) {
      setState(() {
        _showJump = away;
        if (!away) _newWhileAway = 0;
      });
    }
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadOlder();
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    setState(() => _newWhileAway = 0);
  }

  // ===================== AKSI =====================

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _openOrder() {
    final o = _order;
    if (o == null) return;
    if (_isOwner) {
      showTransactionDetail(context, o);
    } else if (widget.fromOrderPage) {
      Navigator.pop(context);
    } else {
      openOrderTracking(context, o);
    }
  }

  Future<void> _toggleBlock() async {
    final blocking = !_conv.isBlocked;
    if (!blocking && _conv.blockedBy != _me) return;
    if (blocking) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Blokir percakapan?'),
          content: Text(
            '${_conv.partnerName(_me)} tidak akan bisa mengirim pesan di percakapan pesanan #${_conv.orderCode}. '
            'Anda bisa membuka blokir kapan saja.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: CC.bad),
              child: const Text('Blokir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final c = await _service.setBlocked(_conv.id, blocking);
      if (!mounted) return;
      setState(() => _conv = c);
      _snack(blocking ? 'Percakapan diblokir.' : 'Blokir dibuka.');
    } catch (e) {
      _snack(e.toString(), color: CC.bad);
    }
  }

  Future<void> _report({ChatMessage? message}) async {
    const reasons = ['Kata-kata kasar atau menghina', 'Penipuan atau meminta data pribadi', 'Spam', 'Lainnya'];
    final otherCtrl = TextEditingController();
    String? picked;
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(8, 16, 8, MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(message != null ? 'Laporkan pesan' : 'Laporkan ${_conv.partnerName(_me)}',
                    style: GoogleFonts.quicksand(fontSize: 17, fontWeight: FontWeight.w700, color: CC.ink)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Text('Laporan dikirim ke tim Washora untuk ditinjau.', style: cText(12, color: CC.muted)),
              ),
              RadioGroup<String>(
                groupValue: picked,
                onChanged: (v) => setSheet(() => picked = v),
                child: Column(
                  children: [
                    for (final r in reasons)
                      RadioListTile<String>(
                        value: r,
                        title: Text(r, style: cText(13.5, color: CC.ink)),
                        dense: false,
                      ),
                  ],
                ),
              ),
              if (picked == 'Lainnya')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: otherCtrl,
                    maxLength: 300,
                    decoration: const InputDecoration(hintText: 'Jelaskan singkat'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: CC.bad),
                    onPressed: picked == null
                        ? null
                        : () {
                            final text = picked == 'Lainnya' ? otherCtrl.text.trim() : picked!;
                            Navigator.pop(ctx, text.isEmpty ? 'Lainnya' : text);
                          },
                    child: const Text('Kirim laporan'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    otherCtrl.dispose();
    if (reason == null) return;
    try {
      await _service.report(conversationId: _conv.id, messageId: message?.id, reason: reason);
      _snack('Laporan terkirim. Terima kasih.', color: const Color(0xFF15803D));
    } catch (e) {
      _snack(e.toString(), color: CC.bad);
    }
  }

  void _messageActions(ChatMessage m) {
    final mine = m.senderId == _me;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (m.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Salin teks'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.body));
                  Navigator.pop(ctx);
                  _snack('Teks disalin.');
                },
              ),
            if (m.failed)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Kirim ulang'),
                onTap: () {
                  Navigator.pop(ctx);
                  _retry(m);
                },
              ),
            if (!mine && !m.pending)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: CC.bad),
                title: const Text('Laporkan pesan', style: TextStyle(color: CC.bad)),
                onTap: () {
                  Navigator.pop(ctx);
                  _report(message: m);
                },
              ),
            if (mine && m.state != MessageState.sending && m.state != MessageState.failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoLine('Terkirim', tanggalJam(m.createdAt)),
                    _infoLine('Diterima', m.deliveredAt == null ? 'Belum' : tanggalJam(m.deliveredAt!)),
                    _infoLine('Dibaca', m.readAt == null ? 'Belum' : tanggalJam(m.readAt!)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 80, child: Text(k, style: cText(12.5, color: CC.muted))),
          Text(v, style: cText(12.5, color: CC.ink, weight: FontWeight.w600)),
        ]),
      );

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    final partner = _conv.partnerName(_me);
    final blockedByMe = _conv.blockedBy == _me;
    return Scaffold(
      backgroundColor: CC.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: CC.ink,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            InitialAvatar(name: partner, size: 38, icon: _isOwner ? null : Icons.local_laundry_service_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(partner, overflow: TextOverflow.ellipsis, style: cText(15, color: CC.ink, weight: FontWeight.w700)),
                  Text(
                    _partnerTyping ? 'sedang mengetik…' : 'Chat Pesanan #${_conv.orderCode}',
                    style: cText(11.5, color: _partnerTyping ? CC.brand : CC.muted, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opsi percakapan',
            onSelected: (v) {
              if (v == 'report') _report();
              if (v == 'block') _toggleBlock();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('Laporkan pengguna')),
              if (!_conv.isBlocked || blockedByMe)
                PopupMenuItem(value: 'block', child: Text(_conv.isBlocked ? 'Buka blokir' : 'Blokir')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _orderCard(),
          if (!_connected && !_loading)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('Koneksi realtime terputus. Pesan diperbarui tiap 5 detik.',
                  style: cText(11.5, color: const Color(0xFFB45309))),
            ),
          Expanded(
            child: Stack(
              children: [
                _messageList(),
                if (_showJump)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: Material(
                      color: Colors.white,
                      elevation: 3,
                      shape: const StadiumBorder(side: BorderSide(color: CC.border)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: _jumpToLatest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_downward_rounded, size: 18, color: CC.brand),
                              const SizedBox(width: 6),
                              Text(
                                _newWhileAway > 0 ? '$_newWhileAway pesan baru' : 'Ke pesan terbaru',
                                style: cText(12.5, color: CC.brand, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_partnerTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('$partner sedang mengetik…', style: cText(11.5, color: CC.muted)),
              ),
            ),
          if (_conv.isBlocked) _blockedBar(blockedByMe) else _composer(),
        ],
      ),
    );
  }

  Widget _orderCard() {
    final o = _order;
    final status = o == null ? null : OrderModel.statusLabels[o.status];
    final services = o == null
        ? ''
        : (o.items.isEmpty ? 'Layanan tidak dicatat' : o.items.map((i) => i.name).join(', '));
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: o == null ? null : _openOrder,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: CC.border), bottom: BorderSide(color: CC.border))),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: CC.bg, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_outlined, color: CC.body, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: o == null
                    ? Text('Memuat info pesanan #${_conv.orderCode}…', style: cText(12.5, color: CC.muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text('Pesanan #${_conv.orderCode}',
                                    style: cText(13, color: CC.ink, weight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                              _statusChip(o.status, status ?? o.status),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$services · ${rupiah(o.totalPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: cText(11.5, color: CC.muted),
                          ),
                          Text(
                            o.receivedAt != null
                                ? 'Diterima pelanggan ${tanggalJam(o.receivedAt!)}'
                                : 'Dipesan ${tanggalJam(o.createdAt)}',
                            style: cText(11, color: CC.faint),
                          ),
                        ],
                      ),
              ),
              if (o != null) const Icon(Icons.chevron_right_rounded, color: CC.faint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status, String label) {
    final (fg, bg) = switch (status) {
      'cancelled' => (const Color(0xFFB91C1C), const Color(0xFFFEE2E2)),
      'done' || 'delivered' => (const Color(0xFF15803D), const Color(0xFFDCFCE7)),
      _ => (const Color(0xFFB45309), const Color(0xFFFEF3C7)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: cText(10.5, color: fg, weight: FontWeight.w700)),
    );
  }

  Widget _messageList() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: CC.brand));
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: CC.bad, size: 32),
              const SizedBox(height: 10),
              Text('Pesan gagal dimuat', style: cText(15, color: CC.ink, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_loadError!, textAlign: TextAlign.center, style: cText(12.5, color: CC.muted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, color: CC.faint, size: 36),
              const SizedBox(height: 10),
              Text('Belum ada pesan', style: cText(15, color: CC.ink, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                _isOwner
                    ? 'Sapa pelanggan atau kirim kabar terbaru tentang cuciannya.'
                    : 'Tanyakan apa saja tentang pesanan #${_conv.orderCode} ke ${_conv.partnerName(_me)}.',
                textAlign: TextAlign.center,
                style: cText(12.5, color: CC.muted),
              ),
            ],
          ),
        ),
      );
    }

    final latestMine = _messages.indexWhere((x) => x.senderId == _me);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _messages.length + (_hasOlder ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final m = _messages[i];
        final older = i + 1 < _messages.length ? _messages[i + 1] : null;
        final newer = i > 0 ? _messages[i - 1] : null;
        final showDay = older == null || !sameDay(older.createdAt, m.createdAt);
        // Rapatkan bubble berurutan dari pengirim yang sama
        final groupedWithNewer = newer != null &&
            newer.senderId == m.senderId &&
            sameDay(newer.createdAt, m.createdAt) &&
            newer.createdAt.difference(m.createdAt).inMinutes < 3;
        return Column(
          children: [
            if (showDay) _daySeparator(m.createdAt),
            _Bubble(
              message: m,
              mine: m.senderId == _me,
              tight: groupedWithNewer,
              // Status tertulis hanya di pesan terakhir saya, agar tidak bergantung warna centang saja
              showStateLabel: i == latestMine,
              onLongPress: () => _messageActions(m),
              onRetry: () => _retry(m),
            ),
          ],
        );
      },
    );
  }

  Widget _daySeparator(DateTime t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: CC.border)),
            child: Text(dayLabel(t), style: cText(11, color: CC.muted, weight: FontWeight.w600)),
          ),
        ),
      );

  Widget _blockedBar(bool byMe) => Container(
        width: double.infinity,
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: CC.bad, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                byMe ? 'Anda memblokir percakapan ini.' : 'Percakapan ini tidak bisa menerima pesan baru.',
                style: cText(12.5, color: CC.body),
              ),
            ),
            if (byMe)
              TextButton(
                onPressed: _toggleBlock,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('Buka blokir'),
              ),
          ],
        ),
      );

  Widget _composer() {
    final canSend = _input.text.trim().isNotEmpty;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isOwner) _quickReplyBar(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Kirim foto',
                onPressed: _attachMenu,
                icon: const Icon(Icons.add_photo_alternate_outlined, color: CC.muted),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: _onInputChanged,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      currentLength > 1800 ? Text('$currentLength/2000', style: cText(10.5, color: CC.muted)) : null,
                  decoration: InputDecoration(
                    hintText: 'Tulis pesan…',
                    hintStyle: cText(13.5, color: CC.faint),
                    filled: true,
                    fillColor: CC.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton.filled(
                  tooltip: 'Kirim',
                  onPressed: canSend ? _sendText : null,
                  style: IconButton.styleFrom(
                    backgroundColor: CC.brand,
                    disabledBackgroundColor: CC.border,
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _attachMenu() {
    if (kIsWeb) {
      _pickImage(ImageSource.gallery);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto'),
              subtitle: const Text('Misalnya kondisi pakaian atau noda'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Foto dikompres otomatis, maksimal 3 MB.', style: cText(11.5, color: CC.muted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickReplyBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
        children: [
          for (final q in _quickReplies)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(q.body, overflow: TextOverflow.ellipsis),
                ),
                labelStyle: cText(12, color: CC.body, weight: FontWeight.w600),
                backgroundColor: Colors.white,
                side: const BorderSide(color: CC.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                // Isi ke kolom tulis dulu supaya mitra bisa menyesuaikan sebelum mengirim
                onPressed: () {
                  _input.text = q.body;
                  _input.selection = TextSelection.collapsed(offset: q.body.length);
                  _focus.requestFocus();
                  setState(() {});
                },
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.edit_note_rounded, size: 18, color: CC.brand),
            label: const Text('Atur template'),
            labelStyle: cText(12, color: CC.brand, weight: FontWeight.w700),
            backgroundColor: CC.brandSoft,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onPressed: _manageQuickReplies,
          ),
        ],
      ),
    );
  }

  Future<void> _manageQuickReplies() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _QuickReplyManager(),
    );
    _loadQuickReplies();
  }
}

// ======================================================================
// BUBBLE
// ======================================================================

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool tight;
  final bool showStateLabel;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  const _Bubble({
    required this.message,
    required this.mine,
    required this.tight,
    this.showStateLabel = false,
    required this.onLongPress,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    final maxW = MediaQuery.of(context).size.width.clamp(0, 720) * 0.78;
    final bg = mine ? CC.brand : Colors.white;
    final fg = mine ? Colors.white : CC.ink;
    final metaColor = mine ? Colors.white.withValues(alpha: 0.8) : CC.faint;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );

    return Padding(
      padding: EdgeInsets.only(top: tight ? 2 : 8),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW.toDouble()),
              child: GestureDetector(
                onLongPress: onLongPress,
                onTap: m.failed ? onRetry : null,
                child: Container(
                  padding: EdgeInsets.all(m.isImage ? 4 : 10),
                  decoration: BoxDecoration(
                    color: m.failed ? CC.badBg : bg,
                    borderRadius: radius,
                    border: mine ? (m.failed ? Border.all(color: CC.bad) : null) : Border.all(color: CC.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.isImage) _ChatImage(message: m),
                      if (m.body.isNotEmpty)
                        Padding(
                          padding: m.isImage ? const EdgeInsets.fromLTRB(6, 6, 6, 0) : EdgeInsets.zero,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1,
                            child: SelectableText(
                              m.body,
                              style: cText(14, color: m.failed ? CC.ink : fg, weight: FontWeight.w500),
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: m.isImage ? const EdgeInsets.fromLTRB(6, 0, 6, 2) : EdgeInsets.zero,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(jam(m.createdAt), style: cText(10.5, color: m.failed ? CC.bad : metaColor)),
                            if (mine) ...[
                              const SizedBox(width: 4),
                              _StatusIcon(state: m.state),
                              if (showStateLabel && !m.failed) ...[
                                const SizedBox(width: 3),
                                Text(
                                  switch (m.state) {
                                    MessageState.sending => 'Mengirim',
                                    MessageState.sent => 'Terkirim',
                                    MessageState.delivered => 'Diterima',
                                    MessageState.read => 'Dibaca',
                                    MessageState.failed => '',
                                  },
                                  style: cText(10.5, color: metaColor, weight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (m.failed)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Gagal terkirim · Kirim ulang'),
              style: TextButton.styleFrom(foregroundColor: CC.bad, minimumSize: const Size(44, 36)),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageState state;
  const _StatusIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    final white = Colors.white.withValues(alpha: 0.85);
    final (icon, color, label) = switch (state) {
      MessageState.sending => (Icons.schedule_rounded, white, 'Mengirim'),
      MessageState.failed => (Icons.error_outline_rounded, CC.bad, 'Gagal'),
      MessageState.sent => (Icons.check_rounded, white, 'Terkirim'),
      MessageState.delivered => (Icons.done_all_rounded, white, 'Diterima'),
      // Dibaca: biru muda, terbedakan dari putih "diterima" di atas bubble biru
      MessageState.read => (Icons.done_all_rounded, const Color(0xFF7DD3FC), 'Dibaca'),
    };
    return Semantics(label: label, child: Icon(icon, size: 15, color: color));
  }
}

class _ChatImage extends StatelessWidget {
  final ChatMessage message;
  const _ChatImage({required this.message});

  @override
  Widget build(BuildContext context) {
    final m = message;
    const size = 220.0;
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: size, height: size, child: child),
        );

    if (m.localBytes != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          frame(Image.memory(Uint8List.fromList(m.localBytes!), fit: BoxFit.cover)),
          if (m.pending)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      );
    }
    final path = m.imagePath;
    if (path == null) return frame(const ColoredBox(color: CC.bg));
    return FutureBuilder<String?>(
      future: ChatService.instance.imageUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) {
          return frame(ColoredBox(
            color: CC.bg,
            child: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.broken_image_outlined, color: CC.faint),
            ),
          ));
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _ImageViewer(url: url)),
          ),
          child: frame(Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, p) =>
                p == null ? child : const ColoredBox(color: CC.bg, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorBuilder: (_, _, _) => const ColoredBox(color: CC.bg, child: Icon(Icons.broken_image_outlined, color: CC.faint)),
          )),
        );
      },
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String url;
  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: Center(
        child: InteractiveViewer(maxScale: 5, child: Image.network(url)),
      ),
    );
  }
}

// ======================================================================
// KELOLA TEMPLATE BALASAN CEPAT
// ======================================================================

class _QuickReplyManager extends StatefulWidget {
  const _QuickReplyManager();

  @override
  State<_QuickReplyManager> createState() => _QuickReplyManagerState();
}

class _QuickReplyManagerState extends State<_QuickReplyManager> {
  final _service = ChatService.instance;
  List<QuickReply>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.fetchQuickReplies(seedIfEmpty: false);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit([QuickReply? q]) async {
    final ctrl = TextEditingController(text: q?.body ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(q == null ? 'Template baru' : 'Ubah template'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(hintText: 'Contoh: Cucian Anda siap diantar sore ini.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    try {
      await _service.saveQuickReply(id: q?.id, body: text, sortOrder: q?.sortOrder ?? (_items?.length ?? 0));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _delete(QuickReply q) async {
    try {
      await _service.deleteQuickReply(q.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Template balasan cepat',
                        style: GoogleFonts.quicksand(fontSize: 17, fontWeight: FontWeight.w700, color: CC.ink)),
                  ),
                  TextButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah'),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Ketuk template di ruang chat untuk mengisinya ke kolom pesan.', style: cText(12, color: CC.muted)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(_error!, style: cText(12, color: CC.bad)),
              ),
            if (items == null && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (items != null && items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Belum ada template. Tekan Tambah untuk membuat.', style: cText(12.5, color: CC.muted)),
              )
            else if (items != null)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: CC.border),
                  itemBuilder: (_, i) {
                    final q = items[i];
                    return ListTile(
                      title: Text(q.body, style: cText(13.5, color: CC.ink)),
                      onTap: () => _edit(q),
                      trailing: IconButton(
                        tooltip: 'Hapus template',
                        icon: const Icon(Icons.delete_outline_rounded, color: CC.bad),
                        onPressed: () => _delete(q),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
