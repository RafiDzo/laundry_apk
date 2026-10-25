import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'logistics_screen.dart';

class OrderFlowScreen extends StatefulWidget {
  const OrderFlowScreen({super.key});

  @override
  State<OrderFlowScreen> createState() => _OrderFlowScreenState();
}

class _OrderFlowScreenState extends State<OrderFlowScreen>
    with TickerProviderStateMixin {
  // 0 = Step 1 (Pilih Layanan), 1 = Step 2 (Detail Pesanan)
  int _currentStep = 0;

  // Step 1 state
  int _selectedDeliveryType = 0; // 0=Kurir, 1=Drop-off
  int _selectedDayIndex = 0;
  int _selectedTimeIndex = 1;

  // Step 2 state
  late List<int> _serviceQuantities;
  late List<int> _unitQuantities;
  final TextEditingController _notesController = TextEditingController();
  final int _serviceFee = 2000;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _entranceController;

  final List<Map<String, String>> _days = [
    {'day': 'SEN', 'date': '14'},
    {'day': 'SEL', 'date': '15'},
    {'day': 'RAB', 'date': '16'},
    {'day': 'KAM', 'date': '17'},
    {'day': 'JUM', 'date': '18'},
  ];

  final List<Map<String, dynamic>> _timeSlots = [
    {'time': '09:00', 'available': false},
    {'time': '11:00', 'available': true},
    {'time': '13:00', 'available': true},
    {'time': '15:00', 'available': true},
    {'time': '17:00', 'available': true},
    {'time': '19:00', 'available': true},
  ];

  final List<Map<String, dynamic>> _mainServices = [
    {
      'name': 'Cuci Kiloan',
      'desc': 'Estimasi: 3 kg',
      'price': 10000,
      'unit': '/ kg',
      'icon': Icons.local_laundry_service_rounded,
    },
  ];

  final List<Map<String, dynamic>> _unitServices = [
    {
      'name': 'Sepatu',
      'desc': 'Deep cleaning',
      'price': 45000,
      'icon': Icons.roller_skating_rounded,
    },
    {
      'name': 'Jas / Blazer',
      'desc': 'Dry clean only',
      'price': 35000,
      'icon': Icons.dry_cleaning_rounded,
    },
  ];

  // Color palette (home screen theme)
  static const _blue = Color(0xFF0077E6);
  static const _blueLight = Color(0xFFEFF6FF);
  static const _surface = Color(0xFFF8FAFC);
  static const _white = Colors.white;
  static const _textDark = Color(0xFF0F172A);
  static const _textMid = Color(0xFF334155);
  static const _textLight = Color(0xFF64748B);
  static const _textHint = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bgOuter = Color(0xFFEDF2F7);

  @override
  void initState() {
    super.initState();
    _serviceQuantities = List.generate(_mainServices.length, (_) => 3);
    _unitQuantities = List.generate(_unitServices.length, (_) => 0);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _entranceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _goToStep2() {
    setState(() => _currentStep = 1);
    _slideController.forward(from: 0);
  }

  void _goToStep1() {
    _slideController.reverse().then((_) {
      if (mounted) setState(() => _currentStep = 0);
    });
  }

  int get _totalPrice {
    int total = 0;
    for (int i = 0; i < _mainServices.length; i++) {
      total += (_mainServices[i]['price'] as int) * _serviceQuantities[i];
    }
    for (int i = 0; i < _unitServices.length; i++) {
      total += (_unitServices[i]['price'] as int) * _unitQuantities[i];
    }
    total += _serviceFee;
    return total;
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final result = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      result.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) result.write('.');
    }
    return 'Rp ${result.toString().split('').reversed.join('')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgOuter,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            color: _surface,
            child: _currentStep == 0 ? _buildStep1() : _buildStep2(),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  STEP 1 — PILIH LAYANAN & WAKTU
  // ══════════════════════════════════════════════
  Widget _buildStep1() {
    return Column(
      children: [
        _buildHeader(
          'Pilih Layanan & Waktu',
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(),
                const SizedBox(height: 24),
                _buildSectionTitle('Opsi Pengiriman'),
                const SizedBox(height: 12),
                _buildDeliveryOption(
                  0,
                  Icons.two_wheeler_rounded,
                  'Kurir Antar-Jemput',
                  'Kami jemput & antar cucianmu',
                ),
                const SizedBox(height: 10),
                _buildDeliveryOption(
                  1,
                  Icons.storefront_rounded,
                  'Drop-off Sendiri',
                  'Antar langsung ke outlet',
                ),
                const SizedBox(height: 28),
                _buildSectionTitle('Jadwal Penjemputan'),
                const SizedBox(height: 12),
                _buildDaySelector(),
                const SizedBox(height: 14),
                _buildTimeGrid(),
                const SizedBox(height: 28),
                _buildSectionTitle('Estimasi Pengembalian'),
                const SizedBox(height: 12),
                _buildEstimationCard(),
                const SizedBox(height: 28),
                _buildCostSummaryCard(),
              ],
            ),
          ),
        ),
        _buildStep1Button(),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepDot(1, active: true, done: false),
        _stepLine(done: false),
        _stepDot(2, active: false, done: false),
      ],
    );
  }

  Widget _stepDot(int n, {required bool active, required bool done}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active || done ? _blue : _border,
        boxShadow: active
            ? [BoxShadow(color: _blue.withValues(alpha: 0.3), blurRadius: 10)]
            : null,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check_rounded, color: _white, size: 14)
            : Text(
                '$n',
                style: GoogleFonts.plusJakartaSans(
                  color: active || done ? _white : _textHint,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
      ),
    );
  }

  Widget _stepLine({required bool done}) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: done ? _blue : _border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildDeliveryOption(
    int index,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final isSelected = _selectedDeliveryType == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedDeliveryType = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _blueLight : _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _blue : _border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _blue.withValues(alpha: 0.15)
                  : const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _blue : const Color(0xFFF1F5F9),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _blue.withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? _white : _textLight,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? _blue : _textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: isSelected
                          ? _blue.withValues(alpha: 0.7)
                          : _textLight,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? _blue : _white,
                border: Border.all(
                  color: isSelected ? _blue : _border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: _white, size: 12)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _days.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedDayIndex == index;
          return Padding(
            padding: EdgeInsets.only(right: index < _days.length - 1 ? 10 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _selectedDayIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isSelected ? _blue : _white,
                  border: Border.all(color: isSelected ? _blue : _border),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? _blue.withValues(alpha: 0.3)
                          : const Color(0xFF0F172A).withValues(alpha: 0.04),
                      blurRadius: isSelected ? 12 : 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _days[index]['day']!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? _white.withValues(alpha: 0.85)
                            : _textLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _days[index]['date']!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? _white : _textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.6,
      ),
      itemCount: _timeSlots.length,
      itemBuilder: (context, index) {
        final slot = _timeSlots[index];
        final isAvailable = slot['available'] as bool;
        final isSelected = _selectedTimeIndex == index && isAvailable;
        return GestureDetector(
          onTap: isAvailable
              ? () => setState(() => _selectedTimeIndex = index)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: !isAvailable
                  ? const Color(0xFFF1F5F9)
                  : isSelected
                  ? _blue
                  : _white,
              border: Border.all(
                color: !isAvailable
                    ? _border
                    : isSelected
                    ? _blue
                    : _border,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                        blurRadius: 4,
                      ),
                    ],
            ),
            child: Center(
              child: Text(
                slot['time'] as String,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: !isAvailable
                      ? _textHint
                      : isSelected
                      ? _white
                      : _textMid,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEstimationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: _blue.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _blueLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: _blue,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Kamis, 17 Feb - 14:00 WIB',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Estimasi waktu berdasarkan layanan yang dipilih.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildCostSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RINGKASAN BIAYA SEMENTARA',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _blue,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          _summaryRow('Estimasi Berat', '3 kg', bold: true),
          const SizedBox(height: 8),
          _summaryRow(
            'Estimasi Harga',
            _formatPrice(30000),
            bold: true,
            valueColor: _blue,
            valueLarge: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFD97706),
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Harga final ditentukan setelah cucian ditimbang oleh kurir atau outlet.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: _textLight,
                      height: 1.5,
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

  Widget _buildStep1Button() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: _white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _goToStep2,
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: _white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            shadowColor: _blue.withValues(alpha: 0.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Pilih Layanan',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  STEP 2 — DETAIL PESANAN
  // ══════════════════════════════════════════════
  Widget _buildStep2() {
    return SlideTransition(
      position: _slideAnimation,
      child: Column(
        children: [
          _buildHeader('Detail Pesanan', onBack: _goToStep1),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStep2Indicator(),
                  const SizedBox(height: 24),
                  _buildShopInfoCard(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Detail Layanan'),
                  const SizedBox(height: 12),
                  ..._buildMainServiceCards(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Layanan Satuan'),
                  const SizedBox(height: 12),
                  ..._buildUnitServiceCards(),
                  const SizedBox(height: 20),
                  _buildNotesSection(),
                  const SizedBox(height: 20),
                  _buildOrderSummaryPanel(),
                ],
              ),
            ),
          ),
          _buildStep2Button(),
        ],
      ),
    );
  }

  Widget _buildStep2Indicator() {
    return Row(
      children: [
        _stepDot(1, active: false, done: true),
        _stepLine(done: true),
        _stepDot(2, active: true, done: false),
      ],
    );
  }

  Widget _buildShopInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF0077E6), Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.local_laundry_service_rounded,
              color: _white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CleanPro Kemang',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 13,
                      color: _blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Toko Terpilih',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _textLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
              color: _blueLight,
            ),
            child: const Icon(
              Icons.local_laundry_service_rounded,
              color: _blue,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMainServiceCards() {
    return List.generate(_mainServices.length, (index) {
      final service = _mainServices[index];
      final qty = _serviceQuantities[index];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _blueLight,
              ),
              child: Icon(service['icon'] as IconData, color: _blue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service['name'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  Text(
                    service['desc'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textLight,
                    ),
                  ),
                  Text(
                    '$qty kg × ${_formatPrice(service['price'] as int)} = ${_formatPrice((service['price'] as int) * qty)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    ),
                  ),
                ],
              ),
            ),
            _quantityControl(
              quantity: qty,
              onAdd: () => setState(() => _serviceQuantities[index]++),
              onRemove: () {
                if (qty > 1) setState(() => _serviceQuantities[index]--);
              },
            ),
          ],
        ),
      );
    });
  }

  List<Widget> _buildUnitServiceCards() {
    return List.generate(_unitServices.length, (index) {
      final service = _unitServices[index];
      final qty = _unitQuantities[index];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFF1F5F9),
              ),
              child: Icon(
                service['icon'] as IconData,
                color: _textMid,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service['name'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  Text(
                    service['desc'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textLight,
                    ),
                  ),
                ],
              ),
            ),
            _quantityControl(
              quantity: qty,
              onAdd: () => setState(() => _unitQuantities[index]++),
              onRemove: () {
                if (qty > 0) setState(() => _unitQuantities[index]--);
              },
            ),
          ],
        ),
      );
    });
  }

  Widget _quantityControl({
    required int quantity,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
        color: const Color(0xFFF8FAFC),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _counterBtn(Icons.remove_rounded, onRemove, highlight: false),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: SizedBox(
              key: ValueKey(quantity),
              width: 30,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
          ),
          _counterBtn(Icons.add_rounded, onAdd, highlight: true),
        ],
      ),
    );
  }

  Widget _counterBtn(
    IconData icon,
    VoidCallback onTap, {
    required bool highlight,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highlight ? _blue : const Color(0xFFF1F5F9),
        ),
        child: Icon(icon, color: highlight ? _white : _textMid, size: 16),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: _blue, size: 20),
            const SizedBox(width: 8),
            _buildSectionTitle('Catatan Khusus'),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesController,
          maxLines: 3,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textDark),
          decoration: InputDecoration(
            hintText: 'Contoh: Pisahkan baju putih...',
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: _textHint,
            ),
            filled: true,
            fillColor: _white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _blue, width: 2),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummaryPanel() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0F172A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: _blue, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Ringkasan Pesanan',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ..._mainServices.asMap().entries.map((e) {
                  final idx = e.key;
                  final s = e.value;
                  final qty = _serviceQuantities[idx];
                  final subtotal = (s['price'] as int) * qty;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _summaryRow(
                      '${s['name']} ($qty kg)',
                      _formatPrice(subtotal),
                      nameColor: const Color(0xFFCBD5E1),
                      valueColor: _white,
                    ),
                  );
                }),
                ..._unitServices
                    .asMap()
                    .entries
                    .where((e) => _unitQuantities[e.key] > 0)
                    .map((e) {
                      final idx = e.key;
                      final s = e.value;
                      final qty = _unitQuantities[idx];
                      final subtotal = (s['price'] as int) * qty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _summaryRow(
                          '${s['name']} ($qty)',
                          _formatPrice(subtotal),
                          nameColor: const Color(0xFFCBD5E1),
                          valueColor: _white,
                        ),
                      );
                    }),
                _summaryRow(
                  'Biaya Layanan',
                  _formatPrice(_serviceFee),
                  nameColor: const Color(0xFFCBD5E1),
                  valueColor: _white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Button() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: _white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Estimasi',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatPrice(_totalPrice),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogisticsScreen(
                    laundry: const {
                      'name': 'CleanPro Kemang',
                      'icon': Icons.local_laundry_service_rounded,
                    },
                    items: [],
                    totalAmount: _totalPrice,
                    notes: _notesController.text,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: _white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Row(
              children: [
                Text(
                  'Lanjut ke Pengiriman',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  SHARED WIDGETS
  // ══════════════════════════════════════════════
  Widget _buildHeader(String title, {required VoidCallback onBack}) {
    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _white,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _textDark,
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: _blue.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _summaryRow(
    String name,
    String value, {
    bool bold = false,
    Color? nameColor,
    Color? valueColor,
    bool valueLarge = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          name,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: nameColor ?? _textLight,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: valueLarge ? 20 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? _textDark,
          ),
        ),
      ],
    );
  }
}
