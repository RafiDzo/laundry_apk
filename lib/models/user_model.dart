class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? profileImageUrl;
  final String membershipLevel; // 'Bronze', 'Silver', 'Gold'
  final int totalOrders;
  final int points;
  final int activeVouchers;
  final DateTime createdAt;
  final String role; // 'customer' or 'owner'

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.profileImageUrl,
    this.membershipLevel = 'Bronze',
    this.totalOrders = 0,
    this.points = 0,
    this.activeVouchers = 0,
    required this.createdAt,
    this.role = 'customer',
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      profileImageUrl: data['profile_image_url'],
      membershipLevel: data['membership_level'] ?? 'Bronze',
      totalOrders: data['total_orders'] ?? 0,
      points: data['points'] ?? 0,
      activeVouchers: data['active_vouchers'] ?? 0,
      createdAt: data['created_at'] != null
          ? DateTime.parse(data['created_at'])
          : DateTime.now(),
      role: data['role'] ?? 'customer',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'profile_image_url': profileImageUrl,
      'membership_level': membershipLevel,
      'total_orders': totalOrders,
      'points': points,
      'active_vouchers': activeVouchers,
      'created_at': createdAt.toIso8601String(),
      'role': role,
    };
  }
}
