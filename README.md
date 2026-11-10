# Washora

Washora adalah aplikasi marketplace laundry digital (Flutter) yang menghubungkan pelanggan dengan UMKM laundry terdekat berdasarkan harga dan jarak. Aplikasi ini memiliki dua peran: **pelanggan** dan **mitra (pemilik outlet)**.

Dikembangkan dalam program PMW PENS.

## Fitur

**Pelanggan**
- Pencarian laundry terdekat berbasis geolokasi dan peta
- Detail outlet, layanan, ulasan, dan promo
- Alur pemesanan, pilihan metode pembayaran (termasuk pembayaran QRIS), dan tracking status cucian
- Chat dengan outlet, riwayat pesanan, keanggotaan (membership), dan dompet (wallet)
- Pengajuan klaim kerusakan dengan bukti foto
- Notifikasi push

**Mitra / pemilik outlet**
- Dashboard dan manajemen pesanan
- Pengaturan outlet, promo, dan penanganan klaim
- Laporan pendapatan dengan ekspor PDF dan Excel
- Cetak dan pratinjau struk (PDF dan printer thermal ESC/POS)
- Chat dengan pelanggan dan tinjauan ulasan

## Teknologi

- Flutter dan Dart
- Supabase (autentikasi, database, Edge Function `send-push`)
- Firebase Cloud Messaging untuk notifikasi push
- `flutter_map` dan `latlong2` untuk peta dan lokasi
- `pdf`, `printing`, `excel`, `mobile_scanner` untuk struk, laporan, dan pemindaian QR

## Struktur proyek

| Folder / file | Isi |
|---|---|
| `lib/screens` | Halaman aplikasi (pelanggan dan mitra) |
| `lib/services` | Layanan: Supabase, auth, chat, notifikasi, laporan, wallet |
| `lib/models` | Model data |
| `lib/payments`, `lib/receipt` | Pembayaran QRIS dan pembuatan struk |
| `lib/widgets` | Komponen UI bersama |
| `supabase/functions/send-push` | Edge Function pengirim notifikasi push |
| `supabase_*.sql` | Skema dan migrasi database (mulai dari `supabase_install_all.sql`) |
| `test` | Unit test dan widget test |

## Menjalankan

1. Pasang Flutter SDK (Dart `^3.11.0`).
2. Jalankan `flutter pub get`.
3. Buat proyek Supabase, lalu jalankan `supabase_install_all.sql` dan skrip migrasi lainnya di SQL Editor.
4. Isi `lib/supabase_config.dart` dengan URL dan kunci publik proyek Anda.
5. Untuk notifikasi push, sesuaikan konfigurasi Firebase (`android/app/google-services.json`) dan atur secret `FCM_SERVICE_ACCOUNT` serta `PUSH_WEBHOOK_SECRET` pada Edge Function. Jangan pernah meng-commit file service account.
6. Jalankan dengan `flutter run`, dan uji dengan `flutter test`.
