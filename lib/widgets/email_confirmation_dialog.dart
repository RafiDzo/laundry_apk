import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

/// Dialog "cek email kamu" dengan tombol kirim ulang email konfirmasi.
/// [justSignedUp] = true saat dipanggil tepat setelah pendaftaran,
/// false saat login ditolak karena email belum dikonfirmasi.
Future<void> showEmailConfirmationDialog(
  BuildContext context, {
  required String email,
  bool justSignedUp = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmailConfirmationDialog(email: email, justSignedUp: justSignedUp),
  );
}

class _EmailConfirmationDialog extends StatefulWidget {
  final String email;
  final bool justSignedUp;

  const _EmailConfirmationDialog({required this.email, required this.justSignedUp});

  @override
  State<_EmailConfirmationDialog> createState() => _EmailConfirmationDialogState();
}

class _EmailConfirmationDialogState extends State<_EmailConfirmationDialog> {
  // Supabase membatasi kirim ulang email ±1x per 60 detik
  static const int _cooldownSeconds = 60;

  final AuthService _authService = AuthService();
  bool _isSending = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _message;
  bool _messageIsError = false;

  final brandDark = const Color(0xFF0077B6);
  final darkNavy = const Color(0xFF2B2D42);

  @override
  void initState() {
    super.initState();
    // Email baru saja dikirim saat sign up, jadi langsung mulai jeda
    if (widget.justSignedUp) _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _isSending = true;
      _message = null;
    });
    try {
      await _authService.resendConfirmationEmail(widget.email);
      if (!mounted) return;
      setState(() {
        _message = 'Email konfirmasi terkirim. Cek inbox & folder spam.';
        _messageIsError = false;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_isSending && _cooldown <= 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: brandDark.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mark_email_unread_rounded, color: brandDark, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            widget.justSignedUp ? 'Cek Email Kamu' : 'Email Belum Dikonfirmasi',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: darkNavy),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.5),
              children: [
                TextSpan(
                  text: widget.justSignedUp
                      ? 'Pendaftaran berhasil! Kami sudah mengirim link konfirmasi ke '
                      : 'Akun ini belum bisa login karena email belum dikonfirmasi. Klik link yang kami kirim ke ',
                ),
                TextSpan(
                  text: widget.email,
                  style: TextStyle(fontWeight: FontWeight.w700, color: darkNavy),
                ),
                const TextSpan(text: ', lalu kembali ke sini untuk login.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Tidak menemukan emailnya? Cek folder Spam / Promosi.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _messageIsError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _messageIsError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandDark,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: canResend ? _resend : null,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              label: Text(
                _cooldown > 0 ? 'Kirim ulang dalam ${_cooldown}s' : 'Kirim Ulang Email Konfirmasi',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            widget.justSignedUp ? 'Ke Halaman Login' : 'Tutup',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: brandDark),
          ),
        ),
      ],
    );
  }
}
