import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer.dart';
import '../../../models/product.dart';
import '../../../services/admin_service.dart';
import '../../../services/order_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/search_field.dart';

/// One product line being built up on the new-order screen, before it is
/// sent to the server. Unit price is shown for the admin's benefit only —
/// the server re-reads `products.current_price` itself when the order is
/// created and snapshots it there, so this value is never sent as-is.
class _DraftLine {
  _DraftLine({required this.product, required this.quantity});

  final Product product;
  int quantity;

  num get lineTotal => quantity * product.currentPrice;
}

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _notesController = TextEditingController();

  Customer? _customer;
  final List<_DraftLine> _lines = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  num get _orderTotal =>
      _lines.fold<num>(0, (sum, line) => sum + line.lineTotal);

  Future<void> _pickCustomer() async {
    final customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _OrderCustomerSearchSheet(adminService: widget.adminService),
    );
    if (customer != null && mounted) {
      setState(() {
        _customer = customer;
        _error = null;
      });
    }
  }

  Future<void> _addProduct() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(adminService: widget.adminService),
    );
    if (product == null || !mounted) return;

    setState(() {
      _error = null;
      final existing = _lines.where((line) => line.product.id == product.id);
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
      } else {
        _lines.add(_DraftLine(product: product, quantity: 1));
      }
    });
  }

  void _incrementLine(_DraftLine line) {
    setState(() => line.quantity += 1);
  }

  void _decrementLine(_DraftLine line) {
    setState(() {
      if (line.quantity > 1) {
        line.quantity -= 1;
      } else {
        _lines.remove(line);
      }
    });
  }

  void _removeLine(_DraftLine line) {
    setState(() => _lines.remove(line));
  }

  Future<void> _submit() async {
    if (_customer == null) {
      setState(() => _error = 'Choose a customer.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.adminService.createOrder(
        customerId: _customer!.id,
        items: [
          for (final line in _lines)
            OrderItemInput(productId: line.product.id, quantity: line.quantity),
        ],
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not create the order.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New phone order')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Customer', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_customer?.name ?? 'Choose a customer'),
                subtitle: _customer == null ? null : Text(_customer!.phone),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving ? null : _pickCustomer,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Products', style: textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: _saving ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
              ],
            ),
            if (_lines.isEmpty)
              const EmptyView(message: 'No products added yet.')
            else
              ..._lines.map(
                (line) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.product.name,
                                style: textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${formatMoney(line.product.currentPrice)} each · ${formatMoney(line.lineTotal)} total',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _saving ? null : () => _decrementLine(line),
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Decrease quantity',
                        ),
                        Text('${line.quantity}', style: textTheme.titleMedium),
                        IconButton(
                          onPressed: _saving ? null : () => _incrementLine(line),
                          icon: const Icon(Icons.add_circle_outline),
                          tooltip: 'Increase quantity',
                        ),
                        IconButton(
                          onPressed: _saving ? null : () => _removeLine(line),
                          icon: Icon(Icons.close, color: colorScheme.error),
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Order total: ${formatMoney(_orderTotal)}',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _notesController,
              label: 'Notes (optional)',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: colorScheme.error)),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: 'Save order',
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customer search sheet ───────────────────────────────────────────────────

class _OrderCustomerSearchSheet extends StatefulWidget {
  const _OrderCustomerSearchSheet({required this.adminService});

  final AdminService adminService;

  @override
  State<_OrderCustomerSearchSheet> createState() =>
      _OrderCustomerSearchSheetState();
}

class _OrderCustomerSearchSheetState extends State<_OrderCustomerSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Customer> _customers = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    setState(() {
      _error = null;
      _loading = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final request = ++_request;
    final query = _searchController.text.trim();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Only active customers can be used for a new sale.
      final customers = await widget.adminService.listCustomers(
        activeOnly: true,
        search: query.isEmpty ? null : query,
      );
      if (!mounted || request != _request) return;
      setState(() => _customers = customers);
    } on ApiException catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = 'Could not search customers.');
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .82;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select customer',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              SearchField(
                controller: _searchController,
                hintText: 'Search by name or phone...',
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const LoadingView(message: 'Searching customers...')
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _search)
                        : _customers.isEmpty
                            ? const EmptyView(
                                message: 'No customers match your search.',
                              )
                            : ListView.separated(
                                itemCount: _customers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final customer = _customers[index];
                                  return Card(
                                    child: ListTile(
                                      title: Text(customer.name),
                                      subtitle: Text(customer.phone),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          Navigator.of(context).pop(customer),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Product picker sheet ────────────────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.adminService});

  final AdminService adminService;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchController = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> get _filtered {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return _products;
    return _products
        .where((product) => product.name.toLowerCase().contains(term))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.adminService.listProducts();
      if (!mounted) return;
      setState(() {
        // Only active products can be added to a new phone order.
        _products = products.where((product) => product.active).toList();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load products.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .82;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add product',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              SearchField(
                controller: _searchController,
                hintText: 'Search products...',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const LoadingView(message: 'Loading products...')
                    : _error != null
                        ? ErrorView(message: _error!, onRetry: _load)
                        : _filtered.isEmpty
                            ? const EmptyView(message: 'No products available.')
                            : ListView.separated(
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final product = _filtered[index];
                                  return Card(
                                    child: ListTile(
                                      title: Text(product.name),
                                      subtitle:
                                          Text(formatMoney(product.currentPrice)),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          Navigator.of(context).pop(product),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
