/// QRIS statis → dinamis (nominal terisi otomatis).
///
/// Diadaptasi dari github.com/verssache/qris-dinamis (MIT License, © Gidhan / verssache):
/// parse TLV EMVCo, ubah tag 01 menjadi "12" (dinamis), sisipkan tag 54 (nominal)
/// sebelum tag 58, lalu hitung ulang CRC16-CCITT (tag 63).
///
/// Catatan: hasilnya QRIS statis milik merchant yang diberi nominal — bukan QRIS
/// dinamis yang diterbitkan penyedia jasa pembayaran. Tidak ada konfirmasi
/// pembayaran otomatis; pemilik QRIS mengecek dana masuk lalu menandai lunas.
library;

class TlvElement {
  final String tag;
  final String value;
  final List<TlvElement>? children;
  const TlvElement(this.tag, this.value, [this.children]);
}

class QrisException implements Exception {
  final String message;
  QrisException(this.message);
  @override
  String toString() => message;
}

class Qris {
  Qris._();

  /// Tag 26–51 (info akun merchant) & 62 (data tambahan) berisi TLV bersarang
  static bool _nested(String tag) {
    final n = int.tryParse(tag) ?? -1;
    return (n >= 26 && n <= 51) || n == 62;
  }

  static List<TlvElement> parse(String data) {
    final out = <TlvElement>[];
    var pos = 0;
    while (pos + 4 <= data.length) {
      final tag = data.substring(pos, pos + 2);
      final len = int.tryParse(data.substring(pos + 2, pos + 4));
      if (len == null || pos + 4 + len > data.length) break;
      final value = data.substring(pos + 4, pos + 4 + len);
      out.add(TlvElement(tag, value, _nested(tag) ? parse(value) : null));
      pos += 4 + len;
    }
    return out;
  }

  /// CRC16-CCITT (poly 0x1021, awal 0xFFFF), 4 digit heksadesimal huruf besar
  static String crc16(String s) {
    var crc = 0xFFFF;
    for (final c in s.codeUnits) {
      crc ^= c << 8;
      for (var j = 0; j < 8; j++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  static String _tlv(String tag, String value) => '$tag${value.length.toString().padLeft(2, '0')}$value';

  /// Hasil pemeriksaan: null = valid, selain itu alasan tidak valid
  /// NMID (National Merchant ID) tercetak di stiker QRIS, mis. ID1026634963833A01.
  /// Bukan payload — tidak bisa dipakai membuat QR.
  static bool looksLikeNmid(String s) => RegExp(r'^ID\d{8,}[A-Z0-9]*$').hasMatch(s.trim().toUpperCase());

  static String? validate(String payload) {
    final s = payload.trim();
    if (s.isEmpty) return 'Teks QRIS kosong.';
    if (looksLikeNmid(s)) {
      return 'Ini NMID (nomor ID merchant di bawah gambar QRIS), bukan isi kode QRIS. '
          'Gunakan tombol Scan Kamera / Dari Galeri untuk membaca gambar QR-nya.';
    }
    if (!s.startsWith('000201')) return 'Bukan teks QRIS (harus diawali 000201).';
    if (s.length < 20) return 'Teks QRIS terlalu pendek.';
    final body = s.substring(0, s.length - 4);
    if (!body.endsWith('6304')) return 'Bagian CRC (6304) tidak ditemukan di akhir teks.';
    if (crc16(body) != s.substring(s.length - 4).toUpperCase()) {
      return 'Checksum QRIS tidak cocok. Pastikan teks disalin lengkap.';
    }
    final tags = parse(s).map((e) => e.tag).toSet();
    for (final t in ['00', '01', '52', '53', '58', '59', '60', '63']) {
      if (!tags.contains(t)) return 'Tag wajib $t tidak ada.';
    }
    if (!tags.any((t) => (int.tryParse(t) ?? 0) >= 26 && (int.tryParse(t) ?? 0) <= 51)) {
      return 'Info akun merchant (tag 26-51) tidak ada.';
    }
    return null;
  }

  static bool isValid(String payload) => validate(payload) == null;

  static String? _value(String payload, String tag) {
    for (final e in parse(payload.trim())) {
      if (e.tag == tag) return e.value;
    }
    return null;
  }

  static String merchantName(String payload) => _value(payload, '59')?.trim() ?? '';
  static String merchantCity(String payload) => _value(payload, '60')?.trim() ?? '';

  /// Statis/dinamis: tag 01 "11" = statis, "12" = dinamis
  static bool isStatic(String payload) => _value(payload, '01') == '11';

  /// Buat QRIS dengan nominal [amount] (Rupiah, bilangan bulat).
  static String withAmount(String payload, int amount) {
    final err = validate(payload);
    if (err != null) throw QrisException(err);
    if (amount <= 0) throw QrisException('Nominal harus lebih dari 0.');
    if (amount > 99999999) throw QrisException('Nominal terlalu besar.');

    final b = StringBuffer();
    var inserted = false;
    for (final e in parse(payload.trim())) {
      if (const {'54', '55', '56', '57', '63'}.contains(e.tag)) continue; // ditulis ulang
      if (e.tag == '01') {
        b.write(_tlv('01', '12'));
        continue;
      }
      if (e.tag == '58' && !inserted) {
        b.write(_tlv('54', '$amount'));
        inserted = true;
      }
      b.write(_tlv(e.tag, e.value));
    }
    if (!inserted) throw QrisException('Tag negara (58) tidak ditemukan.');
    final body = '${b}6304';
    return body + crc16(body);
  }

  /// Nominal yang tertanam di QRIS (tag 54), null jika statis
  static int? amountOf(String payload) => int.tryParse(_value(payload, '54') ?? '');
}
