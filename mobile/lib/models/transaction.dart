class Transaction {
  const Transaction({
    required this.id,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.customerId,
    this.productId,
    this.productName,
    this.notes,
    this.createdAt,
  });

  final int id;
  final int? customerId;
  final int? productId;
  final String? productName;
  final int quantity;
  final num unitPrice;
  final num totalAmount;
  final String? notes;
  final String? createdAt;

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int,
      customerId: json['customer_id'] as int?,
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String?,
      quantity: json['quantity'] as int,
      unitPrice: json['unit_price'] as num,
      totalAmount: json['total_amount'] as num,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
