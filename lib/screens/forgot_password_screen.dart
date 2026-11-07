import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/quick_snackbar.dart';
import 'login_screen.dart';

const _kPrimary = Color(0xFF00B4D8);
const _kBrand = Color(0xFF0077B6);
const _kInk = Color(0xFF2B2D42);
const _kBg = Color(0xFFF8F9FA);

enum _Step { email, code, newPassword, done }

/// Alur lupa password:
/// 1. Masukkan email → kirim email reset
/// 2. Masukkan kode 6 digit dari email (atau klik link di email, untuk web)
/// 3. Buat password baru
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  /// true = pengguna datang dari link reset di email (sesi pemulihan sudah aktif)
  final bool fromRecoveryLink;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.fromRecoveryLink = false,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  late _Step _step = widget.fromRecoveryLink ? _Step.newPassword : _Step.email;
  bool _busy = false;
  bool _obscure = true;
  int _cooldown = 0;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFDC2626),
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      ),
    );
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown--);
      return _cooldown > 0;
    });
  }

  Future<void> _sendEmail() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _error('Masukkan email yang valid');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _error(e.toString());
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      _error('Kode terdiri dari 6 digit');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.verifyRecoveryCode(email: _email.text.trim(), code: code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.newPassword;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _error(e.toString());
    }
  }

  Future<void> _savePassword() async {
    if (_pass.text.length < 6) {
      _error('Password minimal 6 karakter');
      return;
    }
    if (_pass.text != _pass2.text) {
      _error('Konfirmasi password tidak sama');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _auth.updatePassword(_pass.text);
      // Keluar dari sesi pemulihan, pengguna login ulang dengan password baru
      await _auth.signOut();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _kInk,
        leading: _step == _Step.done
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () {
                  if (_step == _Step.code) {
                    setState(() => _step = _Step.email);
                  } else {
                    Navigator.maybePop(context);
                  }
                },
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.email:
        return _layout(
          icon: Icons.lock_reset_rounded,
          title: 'Lupa Password?',
          subtitle:
              'Tenang, masukkan email akunmu. Kami kirimkan kode untuk membuat password baru.',
          children: [
            _field(
              _email,
              'Email',
              Icons.mail_outline_rounded,
              keyboard: TextInputType.emailAddress,
              onSubmit: _sendEmail,
            ),
            const SizedBox(height: 20),
            _button('Kirim Kode Reset', _sendEmail),
          ],
        );
      case _Step.code:
        return _layout(
          icon: Icons.mark_email_unread_rounded,
          title: 'Cek Email Kamu',
          subtitle:
              'Kami sudah mengirim email ke ${_email.text.trim()}. Masukkan kode 6 digit di email tersebut, '
              'atau klik link "Reset Password" di email.',
          children: [
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _verifyCode(),
              style: GoogleFonts.robotoMono(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
                color: _kInk,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: GoogleFonts.robotoMono(
                  fontSize: 28,
                  letterSpacing: 12,
                  color: _kInk.withValues(alpha: 0.2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kPrimary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _button('Verifikasi Kode', _verifyCode),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _cooldown > 0 || _busy ? null : _sendEmail,
                child: Text(
                  _cooldown > 0
                      ? 'Kirim ulang kode dalam ${_cooldown}s'
                      : 'Tidak menerima email? Kirim ulang',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Text(
              'Periksa juga folder Spam / Promosi.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _kInk.withValues(alpha: 0.5),
              ),
            ),
          ],
        );
      case _Step.newPassword:
        return _layout(
          icon: Icons.password_rounded,
          title: 'Buat Password Baru',
          subtitle:
              'Gunakan minimal 6 karakter. Kombinasi huruf & angka lebih aman.',
          children: [
            _field(
              _pass,
              'Password baru',
              Icons.lock_outline_rounded,
              obscure: true,
            ),
            const SizedBox(height: 12),
            _field(
              _pass2,
              'Ulangi password baru',
              Icons.lock_outline_rounded,
              obscure: true,
              onSubmit: _savePassword,
            ),
            const SizedBox(height: 20),
            _button('Simpan Password', _savePassword),
          ],
        );
      case _Step.done:
        return _layout(
          icon: Icons.verified_rounded,
          iconColor: const Color(0xFF16A34A),
          title: 'Password Berhasil Diubah!',
          subtitle: 'Silakan masuk kembali menggunakan password barumu.',
          children: [
            _button('Kembali ke Login', () {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop();
              } else {
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            }),
          ],
        );
    }
  }

  Widget _layout({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Color iconColor = _kBrand,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Icon(icon, size: 40, color: iconColor),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.quicksand(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            height: 1.5,
            color: _kInk.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 28),
        ...children,
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure && _obscure,
      keyboardType: keyboard,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: GoogleFonts.inter(fontSize: 15, color: _kInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: _kInk.withValues(alpha: 0.4)),
        prefixIcon: Icon(icon, color: _kInk.withValues(alpha: 0.5)),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _kInk.withValues(alpha: 0.5),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kPrimary, width: 2),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: _busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kPrimary.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
