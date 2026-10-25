import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'supabase_service.dart';

class AuthService {
  final SupabaseClient _auth = Supabase.instance.client;
  final SupabaseService _supabaseService = SupabaseService();

  /// Stream untuk memantau status login
  Stream<AuthState> get authStateChanges => _auth.auth.onAuthStateChange;

  /// Dapatkan user yang sedang login
  User? get currentUser => _auth.auth.currentUser;

  // ================= EMAIL / PASSWORD =================

  /// Sign up dengan email dan password
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    String role = 'customer',
  }) async {
    try {
      final response = await _auth.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'role': role},
      );

      // Hanya buat profile secara manual jika session aktif (user terautentikasi).
      // Jika email confirmation ON di Supabase, session bernilai null (anon),
      // sehingga tidak boleh dipanggil dari client (akan error RLS).
      // Profile akan dibuat oleh database trigger atau otomatis saat login pertama kali.
      if (response.session != null && response.user != null) {
        try {
          await _supabaseService.createUser(
            uid: response.user!.id,
            name: name,
            email: email,
            role: role,
          );
        } catch (e) {
          // Abaikan jika trigger DB sudah membuatnya lebih dulu
          print('createUser notice: $e');
        }
      }
    } on AuthException catch (e) {
      throw _getCustomErrorMessage(e.message);
    } catch (e) {
      throw 'Terjadi kesalahan sistem: ${e.toString()}';
    }
  }

  /// Sign in dengan email dan password
  Future<void> signIn({
    required String email,
    required String password,
    required String expectedRole,
  }) async {
    try {
      final response = await _auth.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        var profile = await _supabaseService.getUserProfile(
          response.user!.id,
        );

        // Jika profil belum ada di public.users, buat sekarang karena user sudah terotentikasi
        if (profile == null) {
          final meta = response.user!.userMetadata;
          final name = (meta?['name'] as String?)?.isNotEmpty == true
              ? meta!['name'] as String
              : (response.user!.email?.split('@').first ?? 'Pengguna');
          final role = (meta?['role'] as String?)?.isNotEmpty == true
              ? meta!['role'] as String
              : expectedRole;

          try {
            await _supabaseService.createUser(
              uid: response.user!.id,
              name: name,
              email: response.user!.email ?? '',
              role: role,
            );
            profile = await _supabaseService.getUserProfile(response.user!.id);
          } catch (e) {
            print('Auto-create profile error on signIn: $e');
          }
        }

        if (profile != null && profile.role != expectedRole) {
          await _auth.auth.signOut();
          final roleText = profile.role == 'owner'
              ? 'Mitra Laundry'
              : 'Pengguna Biasa';
          final expectedText = expectedRole == 'owner'
              ? 'Mitra Laundry'
              : 'Pengguna Biasa';
          throw 'Akun ini terdaftar sebagai $roleText.\nTidak bisa masuk sebagai $expectedText.';
        }
      }
    } on AuthException catch (e) {
      throw _getCustomErrorMessage(e.message);
    } catch (e) {
      if (e is String) rethrow;
      throw 'Terjadi kesalahan sistem.';
    }
  }

  // ================= GOOGLE OAUTH =================

  /// Sign in dengan Google
  Future<void> signInWithGoogle({String defaultRole = 'customer'}) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: SupabaseConfig.googleServerClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) throw 'Login Google dibatalkan.';

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) throw 'Token Google tidak valid.';

      final response = await _auth.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (response.user != null) {
        // Cek apakah sudah ada profil, kalau belum buat baru
        final existing = await _supabaseService.getUserProfile(
          response.user!.id,
        );
        if (existing == null) {
          await _supabaseService.createUser(
            uid: response.user!.id,
            name: googleUser.displayName ?? googleUser.email,
            email: googleUser.email,
            role: defaultRole,
          );
        }
      }
    } on AuthException catch (e) {
      throw _getCustomErrorMessage(e.message);
    } catch (e) {
      if (e is String) rethrow;
      throw 'Terjadi kesalahan Google Sign-In.';
    }
  }

  // ================= PASSWORD UPDATE =================

  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw _getCustomErrorMessage(e.message);
    } catch (e) {
      throw 'Gagal memperbarui kata sandi: $e';
    }
  }

  /// Ubah kata sandi dengan verifikasi kata sandi lama terlebih dahulu
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final email = _auth.auth.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      try {
        await _auth.auth.signInWithPassword(
          email: email,
          password: oldPassword,
        );
      } on AuthException {
        throw 'Kata sandi lama yang Anda masukkan tidak sesuai.';
      } catch (e) {
        throw 'Gagal memverifikasi kata sandi lama: $e';
      }
    }
    await updatePassword(newPassword);
  }

  // ================= SIGN OUT =================

  Future<void> signOut() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    await _auth.auth.signOut();
  }

  // ================= HELPER =================

  String _getCustomErrorMessage(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Email atau password salah.';
    } else if (msg.contains('email not confirmed') ||
        msg.contains('email_not_confirmed')) {
      return 'Email belum dikonfirmasi. Cek inbox email kamu, atau hubungi admin untuk menonaktifkan konfirmasi email.';
    } else if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'Email sudah terdaftar. Silakan login.';
    } else if (msg.contains('email rate limit') || msg.contains('rate limit')) {
      return 'Batas kirim email Supabase tercapai. Matikan "Confirm email" di Dashboard Supabase agar bisa daftar langsung tanpa email.';
    } else if (msg.contains('invalid email')) {
      return 'Format email tidak valid.';
    } else if (msg.contains('password')) {
      return 'Password terlalu lemah, gunakan minimal 6 karakter.';
    } else if (msg.contains('network') || msg.contains('connection')) {
      return 'Periksa koneksi internet Anda.';
    }
    return 'Terjadi kesalahan: $message';
  }
}
