import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/order.dart';

/// One product line the admin picked while building a phone order. Only the
/// product id and quantity travel to the server — the server snapshots the
/// product's current name and price itself, so a client-supplied price can
/// never be trusted or used.
class OrderItemInput {
  const OrderItemInput({required this.productId, required this.quantity});

  final int productId;
  final int quantity;
}

class OrderService {
  OrderService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const _select = 'id, customer_id, status, total_amount, notes, '
      'created_at, updated_at, delivered_at, '
      'customers!fk_orders_customer(id, users!fk_customers_user(name, phone)), '
      'order_items(id, order_id, product_id, product_name, quantity, unit_price, total_amount)';

  /// Total Orders: every order created within the half-open UTC interval
  /// `[startUtc, endUtc)`, any status.
  Future<List<Order>> listOrdersCreatedBetween(
    DateTime startUtc,
    DateTime endUtc,
  ) {
    return _guard(() async {
      final rows = await _supabase
          .from('orders')
          .select(_select)
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String())
          .order('created_at', ascending: false);
      return rows.map((row) => _orderFromRow(_map(row))).toList();
    });
  }

  /// Delivered Orders: orders actually delivered within
  /// `[startUtc, endUtc)`, regardless of when they were originally created.
  Future<List<Order>> listOrdersDeliveredBetween(
    DateTime startUtc,
    DateTime endUtc,
  ) {
    return _guard(() async {
      final rows = await _supabase
          .from('orders')
          .select(_select)
          .eq('status', 'delivered')
          .gte('delivered_at', startUtc.toIso8601String())
          .lt('delivered_at', endUtc.toIso8601String())
          .order('delivered_at', ascending: false);
      return rows.map((row) => _orderFromRow(_map(row))).toList();
    });
  }

  /// Undelivered Orders: still-pending orders created within
  /// `[startUtc, endUtc)`.
  Future<List<Order>> listPendingOrdersCreatedBetween(
    DateTime startUtc,
    DateTime endUtc,
  ) {
    return _guard(() async {
      final rows = await _supabase
          .from('orders')
          .select(_select)
          .eq('status', 'pending')
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String())
          .order('created_at', ascending: false);
      return rows.map((row) => _orderFromRow(_map(row))).toList();
    });
  }

  Future<Order> getOrder(int id) {
    return _guard(() async {
      final row = await _supabase
          .from('orders')
          .select(_select)
          .eq('id', id)
          .maybeSingle();
      if (row == null) {
        throw ApiException(404, 'Order not found');
      }
      return _orderFromRow(_map(row));
    });
  }

  /// Creates a Pending order with its items. Does not create any
  /// transaction and does not change any customer balance.
  Future<Order> createOrder({
    required int customerId,
    required List<OrderItemInput> items,
    String? notes,
  }) {
    return _guard(() async {
      final data = await _supabase.rpc('create_phone_order', params: {
        'customer_id': customerId,
        'items': [
          for (final item in items)
            {'product_id': item.productId, 'quantity': item.quantity},
        ],
        'notes': _emptyAsNull(notes),
      });
      final json = _map(data);
      return Order.fromJson(_orderJson(
        _map(json['order']),
        itemsJson: json['items'],
      ));
    });
  }

  /// Marks an order Delivered and generates its transactions atomically.
  /// Rejects an order that is not Pending (duplicate-delivery prevention).
  Future<Order> deliverOrder(int orderId) {
    return _guard(() async {
      final data = await _supabase.rpc('deliver_phone_order', params: {
        'target_order_id': orderId,
      });
      final json = _map(data);
      return Order.fromJson(_orderJson(_map(json['order'])));
    });
  }

  Order _orderFromRow(Map<String, dynamic> row) {
    final customer = row['customers'];
    final customerMap = customer is Map
        ? _map(customer)
        : customer is List && customer.isNotEmpty && customer.first is Map
            ? _map(customer.first)
            : <String, dynamic>{};
    final user = customerMap['users'];
    final userMap = user is Map
        ? _map(user)
        : user is List && user.isNotEmpty && user.first is Map
            ? _map(user.first)
            : <String, dynamic>{};

    return Order.fromJson({
      'id': _asInt(row['id']),
      'customer_id': _asInt(row['customer_id']),
      'status': row['status'],
      'total_amount': _asNum(row['total_amount']),
      'notes': row['notes'],
      'created_at': _asString(row['created_at']),
      'updated_at': _asString(row['updated_at']),
      'delivered_at': _asString(row['delivered_at']),
      'customer_name': userMap['name'],
      'customer_phone': userMap['phone'],
      'items': _list(row['order_items']).map(_orderItemJson).toList(),
    });
  }

  Map<String, dynamic> _orderJson(
    Map<String, dynamic> row, {
    dynamic itemsJson,
  }) {
    return {
      'id': _asInt(row['id']),
      'customer_id': _asInt(row['customer_id']),
      'status': row['status'],
      'total_amount': _asNum(row['total_amount']),
      'notes': row['notes'],
      'created_at': _asString(row['created_at']),
      'updated_at': _asString(row['updated_at']),
      'delivered_at': _asString(row['delivered_at']),
      'items': _list(itemsJson).map(_orderItemJson).toList(),
    };
  }

  Map<String, dynamic> _orderItemJson(dynamic item) {
    final row = _map(item);
    return {
      'id': _asInt(row['id']),
      'order_id': _asInt(row['order_id']),
      'product_id': _asInt(row['product_id']),
      'product_name': row['product_name'],
      'quantity': _asInt(row['quantity']),
      'unit_price': _asNum(row['unit_price']),
      'total_amount': _asNum(row['total_amount']),
    };
  }

  String? _emptyAsNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw _asApiException(error);
    } on ApiException {
      rethrow;
    }
  }

  ApiException _asApiException(PostgrestException error) {
    final code = error.code;
    final message = error.message;

    if (code == '28000' || message.toLowerCase() == 'unauthenticated') {
      return ApiException(401, 'Authentication required');
    }
    if (code == 'P0002') {
      return ApiException(404, message);
    }
    if (code == '42501' ||
        message == 'admin required' ||
        message.toLowerCase().contains('row-level security')) {
      return ApiException(
          403, 'You do not have permission to perform this action');
    }
    return ApiException(400, message);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    throw ApiException(0, 'Response was not valid');
  }

  List<dynamic> _list(dynamic value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse('$value');
  }

  num _asNum(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value;
    }
    return num.parse('$value');
  }

  String? _asString(dynamic value) {
    if (value == null) {
      return null;
    }
    return value is String ? value : value.toString();
  }
}
