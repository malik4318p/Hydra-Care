import 'customer.dart';
import 'customer_balance.dart';
import 'payment.dart';
import 'transaction.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.balance,
    required this.recentTransactions,
    required this.recentPayments,
  });

  final Customer customer;
  final CustomerBalance balance;
  final List<Transaction> recentTransactions;
  final List<Payment> recentPayments;

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    final transactions = json['recent_transactions'] as List<dynamic>? ?? [];
    final payments = json['recent_payments'] as List<dynamic>? ?? [];

    return CustomerSummary(
      customer: Customer.fromJson(json['customer'] as Map<String, dynamic>),
      balance: CustomerBalance.fromJson(json['balance'] as Map<String, dynamic>),
      recentTransactions: transactions
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList(),
      recentPayments: payments
          .map((item) => Payment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
