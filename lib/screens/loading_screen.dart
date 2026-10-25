import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'role_selection_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final List<AnimationController> _bubbleControllers;
  late final List<Animation<double>> _bubbleScaleAnimations;
  late final List<Animation<double>> _bubbleOpacityAnimations;

  @override
  void initState() {
    super.initState();
    _bubbleControllers = List.generate(4, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      );
    });

    _bubbleScaleAnimations = _bubbleControllers.map((controller) {
      return Tween<double>(
        begin: 0.8,
        end: 1.2,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    _bubbleOpacityAnimations = _bubbleControllers.map((controller) {
      return Tween<double>(
        begin: 0.3,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    // Start bubble animations with staggered delays
    for (int i = 0; i < _bubbleControllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (mounted) {
          _bubbleControllers[i].repeat(reverse: true);
        }
      });
    }

    // Navigate to next screen after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const RoleSelectionScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _bubbleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF00B4D8);
    // Force light mode (white) background
    final bgColor = const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // The background ambient blur
          // <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-80 h-80 bg-[#00B4D8] opacity-5 blur-[100px] rounded-full pointer-events-none"></div>
          Positioned.fill(
            child: Center(
              child: Container(
                width: 320, // w-80
                height: 320, // h-80
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.05),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.05),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main vertical container
          // <div class="relative z-10 h-full flex flex-col items-center justify-center px-10 pb-20">
          SafeArea(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 40, right: 40, bottom: 80),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Orb container
                  // <div class="relative mb-12">
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48), // mb-12
                    child: _buildGlowOrb(primaryColor, bgColor),
                  ),

                  // Text container
                  // <div class="text-center mb-20">
                  Padding(
                    padding: const EdgeInsets.only(bottom: 80), // mb-20
                    child: Column(
                      children: [
                        // <h1 class="text-4xl font-brand font-bold tracking-wide text-primary mb-3 text-glow">
                        Text(
                          'WASHORA',
                          style: GoogleFonts.quicksand(
                            fontSize: 36, // text-4xl
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.9, // tracking-wide
                            color: primaryColor,
                            shadows: [
                              Shadow(
                                // text-glow
                                color: primaryColor.withValues(alpha: 0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12), // mb-3
                        // <p class="text-slate-600 dark:text-slate-300 text-center text-sm font-medium leading-relaxed font-brand">
                        Text(
                          'Bersih & Wangi Sekali Sentuh',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.quicksand(
                            fontSize: 14, // text-sm
                            fontWeight: FontWeight.w500, // font-medium
                            height: 1.625, // leading-relaxed
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Loading Indicators Container
                  // <div class="w-full relative px-2 flex flex-col items-center justify-center gap-4">
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8), // px-2
                    child: Column(
                      children: [
                        // <div class="flex items-center gap-4 h-8">
                        SizedBox(
                          height: 32, // h-8
                          child: _buildBubbleLoading(primaryColor),
                        ),
                        const SizedBox(height: 16), // gap-4 equivalent
                        // <div class="text-primary/80 dark:text-primary text-xs font-semibold tracking-wider uppercase mt-2">
                        Padding(
                          padding: const EdgeInsets.only(top: 8), // mt-2
                          child: Text(
                            'MEMUAT...',
                            style: GoogleFonts.inter(
                              fontSize: 12, // text-xs
                              fontWeight: FontWeight.w600, // font-semibold
                              letterSpacing: 0.6, // tracking-wider
                              color: primaryColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOrb(Color primaryColor, Color bgColor) {
    return Container(
      width: 176, // w-44
      height: 176, // h-44
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // glowing orb radial gradient & tailwind borders
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          // shadow
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.1),
            blurRadius: 40,
            spreadRadius: 10,
          ),
          // inset shadow
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: 0,
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      // To properly render backdrop blur, clip it and nest BackdropFilter
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 4.0,
            sigmaY: 4.0,
          ), // backdrop-blur-sm
          child: Container(
            decoration: BoxDecoration(
              // radial gradient as requested in HTML glow-orb class
              gradient: RadialGradient(
                colors: [primaryColor.withValues(alpha: 0.1), bgColor],
                stops: const [0.0, 0.7],
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(0, 4), // translate-y-1 = 4px down
                child: CustomPaint(
                  size: const Size(128, 128), // w-32 h-32
                  painter: _LaundryIconPainter(color: primaryColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleLoading(Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        return AnimatedBuilder(
          animation: _bubbleControllers[index],
          builder: (context, child) {
            return Container(
              margin: EdgeInsets.only(
                right: index < 3 ? 16 : 0,
              ), // gap-4 (16px) spacing
              child: Transform.scale(
                scale: _bubbleScaleAnimations[index].value,
                child: Opacity(
                  opacity: _bubbleOpacityAnimations[index].value,
                  child: Container(
                    width: 16, // w-4
                    height: 16, // h-4
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _LaundryIconPainter extends CustomPainter {
  final Color color;

  _LaundryIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // SVG viewBox="0 0 100 100" -> scale by size.width / 100
    final scale = size.width / 100;

    // --- Main shirt/clothing shape ---
    final shirtPath = Path();
    shirtPath.moveTo(25 * scale, 32 * scale);
    shirtPath.lineTo(35 * scale, 28 * scale);
    shirtPath.lineTo(50 * scale, 33 * scale);
    shirtPath.lineTo(65 * scale, 28 * scale);
    shirtPath.lineTo(75 * scale, 32 * scale);
    shirtPath.lineTo(70 * scale, 42 * scale);
    shirtPath.lineTo(63 * scale, 38 * scale);
    shirtPath.lineTo(65 * scale, 55 * scale);
    shirtPath.cubicTo(
      65 * scale,
      55 * scale,
      68 * scale,
      62 * scale,
      60 * scale,
      62 * scale,
    );
    shirtPath.lineTo(40 * scale, 62 * scale);
    shirtPath.cubicTo(
      32 * scale,
      62 * scale,
      35 * scale,
      55 * scale,
      35 * scale,
      55 * scale,
    );
    shirtPath.lineTo(37 * scale, 38 * scale);
    shirtPath.lineTo(30 * scale, 42 * scale);
    shirtPath.close();
    canvas.drawPath(shirtPath, paint);

    // --- Sparkle star at top right ---
    final sparklePath = Path();
    sparklePath.moveTo(58 * scale, 35 * scale);
    sparklePath.lineTo(60 * scale, 31 * scale);
    sparklePath.lineTo(62 * scale, 35 * scale);
    sparklePath.lineTo(66 * scale, 37 * scale);
    sparklePath.lineTo(62 * scale, 39 * scale);
    sparklePath.lineTo(60 * scale, 43 * scale);
    sparklePath.lineTo(58 * scale, 39 * scale);
    sparklePath.lineTo(54 * scale, 37 * scale);
    sparklePath.close();
    canvas.drawPath(sparklePath, paint);

    // --- Smile curve (bottom arc) ---
    final smilePath = Path();
    smilePath.moveTo(22 * scale, 65 * scale);
    smilePath.cubicTo(
      22 * scale,
      65 * scale,
      30 * scale,
      78 * scale,
      50 * scale,
      78 * scale,
    );
    smilePath.cubicTo(
      70 * scale,
      78 * scale,
      78 * scale,
      65 * scale,
      78 * scale,
      65 * scale,
    );
    smilePath.lineTo(76 * scale, 68 * scale);
    smilePath.cubicTo(
      76 * scale,
      68 * scale,
      68 * scale,
      82 * scale,
      50 * scale,
      82 * scale,
    );
    smilePath.cubicTo(
      32 * scale,
      82 * scale,
      24 * scale,
      68 * scale,
      24 * scale,
      68 * scale,
    );
    smilePath.close();
    canvas.drawPath(smilePath, paint);

    // --- Wave/swoosh line ---
    final swooshPath = Path();
    swooshPath.moveTo(30 * scale, 60 * scale);
    swooshPath.cubicTo(
      30 * scale,
      60 * scale,
      40 * scale,
      70 * scale,
      65 * scale,
      65 * scale,
    );
    swooshPath.lineTo(63 * scale, 68 * scale);
    swooshPath.cubicTo(
      63 * scale,
      68 * scale,
      40 * scale,
      75 * scale,
      32 * scale,
      63 * scale,
    );
    swooshPath.close();
    canvas.drawPath(swooshPath, paint);

    // --- Bubbles ---
    canvas.drawCircle(Offset(25 * scale, 55 * scale), 3 * scale, paint);
    canvas.drawCircle(Offset(28 * scale, 48 * scale), 2 * scale, paint);
    canvas.drawCircle(Offset(75 * scale, 52 * scale), 4 * scale, paint);
    canvas.drawCircle(Offset(72 * scale, 45 * scale), 2.5 * scale, paint);
    canvas.drawCircle(Offset(35 * scale, 72 * scale), 2 * scale, paint);
    canvas.drawCircle(Offset(65 * scale, 70 * scale), 1.5 * scale, paint);

    // --- Small sparkle stars ---
    _drawSparkle(canvas, paint, scale, 20, 55, 0.7);
    _drawSparkle(canvas, paint, scale, 74, 40, 0.8);
  }

  void _drawSparkle(
    Canvas canvas,
    Paint paint,
    double scale,
    double cx,
    double cy,
    double sparkleScale,
  ) {
    final path = Path();
    final s = sparkleScale;
    path.moveTo(
      (cx - 2) * scale * s + (1 - s) * cx * scale,
      (cy - 1) * scale * s + (1 - s) * cy * scale,
    );
    path.lineTo(cx * scale, (cy - 3) * scale * s + (1 - s) * cy * scale);
    path.lineTo(
      (cx + 2) * scale * s + (1 - s) * cx * scale,
      (cy - 1) * scale * s + (1 - s) * cy * scale,
    );
    path.lineTo((cx + 3) * scale * s + (1 - s) * cx * scale, cy * scale);
    path.lineTo(
      (cx + 2) * scale * s + (1 - s) * cx * scale,
      (cy + 1) * scale * s + (1 - s) * cy * scale,
    );
    path.lineTo(cx * scale, (cy + 3) * scale * s + (1 - s) * cy * scale);
    path.lineTo(
      (cx - 2) * scale * s + (1 - s) * cx * scale,
      (cy + 1) * scale * s + (1 - s) * cy * scale,
    );
    path.lineTo((cx - 3) * scale * s + (1 - s) * cx * scale, cy * scale);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
