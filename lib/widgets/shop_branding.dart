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

  static const List<List<Color>> palettes = [
    [Color(0xFF0EA5E9), Color(0xFF0369A1)], // biru laut
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // lavender
    [Color(0xFF14B8A6), Color(0xFF0F766E)], // tosca
    [Color(0xFFF59E0B), Color(0xFFEA580C)], // oranye
    [Color(0xFFEC4899), Color(0xFFBE185D)], // pink
    [Color(0xFF22C55E), Color(0xFF15803D)], // hijau
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // biru
  ];

  static List<Color> paletteFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('lavender') || n.contains('ungu')) return palettes[1];
    if (n.contains('eco') || n.contains('green') || n.contains('hijau')) return palettes[5];
    if (n.contains('express') || n.contains('kilat') || n.contains('quick')) return palettes[3];
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

/// Logo outlet: kotak gradien dengan "pintu mesin cuci" berisi inisial
/// outlet dan gelembung busa. Dibuat otomatis dari nama outlet.
class ShopLogo extends StatelessWidget {
  final String name;
  final double size;

  const ShopLogo({super.key, required this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colors = ShopBranding.paletteFor(name);
    final s = size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.30),
            blurRadius: s * 0.18,
            offset: Offset(0, s * 0.06),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s * 0.28),
        child: Stack(
          children: [
            // Gelembung busa dekoratif
            _bubble(left: s * 0.08, top: s * 0.10, d: s * 0.14, a: 0.35),
            _bubble(left: s * 0.20, top: s * 0.04, d: s * 0.07, a: 0.30),
            _bubble(right: -s * 0.10, bottom: -s * 0.12, d: s * 0.45, a: 0.12),
            _bubble(right: s * 0.10, top: s * 0.12, d: s * 0.08, a: 0.40),
            // Pintu mesin cuci berisi inisial
            Center(
              child: Container(
                width: s * 0.58,
                height: s * 0.58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: s * 0.05,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  ShopBranding.initials(name),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: s * 0.22,
                    fontWeight: FontWeight.w800,
                    color: colors.last,
                    letterSpacing: -0.5,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble({double? left, double? top, double? right, double? bottom, required double d, required double a}) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: a),
        ),
      ),
    );
  }
}
