/// Lapisan driver printer. Tahap 2 baru berisi [SimulatedPrinterDriver];
/// driver Bluetooth/USB/RawBT (tahap 3) mengikuti antarmuka yang sama
/// sehingga layar cetak tidak perlu tahu jenis koneksinya.
library;

import 'dart:typed_data';

import 'escpos_encoder.dart';
import 'receipt_builder.dart';

enum PrinterStatus { disconnected, connecting, connected, printing, error }

class PrinterException implements Exception {
  final String message;
  final String? hint; // saran tindakan untuk pengguna
  PrinterException(this.message, {this.hint});
  @override
  String toString() => message;
}

abstract class PrinterDriver {
  String get name;
  PrinterStatus get status;
  Future<void> connect();
  Future<void> disconnect();

  /// Kirim byte ESC/POS. Melempar [PrinterException] jika gagal.
  Future<void> write(Uint8List bytes);
}

/// Hasil decode satu job cetak (apa yang akan keluar di kertas)
class SimulatedJob {
  final List<String> paper; // baris teks seperti di kertas, QR ditulis "[QR data]"
  final int bytes;
  final int cuts;
  final bool drawerOpened;
  final DateTime at;
  const SimulatedJob({required this.paper, required this.bytes, required this.cuts, required this.drawerOpened, required this.at});
}

/// Printer simulasi: menerima byte ESC/POS lalu men-decode-nya kembali menjadi
/// teks, sehingga encoder & isi struk bisa diuji tanpa perangkat.
class SimulatedPrinterDriver implements PrinterDriver {
  final PaperWidth width;
  SimulatedPrinterDriver({this.width = PaperWidth.mm58});

  PrinterStatus _status = PrinterStatus.disconnected;
  final List<SimulatedJob> jobs = [];

  /// Untuk menguji penanganan error: job berikutnya gagal dengan pesan ini
  String? failNextWith;

  @override
  String get name => 'Printer simulasi ${width.label}';

  @override
  PrinterStatus get status => _status;

  @override
  Future<void> connect() async => _status = PrinterStatus.connected;

  @override
  Future<void> disconnect() async => _status = PrinterStatus.disconnected;

  @override
  Future<void> write(Uint8List bytes) async {
    if (_status != PrinterStatus.connected) {
      throw PrinterException('Printer belum tersambung.', hint: 'Sambungkan printer lalu coba lagi.');
    }
    final fail = failNextWith;
    if (fail != null) {
      failNextWith = null;
      _status = PrinterStatus.error;
      throw PrinterException(fail, hint: 'Periksa printer lalu tekan Coba lagi.');
    }
    _status = PrinterStatus.printing;
    jobs.add(decode(bytes, width));
    _status = PrinterStatus.connected;
  }

  /// Decode byte ESC/POS (subset yang dipakai [EscPosEncoder]) menjadi baris kertas.
  static SimulatedJob decode(Uint8List b, PaperWidth width) {
    final cols = width.columns;
    final paper = <String>[];
    var align = RAlign.left;
    var large = false;
    var cuts = 0;
    var drawer = false;
    final line = StringBuffer();

    void flush() {
      final text = line.toString();
      line.clear();
      final shown = large ? text.split('').join(' ') : text;
      final len = large ? text.length * 2 : text.length;
      final pad = cols - len;
      final left = switch (align) {
        RAlign.left => 0,
        RAlign.center => pad ~/ 2,
        RAlign.right => pad,
      };
      paper.add(' ' * (left < 0 ? 0 : left) + shown);
    }

    var i = 0;
    while (i < b.length) {
      final c = b[i];
      if (c == EscPos.esc && i + 1 < b.length) {
        final cmd = b[i + 1];
        switch (cmd) {
          case 0x40: // init
            align = RAlign.left;
            large = false;
            i += 2;
          case 0x74: // code page
            i += 3;
          case 0x61: // align
            align = switch (b[i + 2]) { 1 => RAlign.center, 2 => RAlign.right, _ => RAlign.left };
            i += 3;
          case 0x45: // bold (tidak tampak di teks)
            i += 3;
          case 0x64: // feed n
            if (line.isNotEmpty) flush();
            for (var k = 0; k < b[i + 2]; k++) {
              paper.add('');
            }
            i += 3;
          case 0x70: // laci kas
            drawer = true;
            i += 5;
          default:
            i += 2;
        }
      } else if (c == EscPos.gs && i + 1 < b.length) {
        final cmd = b[i + 1];
        if (cmd == 0x21) {
          large = b[i + 2] != 0;
          i += 3;
        } else if (cmd == 0x56) {
          cuts++;
          i += 4;
        } else if (cmd == 0x28 && b[i + 2] == 0x6B) {
          final len = b[i + 3] | (b[i + 4] << 8);
          final fn = b[i + 6];
          if (fn == 0x50) {
            // simpan data QR: 3 byte (cn fn m) + data
            final data = String.fromCharCodes(b.sublist(i + 8, i + 5 + len));
            paper.add('[QR $data]');
          }
          i += 5 + len;
        } else {
          i += 2;
        }
      } else if (c == EscPos.lf) {
        flush();
        i++;
      } else {
        line.writeCharCode(c);
        i++;
      }
    }
    if (line.isNotEmpty) flush();
    return SimulatedJob(paper: paper, bytes: b.length, cuts: cuts, drawerOpened: drawer, at: DateTime.now());
  }
}
