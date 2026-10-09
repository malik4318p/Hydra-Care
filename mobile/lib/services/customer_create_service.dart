import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/customer.dart';

class CustomerCreateService {
  CustomerCreateService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const functionName = 'create-customer';

  Future<Customer> createCustomer({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String address,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      throw ApiException(401, 'Authentication required');
    }

    try {
      final response = await _supabase.functions.invoke(
        functionName,
        body: {
          'name': name,
          'phone': phone,
          'email': email,
          'password': password,
          'address': address,
        },
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        return Customer.fromJson(_customerJson(body['data']));
      }
      throw ApiException(response.status, _message(body));
    } on FunctionException catch (error) {
      throw ApiException(error.status, _message(error.details));
    }
  }

  Map<String, dynamic> _customerJson(dynamic value) {
    final row = _map(value);
    return {
      'id': _asInt(row['id']),
      'user_id': _asInt(row['user_id']),
      'name': row['name'],
      'phone': row['phone'],
      'email': row['email'],
      'role': row['role'],
      'address': row['address'],
      'created_at': row['created_at']?.toString(),
      'updated_at': row['updated_at']?.toString(),
    };
  }

  String _message(dynamic details) {
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    if (details is String && details.trim().isNotEmpty) {
      return details.trim();
    }
    return 'Could not add the customer.';
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
}
