import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop_model.dart';
import 'address_service.dart';

class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// Hitung jarak sungguhan antara alamat pengguna dan outlet.
///
/// Koordinat pengguna diambil dari alamat aktif (dipilih lewat peta), atau
/// dicari dari teks alamatnya via OpenStreetMap Nominatim. Koordinat outlet
/// diambil dari kolom latitude/longitude, atau dicari dari alamat outlet.
/// Hasil pencarian alamat disimpan di perangkat supaya tidak dicari ulang.
class GeoService {
  GeoService._();

  static const _cacheKey = 'geocode_cache_v1';
  static Map<String, List<double>>? _cache;
  static DateTime? _lastRequest;

  /// Jarak garis lurus (Haversine) dalam kilometer
  static double distanceKm(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) *
            math.cos(rad(b.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  /// "350 m", "1,2 km", "15 km"
  static String formatKm(double km) {
    if (km < 1) return '${(km * 1000 / 10).round() * 10} m';
    if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${km.round()} km';
  }

  static Future<Map<String, List<double>>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cache = decoded.map(
          (k, v) => MapEntry(
            k,
            (v as List).map((e) => (e as num).toDouble()).toList(),
          ),
        );
        return _cache!;
      }
    } catch (_) {}
    return _cache = {};
  }

  static Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_cache));
    } catch (_) {}
  }

  /// Cari koordinat dari teks alamat (Indonesia). null jika tidak ditemukan.
  static Future<GeoPoint?> geocode(String address) async {
    final q = address.trim();
    if (q.length < 4) return null;
    final key = q.toLowerCase();
    final cache = await _loadCache();
    final hit = cache[key];
    if (hit != null) return hit.isEmpty ? null : GeoPoint(hit[0], hit[1]);

    // Coba alamat lengkap, lalu versi lebih pendek (tanpa RT/RW, nomor, dll.)
    final candidates = <String>{q, _simplify(q)}
      ..removeWhere((c) => c.length < 4);
    for (final c in candidates) {
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(c)}&format=json&limit=1&countrycodes=id',
        );
        // Batas pemakaian Nominatim: maks. 1 permintaan per detik
        final wait = _lastRequest == null
            ? Duration.zero
            : const Duration(milliseconds: 1100) -
                  DateTime.now().difference(_lastRequest!);
        if (wait > Duration.zero) await Future.delayed(wait);
        _lastRequest = DateTime.now();
        final res = await http
            .get(uri, headers: {'User-Agent': 'WashoraApp/1.0'})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          if (list.isNotEmpty) {
            final p = GeoPoint(
              double.parse(list[0]['lat']),
              double.parse(list[0]['lon']),
            );
            cache[key] = [p.lat, p.lng];
            await _saveCache();
            return p;
          }
        }
      } catch (_) {
        return null; // jaringan bermasalah: jangan simpan sebagai "tidak ditemukan"
      }
    }
    cache[key] = [];
    await _saveCache();
    return null;
  }

  static String _simplify(String address) {
    return address
        .replaceAll(
          RegExp(r'RT\s*\d+\s*/?\s*RW\s*\d+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'(No\.?|Nomor|Kamar|Lt\.?|Lantai)\s*\w+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*,\s*,+'), ',')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim()
        .replaceAll(RegExp(r'^,|,$'), '')
        .trim();
  }

  /// Koordinat alamat aktif pengguna
  static Future<GeoPoint?> currentUserPoint() async {
    final addr = AddressService.currentAddressNotifier.value;
    if (addr.hasLocation) return GeoPoint(addr.latitude!, addr.longitude!);
    return geocode(addr.address);
  }

  static Future<GeoPoint?> shopPoint(ShopModel shop) async {
    if (shop.hasLocation) return GeoPoint(shop.latitude!, shop.longitude!);
    if (shop.address.isEmpty) return null;
    return geocode(shop.address);
  }

  /// Jarak (km) setiap outlet dari pengguna, key = id outlet.
  /// Outlet yang lokasinya tidak diketahui tidak dimasukkan.
  static Future<Map<String, double>> distancesFor(List<ShopModel> shops) async {
    final me = await currentUserPoint();
    if (me == null) return {};
    final result = <String, double>{};
    for (final shop in shops) {
      final p = await shopPoint(shop);
      if (p != null) result[shop.id] = distanceKm(me, p);
    }
    return result;
  }
}
