import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/promo_checkout.dart';
import '../models/shop_promo_model.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);
const _green = Color(0xFF15803D);
const _greenBg = Color(0xFFF0FDF4);
const _red = Color(0xFFB91C1C);

String _rp(int v) =>
    'Rp ${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

TextStyle _t(double size, {Color color = _ink, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color);

/// Pilihan promo outlet di halaman pembayaran. Promo tanpa kode bisa langsung
/// dipilih; promo berkode harus dimasukkan kodenya dulu. Promo yang tidak
/// memenuhi syarat tetap terlihat beserta alasannya.
class PromoCheckoutCard extends StatefulWidget {
  final bool loading;
  final List<PromoQuote> quotes;
  final PromoQuote? applied;
  final ValueChanged<PromoQuote?> onChanged;

  const PromoCheckoutCard({
    super.key,
    required this.loading,
    required this.quotes,
    required this.applied,
    required this.onChanged,
  });

  @override
  State<PromoCheckoutCard> createState() => _PromoCheckoutCardState();
}

class _PromoCheckoutCardState extends State<PromoCheckoutCard> {
  final _code = TextEditingController();
  final Set<String> _unlocked = {}; // promo berkode yang kodenya sudah benar
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _applyCode() {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final match = widget.quotes.where((q) => (q.promo.code ?? '').toUpperCase() == code).firstOrNull;
    if (match == null) {
      setState(() => _codeError = 'Kode "$code" tidak ditemukan di outlet ini.');
      return;
    }
    if (!match.usable) {
      setState(() => _codeError = match.blockedReason);
      return;
    }
    setState(() {
      _codeError = null;
      _unlocked.add(match.promo.id);
    });
    FocusScope.of(context).unfocus();
    widget.onChanged(match);
  }

  Widget _box({required Widget child, bool highlight = false}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: highlight ? const Color(0xFF86EFAC) : _border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _box(
        child: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Memeriksa promo outlet…', style: _t(12, color: _muted)),
        ]),
      );
    }
    // Outlet tidak punya promo aktif: tidak perlu menampilkan apa-apa
    if (widget.quotes.isEmpty) return const SizedBox.shrink();

    final applied = widget.applied;
    final hasCodePromo = widget.quotes.any((q) => (q.promo.code ?? '').isNotEmpty);

    return _box(
      highlight: applied != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_rounded, size: 18, color: _green),
              const SizedBox(width: 8),
              Expanded(child: Text('Promo outlet', style: _t(14, weight: FontWeight.w800))),
              if (applied != null)
                Text('Hemat ${_rp(applied.discount)}', style: _t(13, color: _green, weight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          for (final q in widget.quotes) _option(q),
          if (hasCodePromo) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _applyCode(),
                    decoration: InputDecoration(
                      hintText: 'Punya kode voucher?',
                      hintStyle: _t(12.5, color: _faint),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _applyCode,
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Pakai'),
                  ),
                ),
              ],
            ),
            if (_codeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_codeError!, style: _t(11.5, color: _red)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _option(PromoQuote q) {
    final p = q.promo;
    final selected = widget.applied?.promo.id == p.id;
    final locked = (p.code ?? '').isNotEmpty && !_unlocked.contains(p.id) && !selected;
    final subtitle = !q.usable
        ? q.blockedReason!
        : locked
            ? 'Masukkan kode ${p.code} · ${p.summaryDescription}'
            : 'Hemat ${_rp(q.discount)} · ${p.summaryDescription}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _greenBg : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: !q.usable
              ? null
              : () {
                  if (selected) {
                    widget.onChanged(null);
                  } else if (locked) {
                    setState(() => _codeError = 'Masukkan kode voucher untuk memakai "${p.title}".');
                  } else {
                    widget.onChanged(q);
                  }
                },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _green : _border),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : locked
                          ? Icons.lock_outline_rounded
                          : (q.usable ? Icons.radio_button_unchecked_rounded : p.type.icon),
                  size: 20,
                  color: selected ? _green : (q.usable ? _muted : const Color(0xFFCBD5E1)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.title} · ${p.type == ShopPromoType.freeDelivery ? 'Gratis Ongkir' : p.valueDisplay}',
                        style: _t(12.5, color: q.usable ? _ink : _faint, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: _t(11, color: q.usable ? _muted : _red)),
                    ],
                  ),
                ),
                if (selected)
                  Text('Lepas', style: _t(11.5, color: _muted, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
