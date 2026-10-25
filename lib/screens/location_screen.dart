import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'home_screen.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _pingController;
  late Animation<double> _pulseScaleAnim;
  late Animation<double> _pingScaleAnim;
  late Animation<double> _pingOpacityAnim;

  final _searchController = TextEditingController();
  String? _selectedCity;

  // Default center: Jakarta
  LatLng _center = const LatLng(-6.2088, 106.8456);
  final MapController _mapController = MapController();
  bool _isSearching = false;
  String? _searchError;
  LatLng? _searchResult;

  final List<Map<String, dynamic>> _cities = [
    {'name': 'Jakarta', 'latlng': LatLng(-6.2088, 106.8456)},
    {'name': 'Bandung', 'latlng': LatLng(-6.9175, 107.6191)},
    {'name': 'Surabaya', 'latlng': LatLng(-7.2575, 112.7521)},
    {'name': 'Malang', 'latlng': LatLng(-7.9839, 112.6214)},
  ];

  @override
  void initState() {
    super.initState();
    // Pulse animation (slow pulse)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseScaleAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ping animation
    _pingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pingScaleAnim = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: _pingController, curve: Curves.easeOutCubic),
    );
    _pingOpacityAnim = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(parent: _pingController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pingController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _goToCity(Map<String, dynamic> city) {
    final latlng = city['latlng'] as LatLng;
    setState(() {
      _selectedCity = city['name'];
      _center = latlng;
      _searchResult = null;
      _searchError = null;
    });
    _mapController.move(latlng, 13.0);
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _selectedCity = null;
    });
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=1&countrycodes=id',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'WashoraApp/1.0'},
      );
      if (response.statusCode == 200) {
        final List results = jsonDecode(response.body);
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat']);
          final lon = double.parse(results[0]['lon']);
          final latlng = LatLng(lat, lon);
          setState(() {
            _searchResult = latlng;
            _center = latlng;
          });
          _mapController.move(latlng, 15.0);
        } else {
          setState(() => _searchError = 'Lokasi "$query" tidak ditemukan');
        }
      } else {
        setState(() => _searchError = 'Gagal mencari lokasi, coba lagi');
      }
    } catch (e) {
      setState(() => _searchError = 'Periksa koneksi internet Anda');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F5),
      body: Stack(
        children: [
          // ── Real OpenStreetMap ──
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 13.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.laundry_apk',
                  maxZoom: 19,
                  // Grayscale & Brightness adjustments to mimic CSS filter
                  tileProvider: NetworkTileProvider(),
                ),
                // Marker hasil pencarian
                if (_searchResult != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _searchResult!,
                        width: 48,
                        height: 56,
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFEF4444),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.search, color: Colors.white, size: 20),
                            ),
                            CustomPaint(
                              size: const Size(14, 10),
                              painter: _RedPinPainter(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Overlays mimicking CSS ──
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.white.withValues(alpha: 0.3)),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar ──
          _buildTopBar(),

          // ── Center map pin ──
          _buildCenterPin(),

          // ── Bottom Glass Card ──
          _buildBottomCard(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back Button
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: Color(0xFF1E293B), size: 22),
                    ),
                  ),
                ),
              ),

              // Brand Badge
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_laundry_service, color: Color(0xFF00B4D8), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'WASHORA',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 44), // Balancer
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPin() {
    // 35% height placement
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.35,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The glowing and pinging pin
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ping 1
                    AnimatedBuilder(
                      animation: _pingController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pingScaleAnim.value * 1.5,
                          child: Opacity(
                            opacity: _pingOpacityAnim.value * 0.5,
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.2), width: 1),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Inner ping 2
                    AnimatedBuilder(
                      animation: _pingController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pingScaleAnim.value,
                          child: Opacity(
                            opacity: _pingOpacityAnim.value,
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.3), width: 2),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Pulse glow
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseScaleAnim.value,
                          child: Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Main pin circle
                    Container(
                      width: 56, // w-14
                      height: 56, // h-14
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                        ),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF00B4D8).withValues(alpha: 0.5), blurRadius: 25, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 30),
                    ),
                    // Arrow pointing down from the bottom of the circle
                    Positioned(
                      bottom: 40, // carefully placed arrow
                      child: CustomPaint(
                        size: const Size(16, 12),
                        painter: _PinArrowPainter(),
                      ),
                    ),
                  ],
                ),
              ),
              // Floating text badge
              Transform.translate(
                offset: const Offset(0, -20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                        ],
                      ),
                      child: Text(
                        'GESER UNTUK MENYESUAIKAN',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00B4D8),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32), // 2xl
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08), // shadow-card
                blurRadius: 40,
                offset: const Offset(0, -10),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA).withValues(alpha: 0.9), // bone
                  border: const Border(top: BorderSide(color: Colors.white70)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B4D8).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.explore, color: Color(0xFF00B4D8), size: 24),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Atur Lokasi Anda',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A), // slate-900
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Tentukan titik lokasi anda sekarang',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B), // slate-500
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 20),

                      // Search field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)), // slate-200
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF1E293B)),
                          onSubmitted: (v) => _searchLocation(v),
                          decoration: InputDecoration(
                            hintText: 'Cari alamat atau area...',
                            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8)), // slate-400
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4D8)),
                                    ),
                                  )
                                : _searchResult != null
                                    ? IconButton(
                                        icon: const Icon(Icons.close, color: Colors.black26),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchResult = null;
                                            _searchError = null;
                                          });
                                        },
                                      )
                                    : null,
                          ),
                        ),
                      ),
                      if (_searchError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(_searchError!, style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontSize: 12)),
                        ),

                      const SizedBox(height: 20),

                      // Chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _cities.map((city) {
                          final isSelected = _selectedCity == city['name'];
                          return InkWell(
                            onTap: () => _goToCity(city),
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF00B4D8).withValues(alpha: 0.1) : Colors.white,
                                border: Border.all(color: isSelected ? const Color(0xFF00B4D8) : const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2)],
                              ),
                              child: Text(
                                city['name'],
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? const Color(0xFF00B4D8) : const Color(0xFF475569), // slate-600
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Recent Locations
                      Text(
                        'LOKASI TERAKHIR',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF94A3B8), // slate-400
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          _buildRecentLocationTile('Apartemen Kemang Village', 'Jakarta Selatan'),
                          const SizedBox(height: 12),
                          _buildRecentLocationTile('Kantor Sudirman', 'Jakarta Pusat'),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Primary Button
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00B4D8),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00B4D8).withValues(alpha: 0.4),
                              blurRadius: 25,
                            )
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const HomeScreen()),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.near_me, color: Colors.white, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    'IZINKAN AKSES LOKASI',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentLocationTile(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)), // slate-100
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), // slate-100
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, color: Color(0xFF94A3B8), size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: const Color(0xFF1E293B), // slate-800
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.normal,
                  fontSize: 11,
                  color: const Color(0xFF64748B), // slate-500
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0077B6) // secondary color
      ..style = PaintingStyle.fill;
    final path = ui.Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RedPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    final path = ui.Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
