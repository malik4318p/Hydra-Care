import 'customer.dart';
import 'customer_balance.dart';
import 'customer_ledger.dart';
import 'payment.dart';
import 'transaction.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.customer,
    required this.balance,
    required this.recentTransactions,
    required this.recentPayments,
    this.securityBalance = 0,
    this.bottleBalance =
        const CustomerBottleBalance(issued: 0, returned: 0, outstanding: 0),
    this.securityHistory = const [],
    this.bottleHistory = const [],
  });

  final Customer customer;
  final CustomerBalance balance;
  final List<Transaction> recentTransactions;
  final List<Payment> recentPayments;
  final num securityBalance;
  final CustomerBottleBalance bottleBalance;
  final List<CustomerSecurityActivity> securityHistory;
  final List<CustomerBottleActivity> bottleHistory;

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    final transactions = json['recent_transactions'] as List<dynamic>? ?? [];
    final payments = json['recent_payments'] as List<dynamic>? ?? [];
    final securityHistory = json['security_history'] as List<dynamic>? ?? [];
    final bottleHistory = json['bottle_history'] as List<dynamic>? ?? [];

    return CustomerSummary(
      customer: Customer.fromJson(json['customer'] as Map<String, dynamic>),
      balance:
          CustomerBalance.fromJson(json['balance'] as Map<String, dynamic>),
      recentTransactions: transactions
          .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
          .toList(),
      recentPayments: payments
          .map((item) => Payment.fromJson(item as Map<String, dynamic>))
          .toList(),
      securityBalance: json['security_balance'] as num? ?? 0,
      bottleBalance: CustomerBottleBalance.fromJson(
        json['bottles'] as Map<String, dynamic>?,
      ),
      securityHistory: securityHistory
          .map((item) =>
              CustomerSecurityActivity.fromJson(item as Map<String, dynamic>))
          .toList(),
      bottleHistory: bottleHistory
          .map((item) =>
              CustomerBottleActivity.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
