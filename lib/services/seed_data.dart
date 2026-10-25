import 'package:supabase_flutter/supabase_flutter.dart';

class SeedData {
  static Future<void> seedShopsIfEmpty() async {
    try {
      final db = Supabase.instance.client;
      final result = await db.from('shops').select('id').limit(1);

      if (result.isEmpty) {
        // Data kosong, lakukan seeding
        final List<Map<String, dynamic>> initialShops = [
          {
            'name': 'CleanPro Kemang',
            'rating': 4.9,
            'distance': '350m',
            'queue_text': 'ANTRIAN: 2 (CEPAT)',
            'address': 'Jl. Kemang Raya No. 12A',
            'open_hours': '08:00 - 21:00',
            'image_url': 'https://lh3.googleusercontent.com/aida-public/AB6AXuBW9leL5JQT0NDVhvKJuPhytYI88GirFMuMwGe3lsthjoAEBqLmBn7vNge0fcmSKfxOZ4zA9PI3TKh5WgJjQ8vUZpyd9o02b8NCC2TnqbYYcVfa9KvQ8eyJDY151z4mqY4kEjhjf63dbas7B0JD2JMAHVgmYWv4EidKnv_bcooludI6bMBw_ATi2mbC5M2VaxyRoPr3aVg5oUo6NXyxOJF2kGqFbSDATtn9H-oPLTyHAgWy66ebd2KkMEpUP7BjZE7L4OfJTcTTxRM',
            'price_per_kg': 10000,
            'services': [
              {'id': 's1', 'name': 'Cuci Kiloan', 'description': 'Regular wash & fold', 'price': 10000, 'unit': '/ kg', 'iconName': 'local_laundry_service'},
              {'id': 's2', 'name': 'Cuci Express', 'description': 'Selesai dalam 4 jam', 'price': 25000, 'unit': '/ kg', 'iconName': 'bolt'},
            ],
          },
          {
            'name': 'Lavender Laundry',
            'rating': 4.2,
            'distance': '450m',
            'queue_text': 'ANTRIAN: 8 (SIBUK)',
            'address': 'Jl. Pangeran Antasari No. 88',
            'open_hours': '07:00 - 22:00',
            'image_url': 'https://lh3.googleusercontent.com/aida-public/AB6AXuBspHlATXq6VyPPRzCi0-Sq6JlupwTIMdJelS31CjG8_GYeNr2G29S7zyZHV-g-gZMQp1rDbc7SP9AKF2Iv6xCj33mRhWh9FDhVExwBAWojl65lM9rx7LnNAIFGxyESn1pfkgqOT7gYn06AA_R2PYJNY-FqWpnfW7KLb9CvZw66kDy5F9CxKfCE3SJ72uKn1yWfPGMZFdT2qn6ofCjTPGcKEAOcCVb-k3aA27HJmFD8dGsxTxBVUQCWVwkWgOzxd2uNGKDCBi1TsUk',
            'price_per_kg': 8500,
            'services': [
              {'id': 's3', 'name': 'Cuci Kiloan Hemat', 'description': 'Regular wash (3 hari)', 'price': 8500, 'unit': '/ kg', 'iconName': 'local_laundry_service'},
              {'id': 's4', 'name': 'Setrika Saja', 'description': 'Layanan setrika rapi', 'price': 6000, 'unit': '/ kg', 'iconName': 'iron'},
            ],
          },
          {
            'name': 'QuickWash Express',
            'rating': 4.9,
            'distance': '150m',
            'queue_text': 'ANTRIAN: 1 (LANCAR)',
            'address': 'Jl. Bangka Raya No. 15',
            'open_hours': '24 Jam',
            'image_url': 'https://lh3.googleusercontent.com/aida-public/AB6AXuBMc96qEnDZpcm041SQyKSHIn6dcocaOdzIx7pHY6s65ykMB5nQnx1YJrUw_zZXO09mggxl303BvItzd8MeLLA0cgpL_TfMtXlkbEYbGYhxbECwVWBblrB2GvvBS4hB7ATAy52OPwlu0tSKP2Ax57VwgRIVUGPcDlzxzHT5Xco8cWGpqqC-jXtsLE_YoTFYNBOTLVvUpTrF45yJMpgy5V44ZEoamoe7fz6Hobxj9jIoZObZx67CfM6ZSXJlHrXnratH28_6aY0IQWE',
            'price_per_kg': 12000,
            'services': [
              {'id': 's5', 'name': 'Cuci Kiloan Premium', 'description': 'Deterjen premium & pelembut ekstra', 'price': 12000, 'unit': '/ kg', 'iconName': 'local_laundry_service'},
              {'id': 's6', 'name': 'Cuci Satuan', 'description': 'Cuci jas, gaun, boneka, dll.', 'price': 35000, 'unit': '/ pcs', 'iconName': 'dry_cleaning'},
            ],
          },
        ];

        await db.from('shops').insert(initialShops);
        print('✅ Seeding data toko berhasil dilakukan!');
      } else {
        print('ℹ️ Data toko sudah ada di Supabase, melewati proses seeding.');
      }
    } catch (e) {
      print('❌ Error saat seeding data: $e');
    }
  }
}
