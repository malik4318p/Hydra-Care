import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/order.dart';
import '../../../services/admin_service.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.adminService, required this.order});

  final AdminService adminService;
  final Order order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late Order _order;
  bool _delivering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _confirmDeliver() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as delivered?'),
        content: Text(
          'This records the sale for ${_order.customerName ?? 'this customer'} '
          'and cannot be undone from here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark delivered'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deliver();
    }
  }

  Future<void> _deliver() async {
    // Guards against a double-tap triggering delivery twice from the UI
    // side. The database-level unique constraint on
    // transactions.order_item_id is the real duplicate-prevention guard;
    // this is only to avoid a second in-flight request.
    if (_delivering || !_order.isPending) return;

    setState(() {
      _delivering = true;
      _error = null;
    });

    try {
      final updated = await widget.adminService.deliverOrder(_order.id);
      if (!mounted) return;
      setState(() {
        _order = _order.copyWith(
          status: updated.status,
          deliveredAt: updated.deliveredAt,
          updatedAt: updated.updatedAt,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order marked as delivered.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not mark the order as delivered.');
    } finally {
      if (mounted) setState(() => _delivering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('Order #${_order.id}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _order.customerName ?? 'Customer',
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusBadge(status: _order.status),
              ],
            ),
            if (_order.customerPhone != null) ...[
              const SizedBox(height: 2),
              Text(
                _order.customerPhone!,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            _InfoRow(label: 'Placed', value: formatPakistanDateTime(_order.createdAt)),
            if (_order.isDelivered)
              _InfoRow(
                label: 'Delivered',
                value: formatPakistanDateTime(_order.deliveredAt),
              ),
            const SizedBox(height: 16),
            Text('Products', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._order.items.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item.productName),
                  subtitle: Text('${item.quantity} × ${formatMoney(item.unitPrice)}'),
                  trailing: Text(
                    formatMoney(item.totalAmount),
                    style: textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${formatMoney(_order.totalAmount)}',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (_order.notes != null && _order.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_order.notes!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: colorScheme.error)),
            ],
            const SizedBox(height: 24),
            if (_order.isPending)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _delivering ? null : _confirmDeliver,
                  icon: _delivering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_shipping_outlined),
                  label: const Text('Mark as delivered'),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'This order is delivered and read-only.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isDelivered ? 'Delivered' : 'Pending',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
