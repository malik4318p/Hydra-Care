class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
  });

  final int id;
  final int orderId;
  final int productId;
  final String productName;
  final int quantity;
  final num unitPrice;
  final num totalAmount;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as int,
      orderId: json['order_id'] as int,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      quantity: json['quantity'] as int,
      unitPrice: json['unit_price'] as num,
      totalAmount: json['total_amount'] as num,
    );
  }
}
