class Product {
  const Product({
    required this.id,
    required this.name,
    required this.type,
    required this.currentPrice,
    required this.active,
  });

  final int id;
  final String name;
  final String type;
  final num currentPrice;
  final bool active;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      currentPrice: json['current_price'] as num,
      active: json['active'] as bool,
    );
  }
}
