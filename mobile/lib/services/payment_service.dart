import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/payment.dart';

class PaymentService {
  PaymentService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const _select =
      'id, customer_id, transaction_id, amount, payment_method, notes, created_at';

  Future<List<Payment>> listPayments() {
    return _guard(() async {
      final rows = await _supabase
          .from('payments')
          .select(_select)
          .order('created_at', ascending: false);
      return rows.map((row) => Payment.fromJson(_paymentJson(row))).toList();
    });
  }

  Future<Payment> createPayment({
    required int customerId,
    required num amount,
    required String paymentMethod,
    int? transactionId,
    String? notes,
  }) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'create_payment',
        params: {
          'customer_id': customerId,
          'transaction_id': transactionId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': _emptyAsNull(notes),
        },
      );
      return Payment.fromJson(_paymentJson(data));
    });
  }

  Future<Payment> updatePayment({
    required int id,
    required num amount,
    required String paymentMethod,
    required int? transactionId,
    String? notes,
  }) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'update_payment',
        params: {
          'payment_id': id,
          'transaction_id': transactionId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': notes ?? '',
        },
      );
      return Payment.fromJson(_paymentJson(data));
    });
  }

  Map<String, dynamic> _paymentJson(dynamic data) {
    final row = _map(data);
    return {
      'id': _asInt(row['id']),
      'customer_id': row['customer_id'] == null ? null : _asInt(row['customer_id']),
      'transaction_id': row['transaction_id'] == null ? null : _asInt(row['transaction_id']),
      'amount': _asNum(row['amount']),
      'payment_method': row['payment_method'],
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
