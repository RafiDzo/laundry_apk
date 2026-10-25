/// Konfigurasi Supabase
/// TODO: Isi nilai di bawah ini dengan data dari Supabase Dashboard → Settings → API
class SupabaseConfig {
  static const String url = 'https://kyggdszeuinfldjvfkqa.supabase.co';
  static const String anonKey =
      'sb_publishable_ujkYnRBZ8BQ5F0WsgToBvw_XA5X5RwR';

  /// Client ID Google OAuth
  /// Dapatkan dari: Google Cloud Console → Credentials → OAuth 2.0 Client IDs
  /// Pilih tipe "Android" dan gunakan SHA-1 dari debug keystore
  static const String googleClientId =
      '194015664069-9g9ou1r009hgio1deosvon71ebtodddr.apps.googleusercontent.com';
  static const String googleServerClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
}
