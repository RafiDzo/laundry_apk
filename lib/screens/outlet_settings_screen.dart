import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/shop_model.dart';
import '../payments/qris.dart';
import '../payments/qris_scanner.dart';
import '../services/geo_service.dart';
import '../services/supabase_service.dart';
import '../widgets/quick_snackbar.dart';

const _kBrand = Color(0xFF0077B6);
const _kInk = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);
const _kBg = Color(0xFFF1F5F9);

/// Info Outlet milik mitra: foto profil, nama, kontak, deskripsi, alamat & lokasi peta.
/// Tarif layanan, jam buka, status buka/tutup, dan antar jemput diatur di menu
/// Pengaturan dashboard (tidak diulang di sini agar tidak dobel).
class OutletSettingsScreen extends StatefulWidget {
  final ShopModel shop;

  const OutletSettingsScreen({super.key, required this.shop});

  @override
  State<OutletSettingsScreen> createState() => _OutletSettingsScreenState();
}

class _OutletSettingsScreenState extends State<OutletSettingsScreen> {
  late final _name = TextEditingController(text: widget.shop.name);
  late final _phone = TextEditingController(text: widget.shop.phone);
  late final _desc = TextEditingController(text: widget.shop.description);
  late final _address = TextEditingController(text: widget.shop.address);
  late final _qris = TextEditingController(text: widget.shop.qrisPayload);
  final _mapController = MapController();

  LatLng? _location;

  // Foto profil outlet (kolom shops.image_url, tampil di Beranda & halaman outlet)
  late String _imageUrl = widget.shop.imageUrl;
  Uint8List? _newPhoto;
  String _newPhotoMime = 'image/jpeg';

  bool _saving = false;
  bool _locating = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.shop.hasLocation) {
      _location = LatLng(widget.shop.latitude!, widget.shop.longitude!);
    }
    for (final c in [_name, _phone, _desc, _address, _qris]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _desc, _address, _qris]) {
      c.dispose();
    }
    _mapController.dispose();
    super.dispose();
  }

  bool _readingQris = false;

  void _applyQris(String payload) {
    setState(() => _qris.text = payload);
    _toast('QRIS terbaca: ${Qris.merchantName(payload)}. Tekan Simpan untuk menyimpan.',
        color: const Color(0xFF15803D));
  }

  Future<void> _scanQrisCamera() async {
    final payload = await scanQrisWithCamera(context);
    if (payload != null && mounted) _applyQris(payload);
  }

  Future<void> _scanQrisGallery() async {
    setState(() => _readingQris = true);
    final r = await readQrisFromGallery();
    if (!mounted) return;
    setState(() => _readingQris = false);
    if (r == null) return;
    if (r.ok) {
      _applyQris(r.payload!);
    } else {
      _toast(r.error!, color: const Color(0xFFDC2626));
    }
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

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Dikompres sebelum unggah: sisi terpanjang 1200px, kualitas 75
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        _toast('Ukuran foto melebihi 3 MB setelah dikompres. Pilih foto lain.', color: const Color(0xFFDC2626));
        return;
      }
      final name = file.name.toLowerCase();
      setState(() {
        _newPhoto = bytes;
        _newPhotoMime = file.mimeType ??
            (name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
        _dirty = true;
      });
    } catch (e) {
      _toast('Foto tidak bisa dibuka: $e', color: const Color(0xFFDC2626));
    }
  }

  void _removePhoto() {
    setState(() {
      _newPhoto = null;
      _imageUrl = '';
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Nama outlet wajib diisi', color: const Color(0xFFDC2626));
      return;
    }
    final qris = _qris.text.trim();
    final qrisErr = qris.isEmpty ? null : Qris.validate(qris);
    if (qrisErr != null) {
      _toast('QRIS outlet tidak valid: $qrisErr', color: const Color(0xFFDC2626));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_newPhoto != null) {
        imageUrl = await SupabaseService().uploadShopPhoto(widget.shop.id, _newPhoto!, mime: _newPhotoMime);
      }
      final updates = <String, dynamic>{
        'name': name,
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'description': _desc.text.trim(),
        'image_url': imageUrl,
        'qris_payload': qris,
        if (_location != null) 'latitude': _location!.latitude,
        if (_location != null) 'longitude': _location!.longitude,
      };
      final updated = await SupabaseService().updateMyShop(widget.shop.id, updates);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _imageUrl = imageUrl;
        _newPhoto = null;
      });
      _toast('Info outlet tersimpan', color: const Color(0xFF16A34A));
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      _toast(
        msg.contains('Bucket not found') || msg.contains('bucket')
            ? 'Penyimpanan foto belum dibuat. Jalankan supabase_foto_outlet.sql di Supabase.'
            : msg.contains('column') && msg.contains('does not exist') || msg.contains('PGRST204')
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
                'Info Outlet',
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
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildInfoTab(),
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
        _buildPhotoCard(),
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
            ],
          ),
        ),
        // Tarif, jam buka & antar jemput ada di menu Pengaturan (bukan di sini)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: _kMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tarif layanan, jam buka, status buka/tutup, dan antar jemput diatur di menu Pengaturan.',
                  style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
                ),
              ),
            ],
          ),
        ),
        _section('QRIS Outlet', Icons.qr_code_2_rounded),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scan stiker QRIS statis outlet atau pilih gambarnya dari galeri. Pelanggan yang memilih QRIS akan '
                'melihat QR dengan total pesanan terisi otomatis, dan pembayaran masuk langsung ke rekening/e-wallet Anda.',
                style: GoogleFonts.inter(fontSize: 12, color: _kMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _readingQris ? null : _scanQrisCamera,
                      style: FilledButton.styleFrom(
                        backgroundColor: _kBrand,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: const Text('Scan Kamera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _readingQris ? null : _scanQrisGallery,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrand,
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: _kBrand),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _readingQris
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_library_outlined, size: 20),
                      label: Text(_readingQris ? 'Membaca...' : 'Dari Galeri'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Atau tempel teks QRIS secara manual:',
                  style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _qris,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: '00020101021126...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _qris.text.isEmpty
                      ? null
                      : IconButton(tooltip: 'Hapus', icon: const Icon(Icons.close_rounded), onPressed: () => _qris.clear()),
                ),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final text = _qris.text.trim();
                if (text.isEmpty) {
                  return Text('Belum diatur. Gunakan tombol Scan Kamera atau Dari Galeri di atas.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted));
                }
                final err = Qris.validate(text);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(err == null ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 16, color: err == null ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        err ?? 'QRIS valid: ${Qris.merchantName(text)}${Qris.merchantCity(text).isEmpty ? '' : ', ${Qris.merchantCity(text)}'}',
                        style: GoogleFonts.inter(fontSize: 12, color: err == null ? const Color(0xFF15803D) : const Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                );
              }),
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
  //  HELPERS
  // ═══════════════════════════════════════════════
  Widget _buildPhotoCard() {
    final hasPhoto = _newPhoto != null || _imageUrl.trim().isNotEmpty;
    Widget preview;
    if (_newPhoto != null) {
      preview = Image.memory(_newPhoto!, fit: BoxFit.cover);
    } else if (_imageUrl.trim().isNotEmpty) {
      preview = Image.network(
        _imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: _kBg,
          child: Center(child: Icon(Icons.broken_image_outlined, color: _kMuted)),
        ),
      );
    } else {
      preview = const ColoredBox(
        color: _kBg,
        child: Center(child: Icon(Icons.add_a_photo_outlined, color: _kMuted, size: 30)),
      );
    }

    return _card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(width: 92, height: 92, child: preview),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foto Profil Outlet',
                  style: GoogleFonts.quicksand(fontSize: 15, fontWeight: FontWeight.w800, color: _kInk),
                ),
                const SizedBox(height: 2),
                Text(
                  _newPhoto != null
                      ? 'Foto baru, tersimpan setelah Anda menekan Simpan.'
                      : hasPhoto
                          ? 'Tampil di Beranda & halaman outlet.'
                          : 'Belum ada foto. Pelanggan melihat foto contoh laundry.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: _kMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(hasPhoto ? 'Ganti' : 'Pilih foto'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrand,
                        side: const BorderSide(color: _kBorder),
                        minimumSize: const Size(44, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    if (!kIsWeb)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Kamera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kBrand,
                          side: const BorderSide(color: _kBorder),
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    if (hasPhoto)
                      TextButton(
                        onPressed: _saving ? null : _removePhoto,
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), minimumSize: const Size(44, 44)),
                        child: const Text('Hapus'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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


}
