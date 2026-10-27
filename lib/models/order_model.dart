class OrderItem {
  final String name;
  final num qty; // num agar berat desimal (mis. 3.5 kg) dari kasir bisa disimpan
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
  final String status; // 'pending', 'washing', 'drying', 'done', 'delivered', 'cancelled'
  final int totalPrice;
  final int serviceFee;
  final String? notes;
  final String paymentMethod;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;
  final String deliveryType; // 'pickup' (dijemput kurir) atau 'dropoff' (antar sendiri)

  /// Urutan tahapan proses, dipakai halaman pelacakan pelanggan
  static const List<String> statusFlow = ['pending', 'washing', 'drying', 'done', 'delivered'];

  static const Map<String, String> statusLabels = {
    'pending': 'Menunggu Diproses',
    'washing': 'Sedang Dicuci',
    'drying': 'Pengeringan & Setrika',
    'done': 'Selesai Diproses',
    'delivered': 'Pesanan Selesai',
    'cancelled': 'Dibatalkan',
  };

  bool get isDropoff => deliveryType == 'dropoff';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => status != 'delivered' && status != 'cancelled';
  String get statusLabel => statusLabels[status] ?? 'Menunggu Diproses';

  /// Posisi status di [statusFlow] (0 = pending … 4 = delivered); -1 jika dibatalkan
  int get statusStep => statusFlow.indexOf(status);

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
    this.customerName,
    this.customerPhone,
    this.deliveryType = 'pickup',
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
          ? DateTime.parse(data['created_at']).toLocal()
          : DateTime.now(),
      customerName: data['customer_name'],
      customerPhone: data['customer_phone'],
      deliveryType: data['delivery_type'] ?? 'pickup',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId.isEmpty ? null : userId,
      'shop_id': shopId,
      'shop_name': shopName,
      'items': items.map((e) => e.toMap()).toList(),
      'status': status,
      'total_price': totalPrice,
      'service_fee': serviceFee,
      'notes': notes,
      'payment_method': paymentMethod,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      // 'pickup' sudah jadi default di database, jadi hanya dikirim untuk drop-off
      if (isDropoff) 'delivery_type': deliveryType,
    };
  }
}
