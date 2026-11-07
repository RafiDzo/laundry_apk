import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/order_model.dart';
import '../models/revenue_report.dart';
import '../utils/format_id.dart';

/// Ekspor Laporan Omzet ke PDF / Excel. Berjalan di web (unduhan browser)
/// dan Android/iOS (disimpan ke folder dokumen aplikasi/unduhan).
class ReportExport {
  static String _fileName(String shopName, RevenueReport r) {
    final slug = shopName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    String d(DateTime t) => '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
    final last = r.to.subtract(const Duration(days: 1));
    return 'omzet-${slug.isEmpty ? 'outlet' : slug}-${d(r.from)}-${d(last)}';
  }

  static String periodLabel(RevenueReport r) {
    final last = r.to.subtract(const Duration(days: 1));
    return awalHari(r.from) == awalHari(last) ? tanggal(r.from) : '${tanggal(r.from)} - ${tanggal(last)}';
  }

  static String _status(String s) => switch (statusGroup(s)) {
        StatusGroup.selesai => 'Selesai',
        StatusGroup.diproses => 'Diproses',
        StatusGroup.dibatalkan => 'Dibatalkan',
      };

  // ============================== EXCEL ==============================

  static Future<String> saveExcel({
    required String shopName,
    required RevenueReport report,
    required List<OrderModel> orders,
  }) async {
    final book = xl.Excel.createExcel();
    final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(defaultSheet, 'Ringkasan');

    xl.CellValue t(String v) => xl.TextCellValue(v);
    xl.CellValue n(int v) => xl.IntCellValue(v);

    final sum = book['Ringkasan'];
    sum.appendRow([t('Laporan Omzet $shopName')]);
    sum.appendRow([t('Periode'), t(periodLabel(report))]);
    sum.appendRow([]);
    sum.appendRow([t('Total Omzet'), n(report.total)]);
    sum.appendRow([t('Jumlah Transaksi'), n(report.count)]);
    sum.appendRow([t('Rata-rata per Transaksi'), n(report.average)]);
    sum.appendRow([t('Omzet Periode Sebelumnya'), n(report.prevTotal)]);
    sum.appendRow([]);
    sum.appendRow([t('Omzet per Hari')]);
    sum.appendRow([t('Tanggal'), t('Transaksi'), t('Omzet')]);
    for (final d in report.daily) {
      sum.appendRow([t(tanggal(d.day)), n(d.count), n(d.total)]);
    }
    sum.appendRow([]);
    sum.appendRow([t('Omzet per Layanan (harga item, belum termasuk ongkir)')]);
    sum.appendRow([t('Layanan'), t('Transaksi'), t('Omzet')]);
    for (final s in report.services) {
      sum.appendRow([t(s.name), n(s.count), n(s.total)]);
    }
    sum.appendRow([]);
    sum.appendRow([t('Omzet per Metode Pembayaran')]);
    sum.appendRow([t('Metode'), t('Transaksi'), t('Omzet')]);
    for (final p in report.payments) {
      sum.appendRow([t(p.name), n(p.count), n(p.total)]);
    }

    final trx = book['Transaksi'];
    trx.appendRow([
      t('No. Transaksi'), t('Tanggal'), t('Jam'), t('Pelanggan'), t('Layanan'),
      t('Metode Bayar'), t('Status'), t('Total'),
    ]);
    for (final o in orders) {
      trx.appendRow([
        t(nomorTransaksi(o.id)),
        t(tanggal(o.createdAt)),
        t(jam(o.createdAt)),
        t((o.customerName ?? '').trim().isEmpty ? 'Pelanggan' : o.customerName!.trim()),
        t(o.items.map((i) => '${i.name} (${angka(i.qty)}${i.unit.replaceAll('/', '').trim()})').join(', ')),
        t(paymentLabel(o.paymentMethod)),
        t(_status(o.status)),
        n(o.totalPrice),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) throw Exception('File Excel gagal dibuat.');
    return FileSaver.instance.saveFile(
      name: _fileName(shopName, report),
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  // =============================== PDF ===============================

  static Future<String> savePdf({
    required String shopName,
    required RevenueReport report,
    required List<OrderModel> orders,
  }) async {
    final doc = pw.Document(title: 'Laporan Omzet $shopName', author: 'Washora');
    const brand = PdfColor.fromInt(0xFF0077B6);
    const muted = PdfColor.fromInt(0xFF64748B);
    const line = PdfColor.fromInt(0xFFE2E8F0);

    pw.Widget kpi(String label, String value) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: muted)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        );

    pw.Widget table(List<String> head, List<List<String>> rows, {Set<int> rightCols = const {}}) => pw.TableHelper.fromTextArray(
          headers: head,
          data: rows,
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: brand),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {for (final c in rightCols) c: pw.Alignment.centerRight},
          border: pw.TableBorder.all(color: line, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        );

    final change = RevenueReport.change(report.total, report.prevTotal);
    final changeText = change == null
        ? 'Belum ada data periode sebelumnya'
        : '${change >= 0 ? 'Naik' : 'Turun'} ${change.abs().toStringAsFixed(1)}% dibanding periode sebelumnya (${rupiah(report.prevTotal)})';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
        ),
        build: (ctx) => [
          pw.Text('Laporan Omzet', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: brand)),
          pw.Text('$shopName  |  ${periodLabel(report)}', style: const pw.TextStyle(fontSize: 10, color: muted)),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            kpi('Total Omzet', rupiah(report.total)),
            pw.SizedBox(width: 8),
            kpi('Jumlah Transaksi', '${report.count}'),
            pw.SizedBox(width: 8),
            kpi('Rata-rata / Transaksi', rupiah(report.average)),
          ]),
          pw.SizedBox(height: 6),
          pw.Text(changeText, style: const pw.TextStyle(fontSize: 9, color: muted)),
          pw.SizedBox(height: 18),
          pw.Text('Omzet per Hari', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          table(['Tanggal', 'Transaksi', 'Omzet'],
              report.daily.map((d) => [tanggal(d.day), '${d.count}', rupiah(d.total)]).toList(),
              rightCols: {1, 2}),
          pw.SizedBox(height: 16),
          pw.Text('Omzet per Layanan', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('Dari harga item layanan, belum termasuk biaya layanan / ongkir.',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
          pw.SizedBox(height: 6),
          table(['Layanan', 'Transaksi', 'Omzet'],
              report.services.map((s) => [s.name, '${s.count}', rupiah(s.total)]).toList(),
              rightCols: {1, 2}),
          pw.SizedBox(height: 16),
          pw.Text('Omzet per Metode Pembayaran', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          table(['Metode', 'Transaksi', 'Omzet'],
              report.payments.map((p) => [p.name, '${p.count}', rupiah(p.total)]).toList(),
              rightCols: {1, 2}),
          pw.SizedBox(height: 16),
          pw.Text('Daftar Transaksi', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          table(
            ['No.', 'Waktu', 'Pelanggan', 'Metode', 'Status', 'Total'],
            orders
                .map((o) => [
                      nomorTransaksi(o.id),
                      '${tanggalPendek(o.createdAt)} ${jam(o.createdAt)}',
                      (o.customerName ?? '').trim().isEmpty ? 'Pelanggan' : o.customerName!.trim(),
                      paymentGroup(o.paymentMethod),
                      _status(o.status),
                      rupiah(o.totalPrice),
                    ])
                .toList(),
            rightCols: {5},
          ),
          pw.SizedBox(height: 8),
          pw.Text('Omzet dihitung dari pesanan yang tidak dibatalkan. Dibuat ${tanggalJam(DateTime.now())} dari aplikasi Washora.',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ),
    );

    final bytes = await doc.save();
    return FileSaver.instance.saveFile(
      name: _fileName(shopName, report),
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}
