class ServiceModel {
  final String id;
  final String name;
  final String description;
  final int price;
  final String unit; // '/ kg' atau '/ pcs'
  final String iconName;

  ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.unit,
    required this.iconName,
  });

  factory ServiceModel.fromMap(Map<String, dynamic> data) {
    return ServiceModel(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: data['price'] ?? 0,
      unit: data['unit'] ?? '',
      iconName: data['iconName'] ?? '',
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
    };
  }
}
