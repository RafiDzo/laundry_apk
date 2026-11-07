class ServiceModel {
  final String id;
  final String name;
  final String description;
  final int price;
  final String unit; // '/ kg' atau '/ pcs'
  final String iconName;
  final bool isActive;
  final String duration;

  ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.unit,
    required this.iconName,
    this.isActive = true,
    this.duration = '1-2 Hari',
  });

  ServiceModel copyWith({
    String? id,
    String? name,
    String? description,
    int? price,
    String? unit,
    String? iconName,
    bool? isActive,
    String? duration,
  }) {
    return ServiceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      iconName: iconName ?? this.iconName,
      isActive: isActive ?? this.isActive,
      duration: duration ?? this.duration,
    );
  }

  factory ServiceModel.fromMap(Map<String, dynamic> data) {
    return ServiceModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: data['price'] ?? 0,
      unit: data['unit'] ?? '/ kg',
      iconName: data['iconName'] ?? 'local_laundry_service',
      isActive: data['isActive'] ?? data['is_active'] ?? true,
      duration: data['duration'] ?? '1-2 Hari',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'unit': unit,
      'iconName': iconName,
      'isActive': isActive,
      'duration': duration,
    };
  }
}
