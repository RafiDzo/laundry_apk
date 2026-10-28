import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/location_screen.dart';

class AddressItem {
  final String id;
  final String label;
  final String address;
  final String note;
  final bool isDefault;

  const AddressItem({
    required this.id,
    required this.label,
    required this.address,
    this.note = '',
    this.isDefault = false,
  });

  IconData get icon {
    final lower = label.toLowerCase();
    if (lower.contains('kantor') || lower.contains('office') || lower.contains('tower')) {
      return Icons.business_rounded;
    } else if (lower.contains('kos') || lower.contains('kost')) {
      return Icons.apartment_rounded;
    } else if (lower.contains('apartemen') || lower.contains('condo')) {
      return Icons.location_city_rounded;
    } else if (lower.contains('kampus') || lower.contains('sekolah')) {
      return Icons.school_rounded;
    }
    return Icons.home_rounded;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'address': address,
    'note': note,
    'isDefault': isDefault ? 'true' : 'false',
  };

  factory AddressItem.fromMap(Map<String, dynamic> map) => AddressItem(
    id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
    label: map['label']?.toString() ?? 'Rumah',
    address: map['address']?.toString() ?? 'Jl. Merdeka No. 12, RT 02 / RW 05, Menteng',
    note: map['note']?.toString() ?? '',
    isDefault: map['isDefault'] == 'true' || map['isDefault'] == true,
  );

  AddressItem copyWith({
    String? id,
    String? label,
    String? address,
    String? note,
    bool? isDefault,
  }) => AddressItem(
    id: id ?? this.id,
    label: label ?? this.label,
    address: address ?? this.address,
    note: note ?? this.note,
    isDefault: isDefault ?? this.isDefault,
  );
}

class AddressService {
  static const String _prefAddressKey = 'pref_address';
  static const String _prefSavedAddressesKey = 'pref_saved_addresses';

  static final List<AddressItem> defaultAddresses = [
    const AddressItem(
      id: 'addr_1',
      label: 'Rumah',
      address: 'Jl. Merdeka No. 12, RT 02 / RW 05, Menteng',
      note: 'Titip di satpam atau pencet bel pintu pagar hitam',
      isDefault: true,
    ),
    const AddressItem(
      id: 'addr_2',
      label: 'Kos Putra Washora',
      address: 'Jl. Belimbing No. 4A, Kamar 07, Sukolilo',
      note: 'Kamar lantai 2, gantung di depan pintu',
      isDefault: false,
    ),
    const AddressItem(
      id: 'addr_3',
      label: 'Kantor Cyber Tower',
      address: 'Gedung Cyber Lt. 3, Jl. Kuningan Barat No. 8',
      note: 'Serahkan ke resepsionis lobi utama',
      isDefault: false,
    ),
  ];

  static final ValueNotifier<AddressItem> currentAddressNotifier =
      ValueNotifier<AddressItem>(defaultAddresses[0]);

  static final ValueNotifier<List<AddressItem>> addressesNotifier =
      ValueNotifier<List<AddressItem>>(List.from(defaultAddresses));

  static bool _initialized = false;

  /// Inisialisasi data alamat dari SharedPreferences
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefSavedAddressesKey);
      List<AddressItem> list = [];

      if (savedJson != null && savedJson.isNotEmpty) {
        final decoded = jsonDecode(savedJson) as List;
        list = decoded
            .map((item) => AddressItem.fromMap(Map<String, dynamic>.from(item as Map)))
            .toList();
      }

      if (list.isEmpty) {
        list = List.from(defaultAddresses);
        await prefs.setString(
          _prefSavedAddressesKey,
          jsonEncode(list.map((e) => e.toMap()).toList()),
        );
      }

      final savedPrimary = prefs.getString(_prefAddressKey);
      AddressItem? primary;
      if (savedPrimary != null && savedPrimary.isNotEmpty) {
        primary = list.firstWhere(
          (a) =>
              savedPrimary.contains(a.label) ||
              savedPrimary.contains(a.address) ||
              a.address.contains(savedPrimary),
          orElse: () => list.firstWhere(
            (a) => a.isDefault,
            orElse: () => list.first,
          ),
        );
      } else {
        primary = list.firstWhere((a) => a.isDefault, orElse: () => list.first);
      }

      addressesNotifier.value = list;
      currentAddressNotifier.value = primary;
      _initialized = true;
    } catch (e) {
      // Fallback
      addressesNotifier.value = List.from(defaultAddresses);
      currentAddressNotifier.value = defaultAddresses[0];
      _initialized = true;
    }
  }

  /// Memilih alamat aktif sebagai alamat utama
  static Future<void> selectAddress(AddressItem selected) async {
    final updatedList = addressesNotifier.value.map((item) {
      return item.copyWith(isDefault: item.id == selected.id);
    }).toList();

    final newPrimary = selected.copyWith(isDefault: true);
    addressesNotifier.value = updatedList;
    currentAddressNotifier.value = newPrimary;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefAddressKey,
      '${newPrimary.label} • ${newPrimary.address}',
    );
    await prefs.setString(
      _prefSavedAddressesKey,
      jsonEncode(updatedList.map((e) => e.toMap()).toList()),
    );
  }

  /// Menambah alamat baru
  static Future<void> addAddress(
    AddressItem newItem, {
    bool setAsDefault = false,
  }) async {
    final currentList = List<AddressItem>.from(addressesNotifier.value);
    final itemToAdd = newItem.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isDefault: setAsDefault || currentList.isEmpty,
    );

    if (itemToAdd.isDefault) {
      for (int i = 0; i < currentList.length; i++) {
        currentList[i] = currentList[i].copyWith(isDefault: false);
      }
    }

    currentList.add(itemToAdd);
    addressesNotifier.value = currentList;

    if (itemToAdd.isDefault) {
      currentAddressNotifier.value = itemToAdd;
    }

    final prefs = await SharedPreferences.getInstance();
    if (itemToAdd.isDefault) {
      await prefs.setString(
        _prefAddressKey,
        '${itemToAdd.label} • ${itemToAdd.address}',
      );
    }
    await prefs.setString(
      _prefSavedAddressesKey,
      jsonEncode(currentList.map((e) => e.toMap()).toList()),
    );
  }

  /// Menghapus alamat
  static Future<void> deleteAddress(String id) async {
    final currentList = List<AddressItem>.from(addressesNotifier.value);
    final index = currentList.indexWhere((a) => a.id == id);
    if (index == -1) return;

    final wasDefault = currentList[index].isDefault;
    currentList.removeAt(index);

    if (currentList.isNotEmpty && wasDefault) {
      currentList[0] = currentList[0].copyWith(isDefault: true);
      currentAddressNotifier.value = currentList[0];
    }

    addressesNotifier.value = currentList;

    final prefs = await SharedPreferences.getInstance();
    if (currentList.isNotEmpty) {
      await prefs.setString(
        _prefAddressKey,
        '${currentAddressNotifier.value.label} • ${currentAddressNotifier.value.address}',
      );
    }
    await prefs.setString(
      _prefSavedAddressesKey,
      jsonEncode(currentList.map((e) => e.toMap()).toList()),
    );
  }

  /// Mengatur alamat dari peta / string manual
  static Future<void> setFromRawAddress({
    required String label,
    required String address,
    String note = '',
  }) async {
    final newItem = AddressItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      address: address,
      note: note,
      isDefault: true,
    );
    await addAddress(newItem, setAsDefault: true);
  }

  // ══════════════════════════════════════════════════════════
  //  MODAL BOTTOM SHEET PEMILIHAN ALAMAT
  // ══════════════════════════════════════════════════════════
  static void showAddressPickerSheet(
    BuildContext context, {
    Function(AddressItem)? onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x260F172A),
                    blurRadius: 30,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: ValueListenableBuilder<List<AddressItem>>(
                    valueListenable: addressesNotifier,
                    builder: (context, addresses, _) {
                      final current = currentAddressNotifier.value;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Grab Handle
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Header Row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: Color(0xFF0077E6),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pilih Alamat Antar / Jemput',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tentukan lokasi kurir untuk menjemput cucian',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: const Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFF64748B),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Tombol Cepat: Pilih Lewat Peta
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LocationScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.map_rounded,
                                      color: Color(0xFF16A34A),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pilih Titik di Peta Langsung',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: const Color(0xFF15803D),
                                          ),
                                        ),
                                        Text(
                                          'Geser pin atau cari titik alamat di peta interaktif',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: const Color(0xFF166534),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF16A34A),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Text(
                            'ALAMAT TERSIMPAN',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Scrollable list of saved addresses
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(ctx).size.height * 0.38,
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: addresses.map((item) {
                                  final isSelected = item.id == current.id;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      onTap: () {
                                        selectAddress(item);
                                        onSelected?.call(item);
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Lokasi pengantaran diubah ke ${item.label}',
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: const Color(0xFF0077E6),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFEFF6FF)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFF0077E6)
                                                : const Color(0xFFE2E8F0),
                                            width: isSelected ? 2 : 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isSelected
                                                  ? const Color(0xFF0077E6).withValues(alpha: 0.08)
                                                  : const Color(0xFF0F172A).withValues(alpha: 0.03),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(9),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? const Color(0xFF0077E6)
                                                    : const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                item.icon,
                                                color: isSelected
                                                    ? Colors.white
                                                    : const Color(0xFF64748B),
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        item.label,
                                                        style: GoogleFonts.plusJakartaSans(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w700,
                                                          color: const Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                      if (isSelected) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF0077E6),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            'Utama',
                                                            style: GoogleFonts.plusJakartaSans(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    item.address,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 12,
                                                      color: const Color(0xFF475569),
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                  if (item.note.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.sticky_note_2_rounded,
                                                          size: 13,
                                                          color: Color(0xFF94A3B8),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            item.note,
                                                            style: GoogleFonts.plusJakartaSans(
                                                              fontSize: 11,
                                                              color: const Color(0xFF64748B),
                                                              fontStyle: FontStyle.italic,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isSelected)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF0077E6),
                                                size: 22,
                                              )
                                            else
                                              Icon(
                                                Icons.radio_button_unchecked_rounded,
                                                color: const Color(0xFFCBD5E1),
                                                size: 22,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Tombol Tambah Alamat Baru
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                showAddAddressSheet(context);
                              },
                              icon: const Icon(
                                Icons.add_rounded,
                                color: Color(0xFF0077E6),
                                size: 20,
                              ),
                              label: Text(
                                'Tambah Alamat Baru',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: const Color(0xFF0077E6),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(
                                  color: Color(0xFF0077E6),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════
  //  MODAL TAMBAH ALAMAT BARU
  // ══════════════════════════════════════════════════════════
  static void showAddAddressSheet(BuildContext context) {
    final labelController = TextEditingController();
    final addressController = TextEditingController();
    final noteController = TextEditingController();
    bool makeDefault = addressesNotifier.value.isEmpty;
    String selectedCategory = 'Rumah';

    final categories = [
      {'name': 'Rumah', 'icon': Icons.home_rounded},
      {'name': 'Kos', 'icon': Icons.apartment_rounded},
      {'name': 'Kantor', 'icon': Icons.business_rounded},
      {'name': 'Apartemen', 'icon': Icons.location_city_rounded},
      {'name': 'Lainnya', 'icon': Icons.place_rounded},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x260F172A),
                        blurRadius: 30,
                        offset: Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        14,
                        20,
                        24 + MediaQuery.of(ctx).viewInsets.bottom,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Grab Handle
                            Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCBD5E1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.add_location_alt_rounded,
                                    color: Color(0xFF0077E6),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Tambah Alamat Baru',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF64748B),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Kategori Alamat Chips
                            Text(
                              'Kategori Alamat',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: categories.map((cat) {
                                final isSelected = selectedCategory == cat['name'];
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      selectedCategory = cat['name'] as String;
                                      if (labelController.text.isEmpty ||
                                          categories.any((c) => c['name'] == labelController.text)) {
                                        labelController.text = selectedCategory;
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF0077E6)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          cat['icon'] as IconData,
                                          size: 15,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          cat['name'] as String,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),

                            // Label Nama
                            Text(
                              'Nama / Label Alamat',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: labelController,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Contoh: Rumah, Kos Putri, Kantor Menteng',
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Alamat Lengkap
                            Text(
                              'Alamat Lengkap',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: addressController,
                              maxLines: 3,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Nama jalan, nomor rumah, RT/RW, kelurahan, kecamatan',
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Catatan untuk Kurir
                            Text(
                              'Catatan untuk Kurir (Opsional)',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: noteController,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'Contoh: Titip satpam, pagar warna hitam, dekat masjid',
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF0077E6), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Switch Jadikan Alamat Utama
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Jadikan sebagai alamat utama',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                  Switch(
                                    value: makeDefault,
                                    activeThumbColor: const Color(0xFF0077E6),
                                    onChanged: (val) {
                                      setModalState(() => makeDefault = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Tombol Simpan
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  final label = labelController.text.trim().isEmpty
                                      ? selectedCategory
                                      : labelController.text.trim();
                                  final address = addressController.text.trim();
                                  final note = noteController.text.trim();

                                  if (address.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Alamat lengkap tidak boleh kosong',
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white),
                                        ),
                                        backgroundColor: Colors.redAccent,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }

                                  addAddress(
                                    AddressItem(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      label: label,
                                      address: address,
                                      note: note,
                                      isDefault: makeDefault,
                                    ),
                                    setAsDefault: makeDefault,
                                  );

                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Alamat "$label" berhasil disimpan!',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white),
                                      ),
                                      backgroundColor: const Color(0xFF0077E6),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0077E6),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Simpan Alamat',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

