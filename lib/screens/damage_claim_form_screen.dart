import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/evidence_models.dart';
import '../models/order_model.dart';
import '../services/evidence_service.dart';
import '../services/membership_service.dart';
import '../utils/format_id.dart';
import '../widgets/evidence_widgets.dart';
import '../widgets/quick_snackbar.dart';

const _blue = Color(0xFF0077E6);
const _amber = Color(0xFFD97706);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _red = Color(0xFFDC2626);

TextStyle _t(double s, {Color c = _ink, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.plusJakartaSans(fontSize: s, fontWeight: w, color: c);

/// Formulir klaim kerusakan pelanggan: jenis kerusakan, item terdampak,
/// penyelesaian yang diharapkan, foto bukti, dan penjelasan.
class DamageClaimFormScreen extends StatefulWidget {
  final OrderModel order;
  const DamageClaimFormScreen({super.key, required this.order});

  @override
  State<DamageClaimFormScreen> createState() => _DamageClaimFormScreenState();
}

class _DamageClaimFormScreenState extends State<DamageClaimFormScreen> {
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  List<XFile> _photos = [];
  String? _category;
  final Set<String> _items = {};
  String _resolution = 'rewash';
  int? _serverCap;
  bool _busy = false;
  String? _error;

  OrderModel get _o => widget.order;

  /// Batas ganti rugi: 10× harga layanan item terdampak (semua item jika tidak dipilih)
  int get _cap {
    final chosen = _items.isEmpty ? _o.items : _o.items.where((i) => _items.contains(i.name));
    return (chosen.fold<num>(0, (s, i) => s + i.price * i.qty) * 10).round();
  }

  int get _effectiveCap => _serverCap ?? _cap;

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCap() async {
    final c = await EvidenceService().compensationCap(_o.id, _items.toList());
    if (mounted) setState(() => _serverCap = c);
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    final amount = int.tryParse(_amountCtrl.text);
    String? err;
    if (_category == null) {
      err = 'Pilih jenis kerusakan.';
    } else if (_photos.isEmpty) {
      err = 'Lampirkan minimal 1 foto kerusakan.';
    } else if (desc.length < 10) {
      err = 'Jelaskan kerusakan minimal 10 karakter.';
    } else if (_resolution == 'compensation' && (amount == null || amount <= 0)) {
      err = 'Isi nominal ganti rugi yang diminta.';
    } else if (_resolution == 'compensation' && amount! > _effectiveCap) {
      err = 'Ganti rugi maksimal ${rupiah(_effectiveCap)} (10x harga layanan item terdampak).';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final claimHours = await MembershipService().claimHoursFor(_o);
    if (!mounted) return;
    if (!_o.canClaimWithin(claimHours)) {
      setState(() => _error = 'Batas waktu klaim $claimHours jam sudah lewat.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await EvidenceService().createClaim(
        orderId: _o.id,
        shopId: _o.shopId,
        description: desc,
        photos: _photos,
        category: _category,
        affectedItems: _items.toList(),
        requestedResolution: _resolution,
        requestedAmount: _resolution == 'compensation' ? amount : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showQuickSnackBar(
        const SnackBar(content: Text('Klaim terkirim. Outlet akan merespons maksimal 2x24 jam.'), backgroundColor: _amber),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error createClaim: $e');
      final msg = e.toString();
      final cap = RegExp(r'Ganti rugi maksimal Rp [\d.]+').firstMatch(msg)?.group(0);
      setState(() {
        _busy = false;
        _error = msg.contains('duplicate key') || msg.contains('23505')
            ? 'Pesanan ini sudah pernah diklaim.'
            : cap != null
                ? '$cap (10x harga layanan item terdampak).'
                : evidenceErrorMessage(e);
      });
    }
  }

  Widget _card({required String title, String? hint, required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _t(14, w: FontWeight.w800)),
            if (hint != null) ...[const SizedBox(height: 2), Text(hint, style: _t(11.5, c: _muted))],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Laporkan Kerusakan', style: _t(16, w: FontWeight.w800)),
            Text('Pesanan #${nomorTransaksi(_o.id)} · ${_o.shopName}', style: _t(11.5, c: _muted)),
          ],
        ),
        iconTheme: const IconThemeData(color: _ink),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'Foto buktimu dibandingkan dengan foto kondisi cucian saat diterima outlet. '
                  'Outlet wajib merespons dalam 2x24 jam; jika tidak, kamu bisa menaikkan klaim ke tim Washora.',
                  style: _t(12, c: const Color(0xFF92400E)).copyWith(height: 1.5),
                ),
              ),
              _card(
                title: '1. Jenis kerusakan',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in DamageClaim.categoryLabels.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _category == e.key,
                        onSelected: (_) => setState(() => _category = e.key),
                        labelStyle: _t(12.5, c: _category == e.key ? Colors.white : _ink, w: FontWeight.w600),
                        selectedColor: _blue,
                        backgroundColor: Colors.white,
                        showCheckmark: false,
                        side: BorderSide(color: _category == e.key ? _blue : _border),
                      ),
                  ],
                ),
              ),
              if (_o.items.isNotEmpty)
                _card(
                  title: '2. Item yang terdampak',
                  hint: 'Kosongkan jika berlaku untuk seluruh pesanan',
                  child: Column(
                    children: [
                      for (final i in _o.items)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: false,
                          value: _items.contains(i.name),
                          onChanged: (v) {
                            setState(() => v == true ? _items.add(i.name) : _items.remove(i.name));
                            _refreshCap();
                          },
                          title: Text(i.name, style: _t(13.5, w: FontWeight.w600)),
                          subtitle: Text('${angka(i.qty)} ${i.unit.replaceAll('/', '').trim()} × ${rupiah(i.price)}',
                              style: _t(11.5, c: _muted)),
                        ),
                    ],
                  ),
                ),
              _card(
                title: '3. Penyelesaian yang kamu harapkan',
                hint: 'Keputusan akhir tetap di outlet; pilihanmu jadi pertimbangan',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioGroup<String>(
                      groupValue: _resolution,
                      onChanged: (v) => setState(() => _resolution = v!),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: 'rewash',
                            contentPadding: EdgeInsets.zero,
                            title: Text('Cuci ulang gratis', style: _t(13.5, w: FontWeight.w600)),
                            subtitle: Text('Untuk noda, bau, atau hasil kurang bersih', style: _t(11.5, c: _muted)),
                          ),
                          RadioListTile<String>(
                            value: 'compensation',
                            contentPadding: EdgeInsets.zero,
                            title: Text('Ganti rugi uang', style: _t(13.5, w: FontWeight.w600)),
                            subtitle: Text('Untuk barang rusak permanen atau hilang', style: _t(11.5, c: _muted)),
                          ),
                          RadioListTile<String>(
                            value: 'points',
                            contentPadding: EdgeInsets.zero,
                            title: Text('Poin Washora', style: _t(13.5, w: FontWeight.w600)),
                            subtitle: Text('Langsung masuk ke saldo poin, bisa dipakai di pesanan berikutnya', style: _t(11.5, c: _muted)),
                          ),
                        ],
                      ),
                    ),
                    if (_resolution == 'compensation') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Nominal yang diminta',
                          prefixText: 'Rp ',
                          helperText: 'Maksimal ${rupiah(_effectiveCap)} (10x harga layanan item terdampak)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _card(
                title: '4. Bukti & penjelasan',
                child: Column(
                  children: [
                    PhotoPickerField(
                      photos: _photos,
                      label: 'Foto kerusakan (min. 1, bagian rusak terlihat dekat)',
                      onChanged: (p) => setState(() => _photos = p),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 5,
                      minLines: 3,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: 'Jelaskan kerusakan',
                        hintText: 'Mis. kemeja putih luntur jadi biru di bagian kerah',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: _t(12.5, c: _red, w: FontWeight.w600)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(_error != null ? 'Coba lagi' : 'Kirim Klaim', style: _t(15, c: Colors.white, w: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
