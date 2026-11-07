/// Penyusun struk/resi Washora untuk thermal printer 58mm (32 kolom) / 80mm (48 kolom).
///
/// Lapisan ini murni (tanpa Flutter/printer): data pesanan → daftar [ReceiptLine]
/// yang sudah dipotong per lebar kertas. Lapisan berikutnya mengubahnya menjadi
/// pratinjau layar, PDF, atau byte ESC/POS (tahap 2), jadi isi struk bisa diuji
/// tanpa perangkat.
library;

import '../models/order_model.dart';
import '../models/revenue_report.dart' show paymentLabel;

// ======================================================================
// DATA
// ======================================================================

enum PaperWidth {
  mm58(32, '58 mm'),
  mm80(48, '80 mm');

  final int columns;
  final String label;
  const PaperWidth(this.columns, this.label);
}

class ReceiptSettings {
  final PaperWidth width;
  final bool showQr;
  final String headerNote; // mis. "Buka 07.00-21.00" (opsional)
  final String footerNote; // mis. "Terima kasih telah mencuci di sini"

  const ReceiptSettings({
    this.width = PaperWidth.mm58,
    this.showQr = true,
    this.headerNote = '',
    this.footerNote = 'Terima kasih!',
  });
}

/// Semua angka diambil dari pesanan yang tersimpan di server (bukan dihitung ulang dari input kasir).
class ReceiptData {
  final OrderModel order;
  final String shopName;
  final String shopAddress;
  final String shopPhone;
  final String cashierName;
  final String? memberTier; // "Silver" / "Gold" / null
  final int claimWindowHours; // dari tingkat member, default 48
  final String? estimate; // mis. "1-2 Hari" dari durasi layanan outlet
  final DateTime? paidAt;
  final int? cashReceived;
  final bool isCopy;
  final DateTime printedAt;

  const ReceiptData({
    required this.order,
    required this.shopName,
    this.shopAddress = '',
    this.shopPhone = '',
    this.cashierName = '',
    this.memberTier,
    this.claimWindowHours = 48,
    this.estimate,
    this.paidAt,
    this.cashReceived,
    this.isCopy = false,
    required this.printedAt,
  });
}

// ======================================================================
// BARIS STRUK
// ======================================================================

enum RAlign { left, center, right }

sealed class ReceiptLine {
  const ReceiptLine();
}

/// Satu baris teks yang sudah pas lebar kertas
class TextLine extends ReceiptLine {
  final String text;
  final RAlign align;
  final bool bold;
  final bool large; // tinggi & lebar ganda (hanya untuk teks pendek)
  const TextLine(this.text, {this.align = RAlign.left, this.bold = false, this.large = false});
}

class DividerLine extends ReceiptLine {
  final String char;
  const DividerLine([this.char = '-']);
}

class QrLine extends ReceiptLine {
  final String data;
  const QrLine(this.data);
}

class FeedLine extends ReceiptLine {
  final int lines;
  const FeedLine([this.lines = 1]);
}

// ======================================================================
// UTIL TEKS
// ======================================================================

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ù': 'u',
  'ú': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ù': 'U',
  'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ñ': 'N', 'Ç': 'C', 'Ý': 'Y',
  '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '•': '-', '·': '-', '×': 'x',
};

/// Printer thermal generik hanya andal untuk ASCII. Huruf beraksen diganti padanannya,
/// karakter lain (emoji, aksara non-Latin) menjadi '?', agar kolom tidak bergeser.
String printable(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r >= 0x20 && r <= 0x7E) {
      b.write(ch);
    } else if (_accents.containsKey(ch)) {
      b.write(_accents[ch]);
    } else if (r == 0x09 || r == 0x0A || r == 0x0D) {
      b.write(' ');
    } else if (r >= 0xFE00 && r <= 0xFE0F || r == 0x200D) {
      // variation selector / zero-width joiner bagian dari emoji: lewati
    } else {
      b.write('?');
    }
  }
  return b.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Bungkus teks per kata; kata yang lebih panjang dari [width] dipotong paksa.
List<String> wrap(String text, int width) {
  final words = printable(text).split(' ').where((w) => w.isNotEmpty);
  final lines = <String>[];
  var cur = '';
  for (var w in words) {
    while (w.length > width) {
      if (cur.isNotEmpty) {
        lines.add(cur);
        cur = '';
      }
      lines.add(w.substring(0, width));
      w = w.substring(width);
    }
    if (cur.isEmpty) {
      cur = w;
    } else if (cur.length + 1 + w.length <= width) {
      cur = '$cur $w';
    } else {
      lines.add(cur);
      cur = w;
    }
  }
  if (cur.isNotEmpty) lines.add(cur);
  return lines.isEmpty ? [''] : lines;
}

/// Kiri & kanan dalam satu baris. Jika tidak muat, teks kiri dibungkus dan
/// teks kanan ditaruh rata kanan di baris terakhir.
List<String> twoColumns(String left, String right, int width) {
  final r = printable(right);
  final maxLeft = width - r.length - 1;
  if (maxLeft < 6) {
    return [...wrap(left, width), r.padLeft(width)];
  }
  final ls = wrap(left, maxLeft);
  return [
    ...ls.take(ls.length - 1),
    ls.last.padRight(width - r.length) + r,
  ];
}

String rp(num v) {
  final n = v.round();
  final s = n.abs().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return '${n < 0 ? '-' : ''}Rp $s';
}

String _qty(num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(1).replaceAll('.', ',');

const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
String _tgl(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_bulan[d.month - 1]} ${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String orderCode(String id) => id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

/// Nomor HP disamarkan di struk (struk bisa tertinggal / difoto orang lain)
String maskPhone(String p) {
  final d = p.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.length < 8) return d;
  return '${d.substring(0, 4)}****${d.substring(d.length - 3)}';
}

// ======================================================================
// BUILDER
// ======================================================================

class ReceiptBuilder {
  final ReceiptSettings settings;
  const ReceiptBuilder([this.settings = const ReceiptSettings()]);

  int get w => settings.width.columns;

  List<TextLine> _text(String s, {RAlign align = RAlign.left, bool bold = false}) =>
      [for (final l in wrap(s, w)) TextLine(l, align: align, bold: bold)];

  List<TextLine> _kv(String label, String value, {bool bold = false}) {
    // Label rata kiri lebar tetap agar titik dua sejajar: "Tanggal : ..."
    const lw = 9;
    final head = '${printable(label).padRight(lw).substring(0, lw)}: ';
    final lines = wrap(value, w - head.length);
    return [
      TextLine(head + lines.first, bold: bold),
      for (final l in lines.skip(1)) TextLine(' ' * head.length + l, bold: bold),
    ];
  }

  List<TextLine> _amount(String label, int value, {bool bold = false}) =>
      [for (final l in twoColumns(label, rp(value), w)) TextLine(l, bold: bold)];

  /// Rincian biaya diturunkan dari angka yang tersimpan di pesanan.
  static ({int subtotal, int serviceFee, int delivery, int discount, int points, int total}) amounts(OrderModel o) {
    final subtotal = o.items.fold<num>(0, (s, i) => s + i.price * i.qty).round();
    final discount = o.discountAmount;
    final rest = o.totalPrice + discount + o.pointsUsed - subtotal - o.serviceFee;
    return (
      subtotal: subtotal,
      serviceFee: o.serviceFee,
      delivery: rest > 0 ? rest : 0,
      discount: discount,
      points: o.pointsUsed,
      total: o.totalPrice,
    );
  }

  List<ReceiptLine> build(ReceiptData d) {
    final o = d.order;
    final a = amounts(o);
    final out = <ReceiptLine>[];

    if (d.isCopy) {
      out
        ..add(TextLine('*** SALINAN ***', align: RAlign.center, bold: true))
        ..add(const FeedLine());
    }

    // ── Header outlet ──
    final name = printable(d.shopName.isEmpty ? 'Outlet Laundry' : d.shopName).toUpperCase();
    if (name.length * 2 <= w) {
      out.add(TextLine(name, align: RAlign.center, bold: true, large: true));
    } else {
      out.addAll(_text(name, align: RAlign.center, bold: true));
    }
    out.add(TextLine('via Washora', align: RAlign.center));
    if (d.shopAddress.trim().isNotEmpty) out.addAll(_text(d.shopAddress, align: RAlign.center));
    if (d.shopPhone.trim().isNotEmpty) out.addAll(_text('Telp ${d.shopPhone}', align: RAlign.center));
    if (settings.headerNote.trim().isNotEmpty) out.addAll(_text(settings.headerNote, align: RAlign.center));
    out.add(const DividerLine());

    // ── Info pesanan ──
    out
      ..addAll(_kv('No.', '#${orderCode(o.id)}', bold: true))
      ..addAll(_kv('Tanggal', _tgl(o.createdAt)))
      ..addAll(_kv('Pelanggan', (o.customerName ?? '').trim().isEmpty ? 'Pelanggan' : o.customerName!));
    if ((o.customerPhone ?? '').trim().isNotEmpty) out.addAll(_kv('No. HP', maskPhone(o.customerPhone!)));
    if (d.cashierName.trim().isNotEmpty) out.addAll(_kv('Kasir', d.cashierName));
    if (d.memberTier != null) out.addAll(_kv('Member', d.memberTier!, bold: true));
    out.addAll(_kv('Layanan', o.isDropoff ? 'Antar sendiri' : 'Antar-jemput'));
    out.add(const DividerLine());

    // ── Item ──
    if (o.items.isEmpty) out.addAll(_text('(item tidak dicatat)'));
    for (final i in o.items) {
      out.addAll(_text(i.name, bold: true));
      final unit = i.unit.replaceAll('/', '').trim();
      // Rincian menjorok 2 spasi agar terbaca sebagai bagian dari nama layanan di atasnya
      final detail = '${_qty(i.qty)}${unit.isEmpty ? '' : ' $unit'} x ${rp(i.price)}';
      for (final l in twoColumns(detail, rp(i.price * i.qty), w - 2)) {
        out.add(TextLine('  $l'));
      }
    }
    out.add(const DividerLine());

    // ── Biaya ──
    out.addAll(_amount('Subtotal', a.subtotal));
    if (a.serviceFee > 0) out.addAll(_amount('Biaya layanan', a.serviceFee));
    if (!o.isDropoff) {
      if (o.memberFreeDelivery) {
        out.addAll([for (final l in twoColumns('Ongkir', 'Gratis (member)', w)) TextLine(l)]);
      } else if (a.delivery > 0) {
        out.addAll(_amount('Ongkir', a.delivery));
      } else {
        out.addAll([for (final l in twoColumns('Ongkir', 'Gratis', w)) TextLine(l)]);
      }
    }
    if (a.discount > 0) {
      out.addAll(_amount('Promo ${o.promoTitle ?? ''}'.trim(), -a.discount));
    }
    if (a.points > 0) out.addAll(_amount('Poin member', -a.points));
    out
      ..add(const DividerLine('='))
      ..addAll(_amount('TOTAL', a.total, bold: true))
      ..add(const DividerLine('='))
      ..addAll(_kv('Bayar', paymentLabel(o.paymentMethod)))
      ..addAll(_kv('Status', d.paidAt != null ? 'LUNAS' : 'BELUM LUNAS', bold: true));
    final cash = d.cashReceived;
    if (cash != null && cash > 0) {
      out
        ..addAll(_amount('Tunai', cash))
        ..addAll(_amount('Kembali', cash - a.total < 0 ? 0 : cash - a.total));
    }
    out.add(const DividerLine());

    // ── Ketentuan ──
    if (d.estimate != null && d.estimate!.trim().isNotEmpty) out.addAll(_text('Estimasi selesai: ${d.estimate}'));
    final claim = d.claimWindowHours % 24 == 0 && d.claimWindowHours >= 72
        ? '${d.claimWindowHours} jam (${d.claimWindowHours ~/ 24} hari)'
        : '${d.claimWindowHours} jam';
    out.addAll(_text('Klaim kerusakan paling lambat $claim setelah cucian diterima, lewat aplikasi Washora.'));

    // ── QR & penutup ──
    if (settings.showQr) {
      out
        ..add(const FeedLine())
        ..add(QrLine('WASHORA:${o.id}'))
        ..add(TextLine('Lacak di aplikasi: #${orderCode(o.id)}', align: RAlign.center));
    }
    out.add(const FeedLine());
    if (settings.footerNote.trim().isNotEmpty) out.addAll(_text(settings.footerNote, align: RAlign.center, bold: true));
    out.add(TextLine('Dicetak ${_tgl(d.printedAt)}', align: RAlign.center));
    if (d.isCopy) out.add(TextLine('*** SALINAN ***', align: RAlign.center, bold: true));
    out.add(const FeedLine(3));
    return out;
  }

  /// Representasi teks polos (monospace) — dipakai pratinjau, PDF & mode simulasi.
  /// Teks besar dihitung 2 kolom per huruf, sama seperti di printer.
  List<String> toText(List<ReceiptLine> lines) {
    final out = <String>[];
    for (final l in lines) {
      switch (l) {
        case TextLine():
          final len = l.large ? l.text.length * 2 : l.text.length;
          final pad = w - len;
          final left = switch (l.align) {
            RAlign.left => 0,
            RAlign.center => pad ~/ 2,
            RAlign.right => pad,
          };
          out.add(' ' * (left < 0 ? 0 : left) + (l.large ? l.text.split('').join(' ') : l.text));
        case DividerLine():
          out.add(l.char * w);
        case QrLine():
          out.add('[QR ${l.data}]');
        case FeedLine():
          for (var i = 0; i < l.lines; i++) {
            out.add('');
          }
      }
    }
    return out;
  }
}
