import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../receipt/escpos_encoder.dart';
import '../receipt/printer_driver.dart';
import '../receipt/receipt_builder.dart';
import '../receipt/receipt_pdf.dart';
import '../receipt/receipt_preview.dart';
import '../receipt/receipt_service.dart';
import '../widgets/quick_snackbar.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _brand = Color(0xFF0077B6);
const _green = Color(0xFF15803D);
const _red = Color(0xFFB91C1C);

TextStyle _t(double s, {Color c = _ink, FontWeight w = FontWeight.w500}) =>
    GoogleFonts.inter(fontSize: s, fontWeight: w, color: c);

/// Cetak Resi (mitra) — tahap 1: pratinjau 58/80 mm, cetak lewat dialog cetak
/// sistem/browser, dan unduh PDF. Printer Bluetooth/USB langsung menyusul.
class ReceiptPrintScreen extends StatefulWidget {
  final String orderId;
  final bool isCopy;
  const ReceiptPrintScreen({super.key, required this.orderId, this.isCopy = false});

  @override
  State<ReceiptPrintScreen> createState() => _ReceiptPrintScreenState();
}

class _ReceiptPrintScreenState extends State<ReceiptPrintScreen> {
  final _service = ReceiptService();
  ReceiptData? _data;
  String? _error;
  ReceiptSettings _settings = const ReceiptSettings();
  late bool _copy = widget.isCopy;
  bool _busy = false;

  static const _kWidth = 'receipt_width';
  static const _kQr = 'receipt_qr';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _load();
  }

  Future<void> _loadSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _settings = ReceiptSettings(
            width: p.getString(_kWidth) == '80' ? PaperWidth.mm80 : PaperWidth.mm58,
            showQr: p.getBool(_kQr) ?? true,
          ));
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kWidth, _settings.width == PaperWidth.mm80 ? '80' : '58');
      await p.setBool(_kQr, _settings.showQr);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _service.load(widget.orderId, isCopy: _copy);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  ReceiptBuilder get _builder => ReceiptBuilder(_settings);

  List<ReceiptLine> _lines(ReceiptData d) => _builder.build(ReceiptData(
        order: d.order,
        shopName: d.shopName,
        shopAddress: d.shopAddress,
        shopPhone: d.shopPhone,
        cashierName: d.cashierName,
        memberTier: d.memberTier,
        claimWindowHours: d.claimWindowHours,
        estimate: d.estimate,
        paidAt: d.paidAt,
        cashReceived: d.cashReceived,
        isCopy: _copy,
        printedAt: DateTime.now(),
      ));

  void _snack(String m, {Color? c}) =>
      ScaffoldMessenger.of(context).showQuickSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  String get _fileName => 'struk-${orderCode(widget.orderId)}${_copy ? '-salinan' : ''}';

  Future<void> _print() async {
    final d = _data;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildReceiptPdf(_lines(d), _settings);
      final ok = await Printing.layoutPdf(name: _fileName, onLayout: (_) async => bytes);
      if (mounted && ok) _snack('Struk dikirim ke printer.', c: _green);
    } catch (e) {
      if (mounted) _snack('Dialog cetak tidak bisa dibuka: $e. Coba "Unduh PDF".', c: _red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final d = _data;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildReceiptPdf(_lines(d), _settings);
      await FileSaver.instance.saveFile(name: _fileName, bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
      if (mounted) _snack('PDF struk tersimpan.', c: _green);
    } catch (e) {
      if (mounted) _snack('PDF gagal disimpan: $e', c: _red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Kirim struk ke printer simulasi: byte ESC/POS asli di-decode kembali menjadi
  /// kertas, sehingga hasil cetak bisa diperiksa tanpa perangkat.
  Future<void> _simulate() async {
    final d = _data;
    if (d == null) return;
    final printer = SimulatedPrinterDriver(width: _settings.width);
    final bytes = EscPosEncoder(width: _settings.width).encode(_lines(d));
    try {
      await printer.connect();
      await printer.write(bytes);
    } on PrinterException catch (e) {
      _snack(e.message, c: _red);
      return;
    }
    final job = printer.jobs.last;
    if (!mounted) return;
    final hex = bytes.take(48).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Hasil printer simulasi', style: GoogleFonts.quicksand(fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 4),
            Text('${printer.name} · ${job.bytes} byte ESC/POS · ${job.cuts}× potong kertas',
                style: _t(12, c: _muted)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  job.paper.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Courier New', 'Courier'], fontSize: 12, height: 1.3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('48 byte pertama', style: _t(12, w: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(hex, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: _muted)),
          ],
        ),
      ),
    );
  }

  Future<void> _markPaid() async {
    final d = _data;
    if (d == null) return;
    final isCash = const {'cash', 'cod', 'tunai'}.contains(d.order.paymentMethod.toLowerCase());
    final ctrl = TextEditingController(text: isCash ? '${d.order.totalPrice}' : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai lunas?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total ${rp(d.order.totalPrice)}'),
            if (isCash) ...[
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Uang diterima (tunai)', prefixText: 'Rp '),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lunas')),
        ],
      ),
    );
    final cash = int.tryParse(ctrl.text);
    ctrl.dispose();
    if (confirmed != true) return;
    if (isCash && cash != null && cash < d.order.totalPrice) {
      _snack('Uang diterima kurang dari total.', c: _red);
      return;
    }
    try {
      await _service.markPaid(widget.orderId, cashReceived: isCash ? cash : null);
      await _load();
      if (mounted) _snack('Pesanan ditandai lunas.', c: _green);
    } catch (e) {
      if (mounted) _snack(e.toString(), c: _red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cetak Resi', style: GoogleFonts.quicksand(fontSize: 18, fontWeight: FontWeight.w700, color: _ink)),
            Text('Pesanan #${orderCode(widget.orderId)}', style: _t(11.5, c: _muted)),
          ],
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.receipt_long_outlined, size: 36, color: _red),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center, style: _t(13)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Coba lagi')),
                ]),
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _controls(d),
                    const SizedBox(height: 14),
                    ReceiptPreview(lines: _lines(d), settings: _settings),
                    const SizedBox(height: 12),
                    Text(
                      'Tahap ini mencetak lewat dialog cetak sistem: pilih printer thermal yang sudah terpasang di '
                      'perangkat, atau "Simpan sebagai PDF". Sambungan Bluetooth/USB langsung ke printer menyusul.',
                      textAlign: TextAlign.center,
                      style: _t(11.5, c: _muted),
                    ),
                  ],
                ),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _download,
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Unduh PDF'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _print,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.print_rounded, size: 18),
                        label: Text(_copy ? 'Cetak Salinan' : 'Cetak Resi'),
                        style: FilledButton.styleFrom(backgroundColor: _brand, minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _controls(ReceiptData d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Lebar kertas', style: _t(13, w: FontWeight.w700)),
              const Spacer(),
              SegmentedButton<PaperWidth>(
                segments: [for (final w in PaperWidth.values) ButtonSegment(value: w, label: Text(w.label))],
                selected: {_settings.width},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  setState(() => _settings = ReceiptSettings(width: v.first, showQr: _settings.showQr));
                  _saveSettings();
                },
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Tampilkan QR pesanan', style: _t(13, w: FontWeight.w600)),
            value: _settings.showQr,
            onChanged: (v) {
              setState(() => _settings = ReceiptSettings(width: _settings.width, showQr: v));
              _saveSettings();
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Tandai sebagai SALINAN', style: _t(13, w: FontWeight.w600)),
            subtitle: Text('Untuk cetak ulang', style: _t(11.5, c: _muted)),
            value: _copy,
            onChanged: (v) => setState(() => _copy = v),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _simulate,
              icon: const Icon(Icons.terminal_rounded, size: 18),
              label: const Text('Uji di printer simulasi (ESC/POS)'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero),
            ),
          ),
          const Divider(height: 16),
          Row(
            children: [
              Icon(d.paidAt != null ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  size: 18, color: d.paidAt != null ? _green : const Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(d.paidAt != null ? 'Status bayar: Lunas' : 'Status bayar: Belum lunas',
                    style: _t(13, w: FontWeight.w700)),
              ),
              if (d.paidAt == null)
                TextButton(
                  onPressed: _markPaid,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: const Text('Tandai lunas'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
