import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/customer.dart';
import '../models/customer_balance.dart';
import '../models/customer_summary.dart';

class CustomerDataService {
  CustomerDataService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const _customerSelect =
      'id, user_id, address, active, created_at, updated_at, users!fk_customers_user!inner(name, phone, email, role)';

  /// Lists customers.
  ///
  /// [activeOnly] is a hard filter on `customers.active`: pass `true` for
  /// the Active tab, `false` for the Archived tab, or leave it null to get
  /// every customer regardless of status (used for historical lookups such
  /// as the transaction/payment list, where an archived customer's past
  /// records must still show their name).
  ///
  /// [search] matches name, phone, or email, case-insensitively, anywhere
  /// in the value. Matching happens in Postgres, not in Flutter.
  Future<List<Customer>> listCustomers({bool? activeOnly, String? search}) {
    return _guard(() async {
      var query = _supabase.from('customers').select(_customerSelect);

      if (activeOnly != null) {
        query = query.eq('active', activeOnly);
      }

      final term = search?.trim();
      if (term != null && term.isNotEmpty) {
        final pattern = _ilikeValue(term);
        query = query.or(
          'name.ilike.$pattern,phone.ilike.$pattern,email.ilike.$pattern',
          referencedTable: 'users',
        );
      }

      final rows = await query.order('id');
      return rows.map((row) => _customerFromRow(_map(row))).toList();
    });
  }

  /// Archives a customer (`active = false`). The row, and every transaction
  /// and payment for it, is left in place. The customer's Supabase Auth
  /// account is not touched.
  Future<void> archiveCustomer(int id) => setCustomerActive(id: id, active: false);

  /// Restores a previously archived customer (`active = true`).
  Future<void> restoreCustomer(int id) => setCustomerActive(id: id, active: true);

  Future<void> setCustomerActive({required int id, required bool active}) {
    return _guard(() async {
      final row = await _supabase
          .from('customers')
          .update({'active': active})
          .eq('id', id)
          .select('id')
          .maybeSingle();

      if (row == null) {
        throw ApiException(404, 'Customer not found');
      }
    });
  }

  /// Wraps a search term as a double-quoted ILIKE pattern so that a comma,
  /// parenthesis, or other PostgREST-reserved character in the term cannot
  /// break the filter expression built for `.or()`.
  String _ilikeValue(String term) {
    final escaped = term.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"%$escaped%"';
  }

  Future<CustomerBalance> getCustomerBalance(int customerId) {
    return _guard(() async {
      final data = await _supabase.rpc(
        'get_customer_balance',
        params: {'target_customer_id': customerId},
      );
      return CustomerBalance.fromJson(_balanceJson(_map(data)));
    });
  }

  Future<CustomerSummary> getMySummary() {
    return _guard(() async {
      final customerId = await _ownCustomerId();
      final data = await _supabase.rpc(
        'get_customer_summary',
        params: {'target_customer_id': customerId},
      );
      return CustomerSummary.fromJson(_summaryJson(_map(data)));
    });
  }

  Future<String> customerEmail(int customerId) {
    return _guard(() async {
      final row = await _supabase
          .from('customers')
          .select('users!fk_customers_user(email)')
          .eq('id', customerId)
          .maybeSingle();

      if (row == null) {
        throw ApiException(404, 'Customer not found');
      }

      final user = row['users'];
      final email = user is Map ? user['email'] : null;
      if (email is! String || email.isEmpty) {
        throw ApiException(404, 'Customer not found');
      }
      return email;
    });
  }

  Future<void> updateNameAndPhone({
    required int id,
    required String name,
    required String phone,
  }) {
    return _guard(() async {
      final trimmedName = name.trim();
      final trimmedPhone = phone.trim();
      if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
        throw ApiException(400, 'Name, phone, email, and address are required.');
      }
      if (trimmedName.length > 255 || trimmedPhone.length > 20) {
        throw ApiException(400, 'Name or phone is too long.');
      }

      final customer = await _supabase
          .from('customers')
          .select('user_id')
          .eq('id', id)
          .maybeSingle();
      if (customer == null) {
        throw ApiException(404, 'Customer not found');
      }

      final updated = await _supabase
          .from('users')
          .update({
            'name': trimmedName,
            'phone': trimmedPhone,
          })
          .eq('id', _asInt(_map(customer)['user_id']))
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw ApiException(404, 'Customer not found');
      }
    });
  }

  Future<Customer> updateAddress({
    required int id,
    required String address,
  }) {
    return _guard(() async {
      if (address.trim().isEmpty) {
        throw ApiException(400, 'Name, phone, email, and address are required.');
      }

      final row = await _supabase
          .from('customers')
          .update({'address': address})
          .eq('id', id)
          .select(_customerSelect)
          .maybeSingle();

      if (row == null) {
        throw ApiException(404, 'Customer not found');
      }
      return _customerFromRow(_map(row));
    });
  }

  Future<int> _ownCustomerId() async {
    final authUserId = _supabase.auth.currentUser?.id;
    if (authUserId == null || authUserId.isEmpty) {
      throw ApiException(401, 'Authentication required');
    }

    final row = await _supabase
        .from('customers')
        .select('id, users!fk_customers_user!inner(auth_user_id)')
        .eq('users.auth_user_id', authUserId)
        .maybeSingle();

    if (row == null) {
      throw ApiException(404, 'Customer profile not found');
    }
    return _asInt(_map(row)['id']);
  }

  Customer _customerFromRow(Map<String, dynamic> row) {
    final user = row['users'];
    final profile = user is Map
        ? _map(user)
        : user is List && user.isNotEmpty && user.first is Map
            ? _map(user.first)
            : <String, dynamic>{};

    return Customer.fromJson({
      'id': _asInt(row['id']),
      'user_id': _asInt(row['user_id']),
      'name': profile['name'],
      'phone': profile['phone'],
      'email': profile['email'],
      'role': profile['role'],
      'address': row['address'],
      'active': row['active'] == true,
      'created_at': _asString(row['created_at']),
      'updated_at': _asString(row['updated_at']),
    });
  }

  Map<String, dynamic> _balanceJson(Map<String, dynamic> json) {
    return {
      'customer_id': _asInt(json['customer_id']),
      'total_charges': _asNum(json['total_charges']),
      'total_payments': _asNum(json['total_payments']),
      'outstanding_balance': _asNum(json['outstanding_balance']),
    };
  }

  Map<String, dynamic> _summaryJson(Map<String, dynamic> json) {
    final customer = _map(json['customer']);
    final transactions = json['recent_transactions'];
    final payments = json['recent_payments'];

    return {
      'customer': {
        'id': _asInt(customer['id']),
        'user_id': _asInt(customer['user_id']),
        'name': customer['name'],
        'phone': customer['phone'],
        'email': customer['email'],
        'role': customer['role'],
        'address': customer['address'],
        'created_at': _asString(customer['created_at']),
        'updated_at': _asString(customer['updated_at']),
      },
      'balance': _balanceJson(_map(json['balance'])),
      'recent_transactions': _list(transactions).map(_transactionJson).toList(),
      'recent_payments': _list(payments).map(_paymentJson).toList(),
    };
  }

  Map<String, dynamic> _transactionJson(dynamic item) {
    final row = _map(item);
    return {
      'id': _asInt(row['id']),
      'product_id': _asInt(row['product_id']),
      'product_name': row['product_name'],
      'quantity': _asInt(row['quantity']),
      'unit_price': _asNum(row['unit_price']),
      'total_amount': _asNum(row['total_amount']),
      'notes': row['notes'],
      'created_at': _asString(row['created_at']),
    };
  }

  Map<String, dynamic> _paymentJson(dynamic item) {
    final row = _map(item);
    return {
      'id': _asInt(row['id']),
      'transaction_id': row['transaction_id'] == null ? null : _asInt(row['transaction_id']),
      'amount': _asNum(row['amount']),
      'payment_method': row['payment_method'],
      'notes': row['notes'],
      'created_at': _asString(row['created_at']),
    };
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
    if (code == 'P0002' || message == 'Customer not found') {
      return ApiException(404, 'Customer not found');
    }
    if (code == '42501' || message.toLowerCase().contains('row-level security')) {
      return ApiException(403, 'You do not have permission to perform this action');
    }
    if (message == 'You do not have permission to perform this action') {
      return ApiException(403, message);
    }
    if (message == 'Customer profile not found') {
      return ApiException(404, message);
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
