import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purify_mobile/features/admin/screens/security_screen.dart';
import 'package:purify_mobile/models/customer.dart';
import 'package:purify_mobile/models/customer_balance.dart';
import 'package:purify_mobile/models/customer_summary.dart';
import 'package:purify_mobile/services/admin_service.dart';
import 'package:purify_mobile/services/customer_data_service.dart';

void main() {
  final existingCustomer = _customer(1, 'Existing Customer', '03000000001');
  final newCustomer = _customer(2, 'New Customer', '03000000002');

  testWidgets('returns to Security after opening an existing customer',
      (tester) async {
    final service = _adminService([existingCustomer]);
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Existing Customer'));
    await tester.pumpAndSettle();
    expect(find.text('Edit customer'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Security'), findsOneWidget);
  });

  testWidgets('searches all customers from Add and opens security operations',
      (tester) async {
    final service = _adminService([existingCustomer, newCustomer]);
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add customer'));
    await tester.pumpAndSettle();
    expect(find.text('Select customer'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'New Customer');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final pickerCustomer = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(ListTile, 'New Customer'),
    );
    expect(pickerCustomer, findsOneWidget);

    await tester.tap(pickerCustomer);
    await tester.pumpAndSettle();
    expect(find.text('Customer ledger'), findsOneWidget);
    expect(find.text('Collect security'), findsOneWidget);
    expect(find.text('Issue 19L bottles'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Security'), findsOneWidget);
  });
}

MaterialApp _app(AdminService service) {
  return MaterialApp(home: SecurityScreen(adminService: service));
}

AdminService _adminService(List<Customer> customers) {
  return AdminService(
    customers: _FakeCustomerDataService(customers),
  );
}

Customer _customer(int id, String name, String phone) {
  return Customer(
    id: id,
    userId: id,
    name: name,
    phone: phone,
    email: null,
    role: 'customer',
    address: null,
    active: true,
  );
}

class _FakeCustomerDataService extends CustomerDataService {
  _FakeCustomerDataService(this._customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> listCustomers(
      {bool? activeOnly, String? search}) async {
    final query = search?.trim().toLowerCase();
    if (query == null || query.isEmpty) return _customers;
    return _customers
        .where((customer) =>
            customer.name.toLowerCase().contains(query) ||
            customer.phone.toLowerCase().contains(query))
        .toList();
  }

  @override
  Future<CustomerSummary> getCustomerSummary(int customerId) async {
    final customer = _customers.firstWhere((item) => item.id == customerId);
    return CustomerSummary(
      customer: customer,
      balance: CustomerBalance(
        customerId: customerId,
        totalCharges: 0,
        totalPayments: 0,
        outstandingBalance: 0,
      ),
      recentTransactions: const [],
      recentPayments: const [],
    );
  }
}
