/// Format angka & tanggal gaya Indonesia, dipakai halaman laporan & riwayat.
library;

const List<String> kBulanSingkat = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const List<String> kHariSingkat = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Rp 1.250.000 (minus ditulis -Rp 5.000)
String rupiah(num value) {
  final v = value.round();
  final digits = v.abs().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
  return '${v < 0 ? '-' : ''}Rp $digits';
}

/// Versi ringkas untuk label grafik: Rp 850rb, Rp 1,2jt
String rupiahRingkas(num value) {
  final v = value.abs();
  if (v >= 1000000) {
    final jt = v / 1000000;
    return 'Rp ${jt.toStringAsFixed(jt >= 10 ? 0 : 1).replaceAll('.', ',')}jt';
  }
  if (v >= 1000) return 'Rp ${(v / 1000).round()}rb';
  return 'Rp ${v.round()}';
}

/// 07 Nov 2026
String tanggal(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${kBulanSingkat[d.month - 1]} ${d.year}';

/// 07 Nov
String tanggalPendek(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${kBulanSingkat[d.month - 1]}';

/// 14:05
String jam(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 07 Nov 2026, 14:05
String tanggalJam(DateTime d) => '${tanggal(d)}, ${jam(d)}';

/// 3,5 (desimal pakai koma, bilangan bulat tanpa koma)
String angka(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// "2 jam 15 mnt", "3 hari 4 jam"
String durasi(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes} mnt';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} jam' : '${d.inHours} jam $m mnt';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} hari' : '${d.inDays} hari $h jam';
}

DateTime awalHari(DateTime d) => DateTime(d.year, d.month, d.day);

/// Nomor transaksi yang sama dengan dashboard mitra (8 karakter pertama id)
String nomorTransaksi(String orderId) =>
    orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
