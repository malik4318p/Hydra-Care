import 'order_item.dart';

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    this.notes,
    this.updatedAt,
    this.deliveredAt,
    this.customerName,
    this.customerPhone,
    this.items = const [],
  });

  final int id;
  final int customerId;

  /// 'pending' or 'delivered'.
  final String status;
  final num totalAmount;
  final String? notes;
  final String createdAt;
  final String? updatedAt;
  final String? deliveredAt;
  final String? customerName;
  final String? customerPhone;
  final List<OrderItem> items;

  bool get isPending => status == 'pending';
  bool get isDelivered => status == 'delivered';

  Order copyWith({
    String? status,
    String? updatedAt,
    String? deliveredAt,
  }) {
    return Order(
      id: id,
      customerId: customerId,
      status: status ?? this.status,
      totalAmount: totalAmount,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      customerName: customerName,
      customerPhone: customerPhone,
      items: items,
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? const [];
    return Order(
      id: json['id'] as int,
      customerId: json['customer_id'] as int,
      status: json['status'] as String,
      totalAmount: json['total_amount'] as num,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String?,
      deliveredAt: json['delivered_at'] as String?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      items: itemsJson
          .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
