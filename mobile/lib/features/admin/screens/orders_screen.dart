import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/pk_date.dart';
import '../../../models/order.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import 'create_order_screen.dart';
import 'order_details_screen.dart';

typedef _OrderFetcher = Future<List<Order>> Function(
  AdminService adminService,
  DateTime startUtc,
  DateTime endUtc,
);

/// Formats the selected Pakistan-local calendar date directly from its
/// year/month/day fields. [date] is never converted through `.toLocal()`
/// here: it already holds the intended Pakistan date, and reinterpreting it
/// in the device's own time zone could shift it by a day.
String _formatSelectedDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// Total Orders: every order created on the selected day (Pakistan time),
/// regardless of delivery status. The only one of the three with an Add
/// action, since a new phone order always starts here.
class TotalOrdersScreen extends StatelessWidget {
  const TotalOrdersScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    return _OrdersListScreen(
      adminService: adminService,
      title: 'Total Orders',
      dateFilterLabel: 'Orders placed on',
      emptyMessage: 'No orders placed on this date.',
      showAddAction: true,
      fetcher: (service, startUtc, endUtc) =>
          service.listOrdersCreatedBetween(startUtc, endUtc),
    );
  }
}

/// Delivered Orders: orders actually delivered on the selected day,
/// including ones originally placed on an earlier day.
class DeliveredOrdersScreen extends StatelessWidget {
  const DeliveredOrdersScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    return _OrdersListScreen(
      adminService: adminService,
      title: 'Delivered Orders',
      dateFilterLabel: 'Delivered on',
      emptyMessage: 'No orders delivered on this date.',
      showAddAction: false,
      fetcher: (service, startUtc, endUtc) =>
          service.listOrdersDeliveredBetween(startUtc, endUtc),
    );
  }
}

/// Undelivered Orders: still-pending orders placed on the selected day.
class UndeliveredOrdersScreen extends StatelessWidget {
  const UndeliveredOrdersScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    return _OrdersListScreen(
      adminService: adminService,
      title: 'Undelivered Orders',
      dateFilterLabel: 'Placed on',
      emptyMessage: 'No pending orders placed on this date.',
      showAddAction: false,
      fetcher: (service, startUtc, endUtc) =>
          service.listPendingOrdersCreatedBetween(startUtc, endUtc),
    );
  }
}

class _OrdersListScreen extends StatefulWidget {
  const _OrdersListScreen({
    required this.adminService,
    required this.title,
    required this.dateFilterLabel,
    required this.emptyMessage,
    required this.showAddAction,
    required this.fetcher,
  });

  final AdminService adminService;
  final String title;
  final String dateFilterLabel;
  final String emptyMessage;
  final bool showAddAction;
  final _OrderFetcher fetcher;

  @override
  State<_OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<_OrdersListScreen> {
  late DateTime _selectedDate = PakistanDate.todayLocal();
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final (startUtc, endUtc) = PakistanDate.utcBoundsFor(_selectedDate);
      final orders = await widget.fetcher(widget.adminService, startUtc, endUtc);
      if (!mounted) return;
      setState(() => _orders = orders);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load orders.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isToday {
    final today = PakistanDate.todayLocal();
    return _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: PakistanDate.todayLocal(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = DateTime.utc(picked.year, picked.month, picked.day));
      await _load();
    }
  }

  Future<void> _openOrder(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          adminService: widget.adminService,
          order: order,
        ),
      ),
    );
    // The order's status may have changed (delivered) while the details
    // screen was open, so the list is always refreshed on return.
    if (mounted) await _load();
  }

  Future<void> _addOrder() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(adminService: widget.adminService),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed.')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.showAddAction)
            IconButton(
              onPressed: _addOrder,
              icon: const Icon(Icons.add),
              tooltip: 'New phone order',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      '${widget.dateFilterLabel}: ${_formatSelectedDate(_selectedDate)}'
                      '${_isToday ? ' (Today)' : ''}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView(message: 'Loading orders...')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _orders.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 24),
                                  EmptyView(message: widget.emptyMessage),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: _orders.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final order = _orders[index];
                                  return _OrderListTile(
                                    order: order,
                                    onTap: () => _openOrder(order),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _OrderListTile extends StatelessWidget {
  const _OrderListTile({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final productsSummary = order.items.isEmpty
        ? ''
        : order.items.map((item) => '${item.quantity}× ${item.productName}').join(', ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.customerName ?? 'Customer',
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Order #${order.id} · ${formatPakistanDateTime(order.createdAt)}',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              if (productsSummary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  productsSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  formatMoney(order.totalAmount),
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDelivered = status == 'delivered';
    final background =
        isDelivered ? colorScheme.primaryContainer : colorScheme.tertiaryContainer;
    final foreground =
        isDelivered ? colorScheme.onPrimaryContainer : colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isDelivered ? 'Delivered' : 'Pending',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
