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
  final List<ServiceModel> services; // In Firestore, this could be a subcollection or nested map

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
  });

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
      openHours: data['open_hours'] ?? data['openHours'] ?? '',
      imageUrl: data['image_url'] ?? data['imageUrl'] ?? '',
      pricePerKg: data['price_per_kg'] ?? data['pricePerKg'] ?? 0,
      services: servicesList,
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
    };
  }
}
