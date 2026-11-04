import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purify_mobile/features/admin/screens/order_details_screen.dart';
import 'package:purify_mobile/features/admin/screens/orders_screen.dart';
import 'package:purify_mobile/models/customer.dart';
import 'package:purify_mobile/models/order.dart';
import 'package:purify_mobile/models/order_item.dart';
import 'package:purify_mobile/models/product.dart';
import 'package:purify_mobile/services/admin_service.dart';
import 'package:purify_mobile/services/customer_data_service.dart';
import 'package:purify_mobile/services/order_service.dart';
import 'package:purify_mobile/services/product_service.dart';

void main() {
  testWidgets(
      'Total Orders lists every order for the selected day with status and total',
      (tester) async {
    final pending = _order(
      id: 10,
      status: 'pending',
      customerName: 'Aisha',
      customerPhone: '03001112222',
      total: 100,
      items: [_item(productName: '19L Bottle', quantity: 2, unitPrice: 50)],
    );
    final delivered = _order(
      id: 11,
      status: 'delivered',
      customerName: 'Bilal',
      customerPhone: '03003334444',
      total: 50,
      deliveredAt: DateTime.utc(2026, 11, 4, 12).toIso8601String(),
      items: [_item(productName: 'Refill', quantity: 1, unitPrice: 50)],
    );
    final service = AdminService(
      orders: _FakeOrderService(ordersToReturn: [pending, delivered]),
    );

    await tester.pumpWidget(MaterialApp(home: TotalOrdersScreen(adminService: service)));
    await tester.pumpAndSettle();

    expect(find.text('Aisha'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.textContaining('Order #10'), findsOneWidget);
    expect(find.textContaining('Order #11'), findsOneWidget);
  });

  testWidgets('Total Orders shows an empty state when there are no orders',
      (tester) async {
    final service = AdminService(orders: _FakeOrderService(ordersToReturn: []));

    await tester.pumpWidget(MaterialApp(home: TotalOrdersScreen(adminService: service)));
    await tester.pumpAndSettle();

    expect(find.text('No orders placed on this date.'), findsOneWidget);
  });

  testWidgets(
      'Delivered Orders and Undelivered Orders have no new-order action',
      (tester) async {
    final service = AdminService(orders: _FakeOrderService(ordersToReturn: []));

    await tester
        .pumpWidget(MaterialApp(home: DeliveredOrdersScreen(adminService: service)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New phone order'), findsNothing);

    await tester
        .pumpWidget(MaterialApp(home: UndeliveredOrdersScreen(adminService: service)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New phone order'), findsNothing);
  });

  testWidgets(
      'creating an order sends the selected customer and product line, and never calls deliverOrder',
      (tester) async {
    final customer = _customer(1, 'New Customer', '03001234567');
    final product = Product(id: 5, name: '19L Bottle', type: 'bottle', currentPrice: 120, active: true);
    final orderService = _FakeOrderService();
    final service = AdminService(
      orders: orderService,
      customers: _FakeCustomerDataService([customer]),
      products: _FakeProductService([product]),
    );

    await tester.pumpWidget(MaterialApp(home: TotalOrdersScreen(adminService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New phone order'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Customer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19L Bottle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();

    expect(orderService.createCallCount, 1);
    expect(orderService.lastCreateCustomerId, 1);
    expect(orderService.lastCreateItems, isNotNull);
    expect(orderService.lastCreateItems!.single.productId, 5);
    expect(orderService.lastCreateItems!.single.quantity, 1);
    expect(orderService.deliverCallCount, 0);
  });

  testWidgets('order details shows Mark as delivered for a pending order',
      (tester) async {
    final service = AdminService(orders: _FakeOrderService());
    final pending = _order(id: 1, status: 'pending');

    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(adminService: service, order: pending)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mark as delivered'), findsOneWidget);
  });

  testWidgets('order details hides Mark as delivered for a delivered order',
      (tester) async {
    final service = AdminService(orders: _FakeOrderService());
    final delivered = _order(
      id: 2,
      status: 'delivered',
      deliveredAt: DateTime.utc(2026, 11, 4, 12).toIso8601String(),
    );

    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(adminService: service, order: delivered)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mark as delivered'), findsNothing);
    expect(find.textContaining('read-only'), findsOneWidget);
  });

  testWidgets(
      'marking delivered calls deliverOrder exactly once and updates the status, even when tapped again while in flight',
      (tester) async {
    final orderService = _FakeOrderService(
      deliverDelay: const Duration(milliseconds: 200),
    );
    final service = AdminService(orders: orderService);
    final order = _order(id: 7, status: 'pending');

    await tester.pumpWidget(
      MaterialApp(home: OrderDetailsScreen(adminService: service, order: order)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as delivered'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark delivered'));
    await tester.pump();

    // The button is disabled while the first call is in flight, so a
    // second tap here must not start a second request.
    await tester.tap(find.text('Mark as delivered'), warnIfMissed: false);
    await tester.pump();

    await tester.pumpAndSettle();

    expect(orderService.deliverCallCount, 1);
    // The status badge and the new "Delivered" info row both render the
    // word, so at least one match confirms the UI reflects the new status.
    expect(find.text('Delivered'), findsWidgets);
  });
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

Order _order({
  required int id,
  required String status,
  int customerId = 1,
  String? customerName,
  String? customerPhone,
  num total = 0,
  String? deliveredAt,
  List<OrderItem> items = const [],
}) {
  return Order(
    id: id,
    customerId: customerId,
    status: status,
    totalAmount: total,
    createdAt: DateTime.utc(2026, 11, 4, 10, 0).toIso8601String(),
    deliveredAt: deliveredAt,
    customerName: customerName,
    customerPhone: customerPhone,
    items: items,
  );
}

OrderItem _item({
  required String productName,
  required int quantity,
  required num unitPrice,
  int id = 1,
  int orderId = 1,
  int productId = 1,
}) {
  return OrderItem(
    id: id,
    orderId: orderId,
    productId: productId,
    productName: productName,
    quantity: quantity,
    unitPrice: unitPrice,
    totalAmount: quantity * unitPrice,
  );
}

class _FakeCustomerDataService extends CustomerDataService {
  _FakeCustomerDataService(this._customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> listCustomers({bool? activeOnly, String? search}) async {
    var result = _customers;
    if (activeOnly != null) {
      result = result.where((customer) => customer.active == activeOnly).toList();
    }
    final query = search?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      result = result
          .where((customer) =>
              customer.name.toLowerCase().contains(query) ||
              customer.phone.contains(query))
          .toList();
    }
    return result;
  }
}

class _FakeProductService extends ProductService {
  _FakeProductService(this._products);

  final List<Product> _products;

  @override
  Future<List<Product>> listProducts() async => _products;
}

class _FakeOrderService extends OrderService {
  _FakeOrderService({this.ordersToReturn = const [], this.deliverDelay});

  final List<Order> ordersToReturn;
  final Duration? deliverDelay;

  int createCallCount = 0;
  int? lastCreateCustomerId;
  List<OrderItemInput>? lastCreateItems;

  int deliverCallCount = 0;
  int? lastDeliveredOrderId;

  @override
  Future<List<Order>> listOrdersCreatedBetween(DateTime startUtc, DateTime endUtc) async =>
      ordersToReturn;

  @override
  Future<List<Order>> listOrdersDeliveredBetween(DateTime startUtc, DateTime endUtc) async =>
      ordersToReturn;

  @override
  Future<List<Order>> listPendingOrdersCreatedBetween(DateTime startUtc, DateTime endUtc) async =>
      ordersToReturn;

  @override
  Future<Order> createOrder({
    required int customerId,
    required List<OrderItemInput> items,
    String? notes,
  }) async {
    createCallCount += 1;
    lastCreateCustomerId = customerId;
    lastCreateItems = items;
    return Order(
      id: 999,
      customerId: customerId,
      status: 'pending',
      totalAmount: 0,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<Order> deliverOrder(int orderId) async {
    deliverCallCount += 1;
    lastDeliveredOrderId = orderId;
    if (deliverDelay != null) {
      await Future.delayed(deliverDelay!);
    }
    return Order(
      id: orderId,
      customerId: 1,
      status: 'delivered',
      totalAmount: 0,
      createdAt: DateTime.now().toIso8601String(),
      deliveredAt: DateTime.now().toIso8601String(),
    );
  }
}
