import 'package:flutter/material.dart';

/// Logo resmi Washora (kaos + garis putaran).
///
/// Tanpa [color], logo memakai gradien biru aplikasi. Isi [color]
/// (mis. `Colors.white`) untuk menampilkannya di atas latar biru.
class WashoraLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const WashoraLogo({super.key, this.size = 24, this.color});

  static const String assetPath = 'assets/images/washora_logo.png';

  /// Gradien biru bawaan, selaras dengan warna utama aplikasi.
  static const List<Color> brandGradient = [Color(0xFF38BDF8), Color(0xFF0077E6)];

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      color: color,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
