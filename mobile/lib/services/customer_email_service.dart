import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';

class CustomerEmailService {
  CustomerEmailService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const functionName = 'update-customer-email';

  Future<void> changeCustomerEmail({
    required int customerId,
    required String email,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null || session.accessToken.isEmpty) {
      throw ApiException(401, 'Authentication required');
    }

    try {
      final response = await _supabase.functions.invoke(
        functionName,
        body: {
          'customer_id': customerId,
          'email': email,
        },
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        return;
      }
      throw ApiException(response.status, _message(data));
    } on FunctionException catch (error) {
      throw ApiException(error.status, _message(error.details));
    }
  }

  String _message(dynamic details) {
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    if (details is String && details.trim().isNotEmpty) {
      return details.trim();
    }
    return 'Could not update the customer.';
  }
}
