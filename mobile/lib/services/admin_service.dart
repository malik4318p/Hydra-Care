import '../models/customer.dart';
import '../models/customer_balance.dart';
import '../models/payment.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import 'customer_create_service.dart';
import 'customer_data_service.dart';
import 'customer_email_service.dart';
import 'payment_service.dart';
import 'product_service.dart';
import 'transaction_service.dart';

class AdminService {
  AdminService({
    ProductService? products,
    CustomerDataService? customers,
    TransactionService? transactions,
    PaymentService? payments,
    CustomerEmailService? emails,
    CustomerCreateService? accounts,
  })  : _products = products ?? ProductService(),
        _customers = customers ?? CustomerDataService(),
        _transactions = transactions ?? TransactionService(),
        _payments = payments ?? PaymentService(),
        _emails = emails ?? CustomerEmailService(),
        _accounts = accounts ?? CustomerCreateService();

  final ProductService _products;
  final CustomerDataService _customers;
  final TransactionService _transactions;
  final PaymentService _payments;
  final CustomerEmailService _emails;
  final CustomerCreateService _accounts;

  Future<List<Customer>> listCustomers({bool? activeOnly, String? search}) {
    return _customers.listCustomers(activeOnly: activeOnly, search: search);
  }

  Future<CustomerBalance> getCustomerBalance(int id) {
    return _customers.getCustomerBalance(id);
  }

  Future<void> archiveCustomer(int id) => _customers.archiveCustomer(id);

  Future<void> restoreCustomer(int id) => _customers.restoreCustomer(id);

  Future<Customer> createCustomer({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String address,
  }) async {
    return _accounts.createCustomer(
      name: name,
      phone: phone,
      email: email,
      password: password,
      address: address,
    );
  }

  Future<Customer> updateCustomer({
    required int id,
    required String name,
    required String phone,
    required String email,
    required String address,
  }) async {
    final currentEmail = await _customers.customerEmail(id);
    if (currentEmail != email) {
      await _emails.changeCustomerEmail(customerId: id, email: email);
    }
    await _customers.updateNameAndPhone(id: id, name: name, phone: phone);
    return _customers.updateAddress(id: id, address: address);
  }

  Future<List<Product>> listProducts() => _products.listProducts();

  Future<Product> createProduct({
    required String name,
    required String type,
    required num currentPrice,
  }) {
    return _products.createProduct(
      name: name,
      type: type,
      currentPrice: currentPrice,
    );
  }

  Future<Product> updateProduct({
    required int id,
    required String name,
    required String type,
    required num currentPrice,
    required bool active,
  }) {
    return _products.updateProduct(
      id: id,
      name: name,
      type: type,
      currentPrice: currentPrice,
      active: active,
    );
  }

  Future<List<Transaction>> listTransactions() => _transactions.listTransactions();

  Future<Transaction> createTransaction({
    required int customerId,
    required int productId,
    required int quantity,
    num? unitPrice,
    String? notes,
  }) {
    return _transactions.createTransaction(
      customerId: customerId,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
    );
  }

  Future<Transaction> updateTransaction({
    required int id,
    required int productId,
    required int quantity,
    required num unitPrice,
    String? notes,
  }) {
    return _transactions.updateTransaction(
      id: id,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
    );
  }

  Future<List<Payment>> listPayments() => _payments.listPayments();

  Future<Payment> createPayment({
    required int customerId,
    required num amount,
    required String paymentMethod,
    int? transactionId,
    String? notes,
  }) {
    return _payments.createPayment(
      customerId: customerId,
      amount: amount,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      notes: notes,
    );
  }

  Future<Payment> updatePayment({
    required int id,
    required num amount,
    required String paymentMethod,
    required int? transactionId,
    String? notes,
  }) {
    return _payments.updatePayment(
      id: id,
      amount: amount,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      notes: notes,
    );
  }
}
