class OrderItem {
  final String name;
  final int qty;
  final int price;
  final String unit;

  OrderItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.unit,
  });

  factory OrderItem.fromMap(Map<String, dynamic> data) {
    return OrderItem(
      name: data['name'] ?? '',
      qty: data['qty'] ?? 0,
      price: data['price'] ?? 0,
      unit: data['unit'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'qty': qty,
      'price': price,
      'unit': unit,
    };
  }
}

class OrderModel {
  final String id;
  final String userId;
  final String shopId;
  final String shopName;
  final List<OrderItem> items;
  final String status; // 'pending', 'washing', 'drying', 'done', 'delivered'
  final int totalPrice;
  final int serviceFee;
  final String? notes;
  final String paymentMethod;
  final DateTime createdAt;

  OrderModel({
    required this.id,
    required this.userId,
    required this.shopId,
    required this.shopName,
    required this.items,
    this.status = 'pending',
    required this.totalPrice,
    required this.serviceFee,
    this.notes,
    required this.paymentMethod,
    required this.createdAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> data, String id) {
    var itemsList = <OrderItem>[];
    if (data['items'] != null) {
      itemsList = List<OrderItem>.from(
        (data['items'] as List).map((item) => OrderItem.fromMap(item as Map<String, dynamic>))
      );
    }
    return OrderModel(
      id: id,
      userId: data['user_id'] ?? '',
      shopId: data['shop_id'] ?? '',
      shopName: data['shop_name'] ?? '',
      items: itemsList,
      status: data['status'] ?? 'pending',
      totalPrice: data['total_price'] ?? 0,
      serviceFee: data['service_fee'] ?? 0,
      notes: data['notes'],
      paymentMethod: data['payment_method'] ?? '',
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'shop_id': shopId,
      'shop_name': shopName,
      'items': items.map((e) => e.toMap()).toList(),
      'status': status,
      'total_price': totalPrice,
      'service_fee': serviceFee,
      'notes': notes,
      'payment_method': paymentMethod,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
