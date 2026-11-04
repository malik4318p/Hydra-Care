import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/sales_metric.dart';

class TodaySalesService {
  TodaySalesService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<SalesMetric>> listTodaySalesByProduct() async {
    try {
      // Pakistan Standard Time is UTC+05:00 and has no DST. Build today's
      // local midnight in UTC, then query the timestamptz column using the
      // equivalent UTC half-open interval.
      final pakistanNow = DateTime.now().toUtc().add(const Duration(hours: 5));
      final pakistanMidnight = DateTime.utc(
        pakistanNow.year,
        pakistanNow.month,
        pakistanNow.day,
      );
      final startUtc = pakistanMidnight.subtract(const Duration(hours: 5));
      final endUtc = startUtc.add(const Duration(days: 1));

      final rows = await _supabase
          .from('transactions')
          .select(
              'product_id, quantity, total_amount, products!fk_transactions_product(name)')
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String());

      final grouped = <int, SalesMetric>{};
      for (final raw in rows) {
        final row = _map(raw);
        final productId = _asInt(row['product_id']);
        final product = row['products'];
        final productName = product is Map && product['name'] is String
            ? product['name'] as String
            : 'Product #$productId';
        final current = grouped[productId];
        grouped[productId] = SalesMetric(
          productId: productId,
          productName: current?.productName ?? productName,
          quantity: (current?.quantity ?? 0) + _asInt(row['quantity']),
          totalAmount:
              (current?.totalAmount ?? 0) + _asNum(row['total_amount']),
        );
      }

      final metrics = grouped.values.toList()
        ..sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
      return metrics;
    } on PostgrestException catch (error) {
      throw ApiException(400, error.message);
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry('$key', item));
    throw ApiException(0, 'Response was not valid');
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse('$value');
  }

  num _asNum(dynamic value) {
    if (value is num) return value;
    return num.parse('$value');
  }
}
