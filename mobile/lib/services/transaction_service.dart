import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/transaction.dart';

class TransactionService {
  TransactionService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const _select =
      'id, customer_id, product_id, quantity, unit_price, total_amount, notes, created_at, products!fk_transactions_product(name)';

  Future<List<Transaction>> listTransactions() {
    return _guard(() async {
      final rows = await _supabase
          .from('transactions')
          .select(_select)
          .order('created_at', ascending: false);
      return rows.map((row) => Transaction.fromJson(_transactionJson(row))).toList();
    });
  }

  Future<Transaction> createTransaction({
    required int customerId,
    required int productId,
    required int quantity,
    num? unitPrice,
    String? notes,
  }) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'create_transaction',
        params: {
          'customer_id': customerId,
          'product_id': productId,
          'quantity': quantity,
          'unit_price': unitPrice,
          'notes': _emptyAsNull(notes),
        },
      );
      return Transaction.fromJson(_transactionJson(data));
    });
  }

  Future<Transaction> updateTransaction({
    required int id,
    required int productId,
    required int quantity,
    required num unitPrice,
    String? notes,
  }) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'update_transaction',
        params: {
          'transaction_id': id,
          'product_id': productId,
          'quantity': quantity,
          'unit_price': unitPrice,
          'notes': notes ?? '',
        },
      );
      return Transaction.fromJson(_transactionJson(data));
    });
  }

  Map<String, dynamic> _transactionJson(dynamic data) {
    final row = _map(data);
    final product = row['products'];
    final productName = product is Map ? product['name'] : row['product_name'];

    return {
      'id': _asInt(row['id']),
      'customer_id': row['customer_id'] == null ? null : _asInt(row['customer_id']),
      'product_id': row['product_id'] == null ? null : _asInt(row['product_id']),
      'product_name': productName,
      'quantity': _asInt(row['quantity']),
      'unit_price': _asNum(row['unit_price']),
      'total_amount': _asNum(row['total_amount']),
      'notes': row['notes'],
      'created_at': _asString(row['created_at']),
    };
  }

  String? _emptyAsNull(String? notes) {
    if (notes == null || notes.isEmpty) {
      return null;
    }
    return notes;
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
    if (code == '42501' || message == 'admin required' || message.toLowerCase().contains('row-level security')) {
      return ApiException(403, 'You do not have permission to perform this action');
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
