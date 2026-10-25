import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'location_screen.dart';
import 'home_screen.dart';
import 'owner_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, this.role = 'customer'});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Colors based on Tailwind config
  final primaryColor = const Color(0xFF00B4D8);
  final secondaryColor = const Color(0xFF90E0EF);
  final boneWhite = const Color(0xFFF8F9FA);
  final darkNavy = const Color(0xFF2B2D42);
  final brandDark = const Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    if (savedEmail != null && savedPassword != null) {
      if (mounted) {
        setState(() {
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _rememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Email dan password harus diisi!',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        expectedRole: widget.role,
      );

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_email', _emailController.text.trim());
        await prefs.setString(
          'saved_password',
          _passwordController.text.trim(),
        );
      } else {
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
      }

      if (!mounted) return;

      if (widget.role == 'owner') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const OwnerDashboardScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString(), style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: boneWhite,
      body: Stack(
        children: [
          // bg-shape-1
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          // bg-shape-2
          Positioned(
            bottom: -50,
            left: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const SizedBox(height: 48), // mt-12
                        // Logo & Branding
                        Column(
                          children: [
                            // Logo Box
                            Container(
                              width: 96, // w-24
                              height: 96, // h-24
                              margin: const EdgeInsets.only(bottom: 16), // mb-4
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.1),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(
                                      alpha: 0.2,
                                    ), // shadow-glow
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: CustomPaint(
                                  size: const Size(56, 56), // w-14 h-14
                                  painter: _LaundryLogoPainter(
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              'WASHORA',
                              style: GoogleFonts.quicksand(
                                fontSize: 30, // text-3xl
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                letterSpacing: 0.9,
                              ),
                            ),
                            const SizedBox(height: 4), // mt-1
                            Text(
                              'Welcome back!',
                              style: GoogleFonts.inter(
                                fontSize: 14, // text-sm
                                fontWeight: FontWeight.w500,
                                color: darkNavy.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 40), // mb-10 equivalent
                        // Input fields
                        _buildInputField(
                          controller: _emailController,
                          icon: Icons.mail_outline,
                          hintText: 'Email address',
                          keyboardType: TextInputType.emailAddress,
                        ),

                        const SizedBox(height: 20),

                        _buildPasswordField(),

                        const SizedBox(height: 12),

                        // Forgot Password & Remember Me
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(
                                      () => _rememberMe = v ?? false,
                                    ),
                                    activeColor: primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    side: BorderSide(
                                      color: darkNavy.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Remember me',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: darkNavy.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {},
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Login Button
                        _buildLoginButton(),

                        const SizedBox(height: 16),

                        // Divider
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: darkNavy.withValues(alpha: 0.1),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'or',
                                style: GoogleFonts.inter(
                                  color: darkNavy.withValues(alpha: 0.4),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: darkNavy.withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Google Sign In
                        _buildGoogleSignInButton(),

                        const Expanded(child: SizedBox(height: 32)),

                        // Sign up link
                        Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: darkNavy.withValues(alpha: 0.6),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SignUpScreen(role: widget.role),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Sign Up',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom Line
                        Container(
                          width: 128,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0), // bg-slate-200
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(color: const Color(0xFFF1F5F9)), // slate-100
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), // shadow-input
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(color: darkNavy, fontSize: 15),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            color: darkNavy.withValues(alpha: 0.3),
            fontSize: 15,
          ),
          prefixIcon: Icon(
            icon,
            color: darkNavy.withValues(alpha: 0.3),
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 16,
          ), // py-4
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: GoogleFonts.inter(color: darkNavy, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: GoogleFonts.inter(
            color: darkNavy.withValues(alpha: 0.3),
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.lock_outline,
            color: darkNavy.withValues(alpha: 0.3),
            size: 22,
          ),
          suffixIcon: GestureDetector(
            onTap: () {
              setState(() => _obscurePassword = !_obscurePassword);
            },
            child: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: darkNavy.withValues(alpha: 0.3),
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [primaryColor, brandDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.3), // shadow-button-glow
              blurRadius: 15,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _handleLogin,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Login',
                        style: GoogleFonts.quicksand(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: darkNavy.withValues(alpha: 0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading
                ? null
                : () async {
                    setState(() => _isLoading = true);
                    try {
                      await _authService.signInWithGoogle(
                        defaultRole: widget.role,
                      );
                      if (!mounted) return;
                      if (widget.role == 'owner') {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const OwnerDashboardScreen(),
                          ),
                          (route) => false,
                        );
                      } else {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LocationScreen(),
                          ),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString(),
                              style: GoogleFonts.inter(),
                            ),
                            backgroundColor: const Color(0xFFDC2626),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Login with Google',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: darkNavy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaundryLogoPainter extends CustomPainter {
  final Color color;
  _LaundryLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 100;

    // Shirt shape
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

    // Sparkle
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

    // Smile arc
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

    // Bubbles
    canvas.drawCircle(Offset(25 * scale, 55 * scale), 2.5 * scale, paint);
    canvas.drawCircle(Offset(75 * scale, 52 * scale), 3 * scale, paint);
    canvas.drawCircle(Offset(65 * scale, 70 * scale), 1.5 * scale, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
