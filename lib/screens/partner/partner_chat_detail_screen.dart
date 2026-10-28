import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _blue = Color(0xFF0077E6);
const Color _surface = Color(0xFFF8FAFC);
const Color _textDark = Color(0xFF0F172A);
const Color _textMid = Color(0xFF334155);
const Color _textLight = Color(0xFF64748B);
const Color _textHint = Color(0xFF94A3B8);
const Color _border = Color(0xFFE2E8F0);
const Color _success = Color(0xFF10B981);
const Color _danger = Color(0xFFEF4444);

class PartnerChatDetailScreen extends StatefulWidget {
  final String customerName;
  final String avatarLetter;
  final Color avatarColor;

  const PartnerChatDetailScreen({
    super.key,
    required this.customerName,
    required this.avatarLetter,
    required this.avatarColor,
  });

  @override
  State<PartnerChatDetailScreen> createState() =>
      _PartnerChatDetailScreenState();
}

class _PartnerChatDetailScreenState extends State<PartnerChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showOrderCard = true;

  final List<Map<String, dynamic>> _messages = [
    {
      'text': 'Halo, apakah pesanan saya sudah diproses?',
      'isMe': false,
      'time': '10:42',
    },
    {
      'text':
          'Halo Pak Rafi! Pesanan Anda sedang dalam pengerjaan. Kami ingin memastikan estimasi waktunya.',
      'isMe': true,
      'time': '10:43',
    },
    {
      'text': 'Oke, berapa lama kira-kira?',
      'isMe': false,
      'time': '10:44',
    },
    {
      'text': 'Estimasi 2-3 jam lagi ya Pak. Kami prioritaskan pesanan Bapak.',
      'isMe': true,
      'time': '10:45',
    },
  ];

  String _getTime() {
    final now = TimeOfDay.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'text': text, 'isMe': true, 'time': _getTime()});
        _messageController.clear();
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _sendQuickMessage(String text) {
    setState(() {
      _messages.add({'text': text, 'isMe': true, 'time': _getTime()});
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildPendingOrderCard() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_laundry_service_rounded,
              color: _blue, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PESANAN AKTIF',
                  style: GoogleFonts.plusJakartaSans(
                    color: _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Cuci Lipat \u2022 5kg',
                  style: GoogleFonts.plusJakartaSans(
                    color: _textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '#ORD-8823 \u2022 Menunggu konfirmasi',
                  style: GoogleFonts.plusJakartaSans(
                    color: _textLight,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() => _showOrderCard = false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _danger,
                  side: const BorderSide(color: _danger),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Tolak'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  setState(() => _showOrderCard = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 0,
                ),
                child: const Text('Terima'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? _blue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg['text'] as String,
              style: GoogleFonts.plusJakartaSans(
                color: isMe ? Colors.white : _textDark,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg['time'] as String,
              style: GoogleFonts.plusJakartaSans(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.7)
                    : _textHint,
                fontSize: 10,
              ),
              textAlign: isMe ? TextAlign.right : TextAlign.left,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionBtn(String label, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () => _sendQuickMessage(label),
      icon: Icon(icon, size: 14, color: _textMid),
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: _textMid,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _textMid,
        side: const BorderSide(color: _border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _quickActionBtn('Toko Baru', Icons.store_rounded),
          _quickActionBtn('Pembayaran Siap', Icons.payment_rounded),
          _quickActionBtn('Minta Tunggu', Icons.hourglass_top_rounded),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _border),
              ),
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 4,
                style: GoogleFonts.plusJakartaSans(
                  color: _textDark,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Tulis pesan...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: _textHint,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _sendMessage,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.avatarColor,
              child: Text(
                widget.avatarLetter,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customerName,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Online',
                  style: GoogleFonts.plusJakartaSans(
                    color: _success,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: _textMid),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: _textMid),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _border, height: 1),
        ),
      ),
      body: Column(
        children: [
          if (_showOrderCard) _buildPendingOrderCard(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          _buildQuickActions(),
          _buildInputBar(),
        ],
      ),
    );
  }
}
