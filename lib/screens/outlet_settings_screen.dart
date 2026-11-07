import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/service_model.dart';
import '../models/shop_model.dart';
import '../services/geo_service.dart';
import '../services/supabase_service.dart';
import '../widgets/quick_snackbar.dart';

const _kBrand = Color(0xFF0077B6);
const _kBlue = Color(0xFF0091EA);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kBg = Color(0xFFF1F5F9);

String _rupiah(int v) =>
    'Rp ${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

/// Ikon layanan yang bisa dipilih mitra (nama disimpan di kolom services.iconName)
const Map<String, IconData> kServiceIcons = {
  'local_laundry_service': Icons.local_laundry_service_rounded,
  'bolt': Icons.bolt_rounded,
  'iron': Icons.iron_rounded,
  'dry_cleaning': Icons.dry_cleaning_rounded,
  'checkroom': Icons.checkroom_rounded,
  'bed': Icons.bed_rounded,
  'dry': Icons.dry_rounded,
};

/// Pengaturan outlet milik mitra: info outlet, jam buka, lokasi peta,
/// serta daftar tarif & layanan yang tampil ke pelanggan.
class OutletSettingsScreen extends StatefulWidget {
  final ShopModel shop;

  /// 0 = Info Outlet, 1 = Tarif & Layanan
  final int initialTab;

  const OutletSettingsScreen({
    super.key,
    required this.shop,
    this.initialTab = 0,
  });

  @override
  State<OutletSettingsScreen> createState() => _OutletSettingsScreenState();
}

class _OutletSettingsScreenState extends State<OutletSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  late final _name = TextEditingController(text: widget.shop.name);
  late final _phone = TextEditingController(text: widget.shop.phone);
  late final _desc = TextEditingController(text: widget.shop.description);
  late final _address = TextEditingController(text: widget.shop.address);
  late final _price = TextEditingController(
    text: widget.shop.pricePerKg > 0 ? widget.shop.pricePerKg.toString() : '',
  );
  final _mapController = MapController();

  late bool _isOpen = widget.shop.isOpen;
  bool _is24h = false;
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 21, minute: 0);
  LatLng? _location;
  late List<ServiceModel> _services = List.of(widget.shop.services);

  bool _saving = false;
  bool _locating = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _parseHours(widget.shop.openHours);
    if (widget.shop.hasLocation) {
      _location = LatLng(widget.shop.latitude!, widget.shop.longitude!);
    }
    for (final c in [_name, _phone, _desc, _address, _price]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _parseHours(String text) {
    if (text.toLowerCase().contains('24')) {
      _is24h = true;
      return;
    }
    final m = RegExp(
      r'(\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})',
    ).firstMatch(text);
    if (m != null) {
      _openTime = TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
      _closeTime = TimeOfDay(hour: int.parse(m[3]!), minute: int.parse(m[4]!));
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String get _hoursText =>
      _is24h ? '24 Jam' : '${_fmt(_openTime)} - ${_fmt(_closeTime)}';

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_name, _phone, _desc, _address, _price]) {
      c.dispose();
    }
    _mapController.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color color = _kInk}) {
    ScaffoldMessenger.of(context).showQuickSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      ),
    );
  }

  Future<void> _locateFromAddress() async {
    final text = _address.text.trim();
    if (text.isEmpty) {
      _toast('Isi alamat outlet dulu', color: const Color(0xFFDC2626));
      return;
    }
    setState(() => _locating = true);
    final p = await GeoService.geocode(text);
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      _toast(
        'Alamat tidak ditemukan di peta. Ketuk peta untuk menandai lokasi.',
        color: const Color(0xFFD97706),
      );
      return;
    }
    setState(() {
      _location = LatLng(p.lat, p.lng);
      _dirty = true;
    });
    _mapController.move(_location!, 16);
  }

  Future<void> _pickTime(bool open) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: open ? _openTime : _closeTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (open) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price =
        int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (name.isEmpty) {
      _tabs.animateTo(0);
      _toast('Nama outlet wajib diisi', color: const Color(0xFFDC2626));
      return;
    }
    if (_services.isEmpty) {
      _tabs.animateTo(1);
      _toast('Tambahkan minimal 1 layanan', color: const Color(0xFFDC2626));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    // Harga dasar per kg: dari isian, atau dari layanan kiloan termurah
    final kiloPrices = _services
        .where((s) => s.unit.contains('kg'))
        .map((s) => s.price);
    final basePrice = price > 0
        ? price
        : (kiloPrices.isEmpty ? 0 : kiloPrices.reduce((a, b) => a < b ? a : b));
    final updates = <String, dynamic>{
      'name': name,
      'address': _address.text.trim(),
      'open_hours': _hoursText,
      'price_per_kg': basePrice,
      'services': _services.map((s) => s.toMap()).toList(),
      'phone': _phone.text.trim(),
      'description': _desc.text.trim(),
      'is_open': _isOpen,
      if (_location != null) 'latitude': _location!.latitude,
      if (_location != null) 'longitude': _location!.longitude,
    };
    try {
      final updated = await SupabaseService().updateMyShop(
        widget.shop.id,
        updates,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      _toast('Pengaturan outlet tersimpan ✓', color: const Color(0xFF16A34A));
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      _toast(
        msg.contains('column') && msg.contains('does not exist') ||
                msg.contains('PGRST204')
            ? 'Kolom baru belum ada. Jalankan supabase_ulasan_lokasi.sql di Supabase.'
            : 'Gagal menyimpan: ${msg.replaceFirst('Exception: ', '')}',
        color: const Color(0xFFDC2626),
      );
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Buang perubahan?',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Perubahan yang belum disimpan akan hilang.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Buang',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: _kInk,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pengaturan Outlet',
                style: GoogleFonts.quicksand(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                widget.shop.name,
                style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabs,
            labelColor: _kBrand,
            unselectedLabelColor: _kMuted,
            indicatorColor: _kBrand,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            tabs: [
              const Tab(
                icon: Icon(Icons.storefront_rounded, size: 20),
                text: 'Info Outlet',
              ),
              Tab(
                icon: const Icon(Icons.sell_outlined, size: 20),
                text: 'Tarif & Layanan (${_services.length})',
              ),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: TabBarView(
              controller: _tabs,
              children: [_buildInfoTab(), _buildServicesTab()],
            ),
          ),
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              _dirty ? 'Simpan Perubahan' : 'Simpan',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrand,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  TAB 1: INFO OUTLET
  // ═══════════════════════════════════════════════
  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status buka / tutup
        _card(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      (_isOpen
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isOpen
                      ? Icons.storefront_rounded
                      : Icons.store_mall_directory_outlined,
                  color: _isOpen
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isOpen ? 'Outlet Buka' : 'Outlet Tutup Sementara',
                      style: GoogleFonts.quicksand(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                    Text(
                      _isOpen
                          ? 'Pelanggan bisa memesan sekarang'
                          : 'Pelanggan melihat outlet sebagai tutup',
                      style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isOpen,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF16A34A),
                onChanged: (v) => setState(() {
                  _isOpen = v;
                  _dirty = true;
                }),
              ),
            ],
          ),
        ),
        _section('Informasi Outlet', Icons.info_outline_rounded),
        _card(
          child: Column(
            children: [
              _input(
                _name,
                'Nama Outlet',
                Icons.local_laundry_service_outlined,
              ),
              const SizedBox(height: 12),
              _input(
                _phone,
                'No. WhatsApp Outlet',
                Icons.phone_outlined,
                hint: '08xxxxxxxxxx',
                keyboard: TextInputType.phone,
                digitsOnly: true,
              ),
              const SizedBox(height: 12),
              _input(
                _desc,
                'Deskripsi Singkat',
                Icons.notes_rounded,
                hint: 'Mis. Laundry kiloan wangi, bisa antar jemput',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _input(
                _price,
                'Harga Dasar Cuci Kiloan',
                Icons.payments_outlined,
                prefix: 'Rp ',
                suffix: '/ kg',
                keyboard: TextInputType.number,
                digitsOnly: true,
              ),
            ],
          ),
        ),
        _section('Jam Operasional', Icons.schedule_rounded),
        _card(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buka 24 Jam',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kInk,
                      ),
                    ),
                  ),
                  Switch(
                    value: _is24h,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _kBrand,
                    onChanged: (v) => setState(() {
                      _is24h = v;
                      _dirty = true;
                    }),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _is24h
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      _timeBox('Buka', _openTime, () => _pickTime(true)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: _kMuted,
                          size: 18,
                        ),
                      ),
                      _timeBox('Tutup', _closeTime, () => _pickTime(false)),
                    ],
                  ),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        _section('Alamat & Lokasi Peta', Icons.place_outlined),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _input(
                _address,
                'Alamat Lengkap',
                Icons.home_work_outlined,
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _locating ? null : _locateFromAddress,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(
                  'Cari lokasi dari alamat',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBrand,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 220,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _location ?? const LatLng(-6.2088, 106.8456),
                      initialZoom: _location != null ? 16 : 11,
                      onTap: (_, point) => setState(() {
                        _location = point;
                        _dirty = true;
                      }),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.laundry_apk',
                        maxZoom: 19,
                      ),
                      if (_location != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _location!,
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFFDC2626),
                                size: 44,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _location != null
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: _location != null
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _location != null
                          ? 'Lokasi ditandai (${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}). '
                                'Jarak ke pelanggan dihitung dari titik ini.'
                          : 'Ketuk peta untuk menandai lokasi outlet, agar jarak ke pelanggan akurat.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  TAB 2: TARIF & LAYANAN
  // ═══════════════════════════════════════════════
  Widget _buildServicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: _kBrand,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Layanan & harga di sini langsung tampil di halaman outlet pelanggan setelah disimpan.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_services.isEmpty)
          _card(
            child: Column(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: Color(0xFFCBD5E1),
                ),
                const SizedBox(height: 8),
                Text(
                  'Belum ada layanan',
                  style: GoogleFonts.quicksand(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _kMuted,
                  ),
                ),
                Text(
                  'Tambahkan layanan pertama outletmu.',
                  style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _services.length; i++) _serviceTile(i),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _editService(),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Tambah Layanan',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kBrand,
            side: const BorderSide(color: _kBrand, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _serviceTile(int i) {
    final s = _services[i];
    final icon =
        kServiceIcons[s.iconName] ?? Icons.local_laundry_service_rounded;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: InkWell(
        onTap: () => _editService(index: i),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _kBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: GoogleFonts.quicksand(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                    if (s.description.isNotEmpty)
                      Text(
                        s.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: _kMuted,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${_rupiah(s.price)} ${s.unit}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kBrand,
                          ),
                        ),
                        if (s.duration.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.duration,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _kMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: _kMuted),
                onSelected: (v) {
                  if (v == 'edit') _editService(index: i);
                  if (v == 'up' && i > 0) {
                    setState(() {
                      final s = _services.removeAt(i);
                      _services.insert(i - 1, s);
                      _dirty = true;
                    });
                  }
                  if (v == 'delete') _deleteService(i);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Ubah')),
                  if (i > 0)
                    const PopupMenuItem(
                      value: 'up',
                      child: Text('Pindah ke atas'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Hapus',
                      style: TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteService(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Hapus layanan?',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '"${_services[i].name}" tidak akan tampil lagi ke pelanggan.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _services = List.of(_services)..removeAt(i);
        _dirty = true;
      });
    }
  }

  Future<void> _editService({int? index}) async {
    final existing = index != null ? _services[index] : null;
    final result = await showModalBottomSheet<ServiceModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceEditor(existing: existing),
    );
    if (result == null) return;
    setState(() {
      _services = List.of(_services);
      if (index != null) {
        _services[index] = result;
      } else {
        _services.add(result);
      }
      _dirty = true;
    });
  }

  // ═══════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════
  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kMuted),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _kMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }

  Widget _input(
    TextEditingController c,
    String label,
    IconData icon, {
    String? hint,
    String? prefix,
    String? suffix,
    int maxLines = 1,
    TextInputType? keyboard,
    bool digitsOnly = false,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: GoogleFonts.inter(fontSize: 14, color: _kInk),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBrand, width: 1.6),
        ),
      ),
    );
  }

  Widget _timeBox(String label, TimeOfDay t, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, color: _kMuted),
              ),
              Text(
                _fmt(t),
                style: GoogleFonts.quicksand(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  EDITOR SATU LAYANAN (BOTTOM SHEET)
// ═══════════════════════════════════════════════════
class _ServiceEditor extends StatefulWidget {
  final ServiceModel? existing;
  const _ServiceEditor({this.existing});

  @override
  State<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends State<_ServiceEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _price = TextEditingController(
    text: (widget.existing?.price ?? 0) > 0
        ? widget.existing!.price.toString()
        : '',
  );
  late String _unit = widget.existing?.unit.contains('pcs') == true
      ? '/ pcs'
      : '/ kg';
  late String _icon = kServiceIcons.containsKey(widget.existing?.iconName)
      ? widget.existing!.iconName
      : 'local_laundry_service';
  late String _duration = widget.existing?.duration.isNotEmpty == true
      ? widget.existing!.duration
      : '1-2 Hari';
  String? _error;

  static const _durations = [
    '4 Jam',
    '1 Hari',
    '1-2 Hari',
    '2-3 Hari',
    '3 Hari',
  ];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final price =
        int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = 'Nama layanan wajib diisi');
      return;
    }
    if (price <= 0) {
      setState(() => _error = 'Harga harus lebih dari 0');
      return;
    }
    Navigator.pop(
      context,
      ServiceModel(
        id: widget.existing?.id.isNotEmpty == true
            ? widget.existing!.id
            : 's${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: _desc.text.trim(),
        price: price,
        unit: _unit,
        iconName: _icon,
        duration: _duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.existing == null ? 'Tambah Layanan' : 'Ubah Layanan',
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const SizedBox(height: 16),
                _field(_name, 'Nama layanan', hint: 'Mis. Cuci Komplit'),
                const SizedBox(height: 10),
                _field(
                  _desc,
                  'Keterangan (opsional)',
                  hint: 'Mis. Cuci + kering + setrika',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _price,
                        'Harga',
                        prefix: 'Rp ',
                        number: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '/ kg', label: Text('/ kg')),
                        ButtonSegment(value: '/ pcs', label: Text('/ pcs')),
                      ],
                      selected: {_unit},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _unit = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Estimasi selesai',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _durations
                      .map(
                        (d) => ChoiceChip(
                          label: Text(d),
                          selected: _duration == d,
                          onSelected: (_) => setState(() => _duration = d),
                          selectedColor: _kBrand.withValues(alpha: 0.15),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _duration == d ? _kBrand : _kInk,
                          ),
                          showCheckmark: false,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ikon',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kServiceIcons.entries.map((e) {
                    final on = _icon == e.key;
                    return GestureDetector(
                      onTap: () => setState(() => _icon = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: on ? _kBrand : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          e.value,
                          color: on ? Colors.white : _kMuted,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFFDC2626),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      widget.existing == null ? 'Tambahkan' : 'Simpan Layanan',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? prefix,
    bool number = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: GoogleFonts.inter(fontSize: 14, color: _kInk),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBrand, width: 1.6),
        ),
      ),
    );
  }
}
