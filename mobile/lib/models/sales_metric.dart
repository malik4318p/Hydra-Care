class SalesMetric {
  const SalesMetric({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.totalAmount,
  });

  final int productId;
  final String productName;
  final int quantity;
  final num totalAmount;
}
