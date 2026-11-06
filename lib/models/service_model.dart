class ServiceModel {
  final String id;
  final String name;
  final String description;
  final int price;
  final String unit; // '/ kg' atau '/ pcs'
  final String iconName;
  final String duration; // mis. '1-2 Hari', '4 Jam' (opsional)

  ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.unit,
    required this.iconName,
    this.duration = '',
  });

  factory ServiceModel.fromMap(Map<String, dynamic> data) {
    return ServiceModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: data['price'] ?? 0,
      unit: data['unit'] ?? '',
      iconName: data['iconName'] ?? '',
      duration: data['duration'] ?? '',
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
      if (duration.isNotEmpty) 'duration': duration,
    };
  }
}
