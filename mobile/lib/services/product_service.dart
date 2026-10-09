import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_exception.dart';
import '../models/product.dart';

class ProductService {
  ProductService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const _columns = 'id, name, type, current_price, active';

  Future<List<Product>> listProducts() async {
    try {
      final rows = await _supabase.from('products').select(_columns).order('id');
      return rows.map((row) => Product.fromJson(_productJson(row))).toList();
    } on PostgrestException catch (error) {
      throw _asApiException(error);
    }
  }

  Future<Product> createProduct({
    required String name,
    required String type,
    required num currentPrice,
  }) async {
    _validate(name: name, type: type, currentPrice: currentPrice);

    try {
      final row = await _supabase
          .from('products')
          .insert({
            'name': name,
            'type': type,
            'current_price': currentPrice,
          })
          .select(_columns)
          .single();
      return Product.fromJson(_productJson(row));
    } on PostgrestException catch (error) {
      throw _asApiException(error);
    }
  }

  Future<Product> updateProduct({
    required int id,
    required String name,
    required String type,
    required num currentPrice,
    required bool active,
  }) async {
    _validate(name: name, type: type, currentPrice: currentPrice);

    try {
      final row = await _supabase
          .from('products')
          .update({
            'name': name,
            'type': type,
            'current_price': currentPrice,
            'active': active,
          })
          .eq('id', id)
          .select(_columns)
          .maybeSingle();

      if (row == null) {
        throw ApiException(404, 'Product not found');
      }
      return Product.fromJson(_productJson(row));
    } on PostgrestException catch (error) {
      throw _asApiException(error);
    }
  }

  void _validate({
    required String name,
    required String type,
    required num currentPrice,
  }) {
    if (name.trim().isEmpty) {
      throw ApiException(400, 'Name is required.');
    }
    if (type != 'bottle' && type != 'refill') {
      throw ApiException(400, 'Type must be bottle or refill.');
    }
    if (currentPrice <= 0) {
      throw ApiException(400, 'Enter a price greater than 0.');
    }
  }

  Map<String, dynamic> _productJson(Map<String, dynamic> row) {
    final id = row['id'];
    final price = row['current_price'];
    return {
      'id': id is int ? id : int.parse('$id'),
      'name': row['name'],
      'type': row['type'],
      'current_price': price is num ? price : num.parse('$price'),
      'active': row['active'] == true,
    };
  }

  ApiException _asApiException(PostgrestException error) {
    switch (error.code) {
      case '23505':
        return ApiException(409, 'A product with this name already exists');
      case '42501':
        return ApiException(403, 'You do not have permission to perform this action');
      case 'PGRST116':
        return ApiException(404, 'Product not found');
      default:
        final message = error.message.toLowerCase();
        if (message.contains('row-level security')) {
          return ApiException(403, 'You do not have permission to perform this action');
        }
        return ApiException(400, error.message);
    }
  }
}
