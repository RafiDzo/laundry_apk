import 'service_model.dart';

class ShopModel {
  final String id;
  final String name;
  final double rating;
  final String distance;
  final String queueText;
  final String address;
  final String openHours;
  final String imageUrl;
  final int pricePerKg;
  final List<ServiceModel> services;
  final String? ownerId;

  // Layanan Antar Jemput & Operasional
  final bool isDeliveryAvailable;
  final int deliveryFee;
  final String deliveryFeeType; // 'flat' | 'per_km' | 'free'
  final double deliveryRadiusKm;
  final int minDeliveryOrder;
  final String operationalDays;
  final bool isOpen;

  ShopModel({
    required this.id,
    required this.name,
    required this.rating,
    required this.distance,
    required this.queueText,
    required this.address,
    required this.openHours,
    required this.imageUrl,
    required this.pricePerKg,
    this.services = const [],
    this.ownerId,
    this.isDeliveryAvailable = true,
    this.deliveryFee = 5000,
    this.deliveryFeeType = 'flat',
    this.deliveryRadiusKm = 5.0,
    this.minDeliveryOrder = 20000,
    this.operationalDays = 'Setiap Hari (Senin - Minggu)',
    this.isOpen = true,
  });

  ShopModel copyWith({
    String? id,
    String? name,
    double? rating,
    String? distance,
    String? queueText,
    String? address,
    String? openHours,
    String? imageUrl,
    int? pricePerKg,
    List<ServiceModel>? services,
    String? ownerId,
    bool? isDeliveryAvailable,
    int? deliveryFee,
    String? deliveryFeeType,
    double? deliveryRadiusKm,
    int? minDeliveryOrder,
    String? operationalDays,
    bool? isOpen,
  }) {
    return ShopModel(
      id: id ?? this.id,
      name: name ?? this.name,
      rating: rating ?? this.rating,
      distance: distance ?? this.distance,
      queueText: queueText ?? this.queueText,
      address: address ?? this.address,
      openHours: openHours ?? this.openHours,
      imageUrl: imageUrl ?? this.imageUrl,
      pricePerKg: pricePerKg ?? this.pricePerKg,
      services: services ?? this.services,
      ownerId: ownerId ?? this.ownerId,
      isDeliveryAvailable: isDeliveryAvailable ?? this.isDeliveryAvailable,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      deliveryFeeType: deliveryFeeType ?? this.deliveryFeeType,
      deliveryRadiusKm: deliveryRadiusKm ?? this.deliveryRadiusKm,
      minDeliveryOrder: minDeliveryOrder ?? this.minDeliveryOrder,
      operationalDays: operationalDays ?? this.operationalDays,
      isOpen: isOpen ?? this.isOpen,
    );
  }

  factory ShopModel.fromMap(Map<String, dynamic> data, String id) {
    var servicesList = <ServiceModel>[];
    if (data['services'] != null) {
      servicesList = List<ServiceModel>.from(
        (data['services'] as List).map((item) => ServiceModel.fromMap(item as Map<String, dynamic>))
      );
    }
    return ShopModel(
      id: id,
      name: data['name'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      distance: data['distance'] ?? '',
      queueText: data['queue_text'] ?? data['queueText'] ?? '',
      address: data['address'] ?? '',
      openHours: data['open_hours'] ?? data['openHours'] ?? '08:00 - 21:00',
      imageUrl: data['image_url'] ?? data['imageUrl'] ?? '',
      pricePerKg: data['price_per_kg'] ?? data['pricePerKg'] ?? 0,
      services: servicesList,
      ownerId: data['owner_id'],
      isDeliveryAvailable: data['is_delivery_available'] ?? data['isDeliveryAvailable'] ?? true,
      deliveryFee: (data['delivery_fee'] ?? data['deliveryFee'] ?? 5000) as int,
      deliveryFeeType: data['delivery_fee_type'] ?? data['deliveryFeeType'] ?? 'flat',
      deliveryRadiusKm: ((data['delivery_radius_km'] ?? data['deliveryRadiusKm'] ?? 5.0) as num).toDouble(),
      minDeliveryOrder: (data['min_delivery_order'] ?? data['minDeliveryOrder'] ?? 20000) as int,
      operationalDays: data['operational_days'] ?? data['operationalDays'] ?? 'Setiap Hari (Senin - Minggu)',
      isOpen: data['is_open'] ?? data['isOpen'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'rating': rating,
      'distance': distance,
      'queueText': queueText,
      'address': address,
      'openHours': openHours,
      'imageUrl': imageUrl,
      'pricePerKg': pricePerKg,
      'services': services.map((e) => e.toMap()).toList(),
      'is_delivery_available': isDeliveryAvailable,
      'delivery_fee': deliveryFee,
      'delivery_fee_type': deliveryFeeType,
      'delivery_radius_km': deliveryRadiusKm,
      'min_delivery_order': minDeliveryOrder,
      'operational_days': operationalDays,
      'is_open': isOpen,
    };
  }
}
