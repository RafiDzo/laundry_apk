import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Foto & logo outlet.
///
/// Foto: kalau outlet belum punya foto, atau fotonya hasil generator AI
/// (URL `aida-public`), dipakai foto laundromat asli dari Unsplash
/// (lisensi Unsplash, bebas dipakai). Pilihan foto tetap per outlet.
class ShopBranding {
  ShopBranding._();

  static const List<String> _photoIds = [
    '1577553698923-17f1a80ce5bc', // deretan mesin cuci front-load
    '1604335398980-ededcadcc37d', // lorong laundromat biru
    '1635274605638-d44babc08a4f', // tumpukan baju terlipat
    '1550025005-05b9002486c5', // mesin cuci & pengering susun
    '1521656693074-0ef32e80a5d5', // laundromat dengan troli
    '1776356829215-37929a717f0d', // laundromat terang
    '1638949493140-edb10b7be2f3', // ruang laundry
    '1765176938654-ac6f04c1d86b', // deretan mesin cuci
  ];

  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static bool _isUsable(String url) =>
      url.trim().isNotEmpty && !url.contains('aida-public');

  /// URL foto yang ditampilkan untuk outlet.
  static String photoUrl({
    required String id,
    required String name,
    required String imageUrl,
    int width = 500,
  }) {
    if (_isUsable(imageUrl)) return imageUrl;
    final pick = _photoIds[_hash(id.isNotEmpty ? id : name) % _photoIds.length];
    return 'https://images.unsplash.com/photo-$pick?w=$width&auto=format&fit=crop&q=80';
  }

  /// Semua outlet pakai palet biru Washora yang konsisten.
  /// Variasi tipis pada shade agar tiap kartu masih terasa unik
  /// tapi tetap harmonis dan tidak mencolok.
  static const List<List<Color>> palettes = [
    [Color(0xFF0077E6), Color(0xFF005BB5)], // biru utama Washora
    [Color(0xFF0284C7), Color(0xFF0369A1)], // biru langit
    [Color(0xFF0EA5E9), Color(0xFF0284C7)], // biru cerah
    [Color(0xFF1D4ED8), Color(0xFF1E40AF)], // biru tua
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // biru medium
    [Color(0xFF60A5FA), Color(0xFF2563EB)], // biru muda
    [Color(0xFF0369A1), Color(0xFF075985)], // biru baja
  ];

  static List<Color> paletteFor(String name) {
    final n = name.toLowerCase();
    return palettes[_hash(n) % palettes.length];
  }

  static String initials(String name) {
    const skip = {'laundry', 'laundromat', 'the', 'dan', '&'};
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
        .toList();
    final src = words.isNotEmpty ? words : name.split(RegExp(r'\s+'));
    final letters = src.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return letters.isEmpty ? 'L' : letters;
  }
}

/// Logo outlet: kotak biru bertema Washora dengan inisial nama outlet.
/// Desain bersih, konsisten, dan tidak mencolok.
class ShopLogo extends StatelessWidget {
  final String name;
  final double size;

  const ShopLogo({super.key, required this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colors = ShopBranding.paletteFor(name);
    final s = size;
    final radius = BorderRadius.circular(s * 0.26);
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.first,
            colors.last,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.22),
            blurRadius: s * 0.20,
            offset: Offset(0, s * 0.07),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Lingkaran dekoratif halus di pojok kanan bawah
            Positioned(
              right: -s * 0.08,
              bottom: -s * 0.08,
              child: Container(
                width: s * 0.55,
                height: s * 0.55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            // Inisial nama outlet di tengah
            Center(
              child: Text(
                ShopBranding.initials(name),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: s * 0.30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
