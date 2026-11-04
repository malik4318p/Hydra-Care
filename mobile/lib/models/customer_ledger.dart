class CustomerBottleBalance {
  const CustomerBottleBalance({
    required this.issued,
    required this.returned,
    required this.outstanding,
  });

  final int issued;
  final int returned;
  final int outstanding;

  factory CustomerBottleBalance.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return CustomerBottleBalance(
      issued: _asInt(value['issued']),
      returned: _asInt(value['returned']),
      outstanding: _asInt(value['outstanding']),
    );
  }
}

class CustomerSecurityActivity {
  const CustomerSecurityActivity({
    required this.id,
    required this.entryType,
    required this.amount,
    this.notes,
    this.createdBy,
    this.createdAt,
  });

  final int id;
  final String entryType;
  final num amount;
  final String? notes;
  final int? createdBy;
  final String? createdAt;

  factory CustomerSecurityActivity.fromJson(Map<String, dynamic> json) {
    return CustomerSecurityActivity(
      id: _asInt(json['id']),
      entryType: json['entry_type'] as String,
      amount: _asNum(json['amount']),
      notes: json['notes'] as String?,
      createdBy: json['created_by'] == null ? null : _asInt(json['created_by']),
      createdAt: _asString(json['created_at']),
    );
  }
}

class CustomerBottleActivity {
  const CustomerBottleActivity({
    required this.id,
    required this.productId,
    required this.entryType,
    required this.quantity,
    this.notes,
    this.createdBy,
    this.createdAt,
  });

  final int id;
  final int productId;
  final String entryType;
  final int quantity;
  final String? notes;
  final int? createdBy;
  final String? createdAt;

  factory CustomerBottleActivity.fromJson(Map<String, dynamic> json) {
    return CustomerBottleActivity(
      id: _asInt(json['id']),
      productId: _asInt(json['product_id']),
      entryType: json['entry_type'] as String,
      quantity: _asInt(json['quantity']),
      notes: json['notes'] as String?,
      createdBy: json['created_by'] == null ? null : _asInt(json['created_by']),
      createdAt: _asString(json['created_at']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse('$value') ?? 0;
}

String? _asString(dynamic value) => value == null ? null : '$value';
