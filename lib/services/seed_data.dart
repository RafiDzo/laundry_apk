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
            'name': 'Sukolilo Fresh Laundry',
            'rating': 4.9,
            'distance': '350m',
            'queue_text': 'ANTRIAN: 2 (CEPAT)',
            'address': 'Jl. Keputih Tegal Timur No. 12, Sukolilo, Surabaya',
            'open_hours': '08:00 - 21:00',
            'image_url': 'https://images.unsplash.com/photo-1577553698923-17f1a80ce5bc?w=500&auto=format&fit=crop&q=80',
            'price_per_kg': 10000,
            'services': [
              {'id': 's1', 'name': 'Cuci Kiloan', 'description': 'Regular wash & fold', 'price': 10000, 'unit': '/ kg', 'iconName': 'local_laundry_service'},
              {'id': 's2', 'name': 'Cuci Express', 'description': 'Selesai dalam 4 jam', 'price': 25000, 'unit': '/ kg', 'iconName': 'bolt'},
            ],
          },
          {
            'name': 'ITS Laundry Center',
            'rating': 4.2,
            'distance': '450m',
            'queue_text': 'ANTRIAN: 8 (SIBUK)',
            'address': 'Jl. Arief Rahman Hakim No. 55, Sukolilo, Surabaya',
            'open_hours': '07:00 - 22:00',
            'image_url': 'https://images.unsplash.com/photo-1635274605638-d44babc08a4f?w=500&auto=format&fit=crop&q=80',
            'price_per_kg': 8500,
            'services': [
              {'id': 's3', 'name': 'Cuci Kiloan Hemat', 'description': 'Regular wash (3 hari)', 'price': 8500, 'unit': '/ kg', 'iconName': 'local_laundry_service'},
              {'id': 's4', 'name': 'Setrika Saja', 'description': 'Layanan setrika rapi', 'price': 6000, 'unit': '/ kg', 'iconName': 'iron'},
            ],
          },
          {
            'name': 'Keputih Express Wash',
            'rating': 4.9,
            'distance': '150m',
            'queue_text': 'ANTRIAN: 1 (LANCAR)',
            'address': 'Jl. Keputih Tegal No. 7, Sukolilo, Surabaya',
            'open_hours': '24 Jam',
            'image_url': 'https://images.unsplash.com/photo-1604335398980-ededcadcc37d?w=500&auto=format&fit=crop&q=80',
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
