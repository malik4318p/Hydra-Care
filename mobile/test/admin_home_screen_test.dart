import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purify_mobile/core/storage/token_storage.dart';
import 'package:purify_mobile/core/theme/theme_controller.dart';
import 'package:purify_mobile/features/admin/screens/admin_home_screen.dart';
import 'package:purify_mobile/models/customer.dart';
import 'package:purify_mobile/models/order.dart';
import 'package:purify_mobile/models/product.dart';
import 'package:purify_mobile/models/sales_metric.dart';
import 'package:purify_mobile/models/transaction.dart';
import 'package:purify_mobile/services/admin_service.dart';
import 'package:purify_mobile/services/auth_service.dart';
import 'package:purify_mobile/services/customer_data_service.dart';
import 'package:purify_mobile/services/order_service.dart';
import 'package:purify_mobile/services/product_service.dart';
import 'package:purify_mobile/services/today_sales_service.dart';
import 'package:purify_mobile/services/transaction_service.dart';

void main() {
  late _FakeTodaySalesService todaySales;
  late AdminService adminService;

  setUp(() {
    todaySales = _FakeTodaySalesService();
    adminService = AdminService(
      todaySales: todaySales,
      products: _FakeProductService(),
      transactions: _FakeTransactionService(),
      customers: _FakeCustomerDataService(),
      orders: _FakeOrderService(),
    );
  });

  Widget buildApp() {
    return MaterialApp(
      home: AdminHomeScreen(
        authService: AuthService(tokenStorage: TokenStorage()),
        adminService: adminService,
        themeController: ThemeController(),
      ),
    );
  }

  // The default test surface (800x600) is shorter than any real phone and
  // is too short for the drawer's full item list (pre-existing; unrelated
  // to the refresh fix under test here). Widen it only for this test file
  // so the drawer actually renders instead of overflowing.
  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
  }

  Future<void> openDrawerAndTap(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'reloads Today\'s Sales once after returning from Transactions',
      (tester) async {
    await pumpDashboard(tester);
    expect(todaySales.callCount, 1, reason: 'initial dashboard load');

    await openDrawerAndTap(tester, 'Transactions');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(todaySales.callCount, 2);
  });

  testWidgets(
      'reloads Today\'s Sales once after returning from Total Orders '
      '(a delivered order also lands in transactions)', (tester) async {
    await pumpDashboard(tester);
    expect(todaySales.callCount, 1);

    await openDrawerAndTap(tester, 'Total Orders');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(todaySales.callCount, 2);
  });

  testWidgets(
      'does not reload Today\'s Sales after returning from Products, '
      'which cannot affect it', (tester) async {
    await pumpDashboard(tester);
    expect(todaySales.callCount, 1);

    await openDrawerAndTap(tester, 'Products');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(todaySales.callCount, 1);
  });

  testWidgets(
      'does not reload Today\'s Sales again while the dashboard stays visible',
      (tester) async {
    await pumpDashboard(tester);
    expect(todaySales.callCount, 1);

    // Typing in the customer search box must not trigger another sales load.
    await tester.enterText(find.byType(TextField).first, 'anything');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(todaySales.callCount, 1);
  });
}

class _FakeTodaySalesService extends TodaySalesService {
  int callCount = 0;

  @override
  Future<List<SalesMetric>> listTodaySalesByProduct() async {
    callCount += 1;
    return const [];
  }
}

class _FakeProductService extends ProductService {
  @override
  Future<List<Product>> listProducts() async => const [];
}

class _FakeTransactionService extends TransactionService {
  @override
  Future<List<Transaction>> listTransactions() async => const [];
}

class _FakeCustomerDataService extends CustomerDataService {
  @override
  Future<List<Customer>> listCustomers({bool? activeOnly, String? search}) async =>
      const [];
}

class _FakeOrderService extends OrderService {
  @override
  Future<List<Order>> listOrdersCreatedBetween(DateTime startUtc, DateTime endUtc) async =>
      const [];

  @override
  Future<List<Order>> listOrdersDeliveredBetween(DateTime startUtc, DateTime endUtc) async =>
      const [];

  @override
  Future<List<Order>> listPendingOrdersCreatedBetween(DateTime startUtc, DateTime endUtc) async =>
      const [];
}
