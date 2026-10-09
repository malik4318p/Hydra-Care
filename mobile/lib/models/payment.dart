class Payment {
  const Payment({
    required this.id,
    required this.amount,
    required this.paymentMethod,
    this.customerId,
    this.transactionId,
    this.notes,
    this.createdAt,
  });

  final int id;
  final int? customerId;
  final int? transactionId;
  final num amount;
  final String paymentMethod;
  final String? notes;
  final String? createdAt;

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as int,
      customerId: json['customer_id'] as int?,
      transactionId: json['transaction_id'] as int?,
      amount: json['amount'] as num,
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
