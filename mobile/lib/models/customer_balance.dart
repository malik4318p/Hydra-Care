class CustomerBalance {
  const CustomerBalance({
    required this.customerId,
    required this.totalCharges,
    required this.totalPayments,
    required this.outstandingBalance,
  });

  final int customerId;
  final num totalCharges;
  final num totalPayments;
  final num outstandingBalance;

  factory CustomerBalance.fromJson(Map<String, dynamic> json) {
    return CustomerBalance(
      customerId: json['customer_id'] as int,
      totalCharges: json['total_charges'] as num,
      totalPayments: json['total_payments'] as num,
      outstandingBalance: json['outstanding_balance'] as num,
    );
  }
}
