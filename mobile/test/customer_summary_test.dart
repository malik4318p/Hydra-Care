import 'package:flutter_test/flutter_test.dart';

import 'package:purify_mobile/models/customer_summary.dart';

void main() {
  test(
      'parses ledger balances and histories while preserving normal summary data',
      () {
    final summary = CustomerSummary.fromJson({
      'customer': {
        'id': 7,
        'user_id': 9,
        'name': 'Ledger Customer',
        'phone': '03001234567',
        'email': null,
        'role': 'customer',
        'auth_user_id': null,
        'address': null,
      },
      'balance': {
        'customer_id': 7,
        'total_charges': 100,
        'total_payments': 25,
        'outstanding_balance': 75,
      },
      'recent_transactions': [],
      'recent_payments': [],
      'security_balance': 50,
      'bottles': {'issued': 4, 'returned': 1, 'outstanding': 3},
      'security_history': [
        {
          'id': 1,
          'entry_type': 'collect',
          'amount': 50,
          'created_at': '2026-11-03T00:00:00Z',
        },
      ],
      'bottle_history': [
        {
          'id': 2,
          'product_id': 1,
          'entry_type': 'issue',
          'quantity': 4,
          'created_at': '2026-11-03T00:00:00Z',
        },
      ],
    });

    expect(summary.customer.email, isNull);
    expect(summary.balance.outstandingBalance, 75);
    expect(summary.securityBalance, 50);
    expect(summary.bottleBalance.outstanding, 3);
    expect(summary.securityHistory.single.entryType, 'collect');
    expect(summary.bottleHistory.single.productId, 1);
  });
}
