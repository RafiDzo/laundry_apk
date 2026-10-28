import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/order_model.dart';
import '../services/evidence_service.dart';
import '../widgets/evidence_widgets.dart';

const _blue = Color(0xFF0077E6);
const _amber = Color(0xFFD97706);
const _textDark = Color(0xFF0F172A);
const _textLight = Color(0xFF64748B);

/// Formulir klaim kerusakan pelanggan (maks. 2×24 jam setelah cucian diterima)
class DamageClaimFormScreen extends StatefulWidget {
  final OrderModel order;
  const DamageClaimFormScreen({super.key, required this.order});

  @override
  State<DamageClaimFormScreen> createState() => _DamageClaimFormScreenState();
}

class _DamageClaimFormScreenState extends State<DamageClaimFormScreen> {
  final _descCtrl = TextEditingController();
  List<XFile> _photos = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (_photos.isEmpty) {
      setState(() => _error = 'Lampirkan minimal 1 foto kerusakan.');
      return;
    }
    if (desc.length < 10) {
      setState(() => _error = 'Jelaskan kerusakan minimal 10 karakter.');
      return;
    }
    if (!widget.order.canClaim) {
      setState(() => _error = 'Batas waktu klaim 2×24 jam sudah lewat.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await EvidenceService().createClaim(
        orderId: widget.order.id,
        shopId: widget.order.shopId,
        description: desc,
        photos: _photos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Klaim terkirim. Outlet akan memeriksa bukti fotomu.'), backgroundColor: _amber),
      );
      Navigator.pop(context, true);
    } catch (e) {
      print('Error createClaim: $e');
      final msg = e.toString();
      setState(() {
        _busy = false;
        _error = msg.contains('duplicate key') || msg.contains('23505')
            ? 'Pesanan ini sudah pernah diklaim.'
            : evidenceErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text('Laporkan Kerusakan',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: _textDark)),
        iconTheme: const IconThemeData(color: _textDark),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'Foto bukti kamu akan dibandingkan dengan foto kondisi cucian saat diterima outlet. '
                  'Foto yang jelas (bagian rusak terlihat dekat) mempercepat verifikasi.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF92400E), height: 1.5),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pesanan #${widget.order.id.substring(0, 8).toUpperCase()} • ${widget.order.shopName}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textLight)),
                    const SizedBox(height: 14),
                    PhotoPickerField(
                      photos: _photos,
                      label: 'Foto Kerusakan (min. 1)',
                      onChanged: (p) => setState(() => _photos = p),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 5,
                      minLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Jelaskan kerusakan',
                        hintText: 'Mis. kemeja putih luntur jadi biru, kancing jas hilang 2',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFFDC2626))),
              ],
              const SizedBox(height: 20),
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
                      : Text('Kirim Klaim', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
