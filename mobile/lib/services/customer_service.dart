import '../models/customer_summary.dart';
import 'customer_data_service.dart';

class CustomerService {
  CustomerService({CustomerDataService? data}) : _data = data ?? CustomerDataService();

  final CustomerDataService _data;

  Future<CustomerSummary> getMySummary() => _data.getMySummary();
}
