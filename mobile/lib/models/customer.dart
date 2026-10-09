class Customer {
  const Customer({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.address,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String address;

  /// Archived (soft-deleted) customers have this set to false. They stay in
  /// the database with all their history; they are just hidden from normal
  /// business operations such as new sales and payments.
  final bool active;
  final String? createdAt;
  final String? updatedAt;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      address: json['address'] as String,
      // Defaults to true for responses that don't select this column, such
      // as the customer summary RPC's own profile object.
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }
}
