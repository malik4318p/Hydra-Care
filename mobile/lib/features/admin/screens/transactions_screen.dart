import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer.dart';
import '../../../models/product.dart';
import '../../../models/transaction.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/search_field.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();

  List<Transaction> _transactions = [];
  Map<int, Customer> _customers = {};
  Map<int, Product> _products = {};
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

  /// Matches by customer name, phone, or email, case-insensitively. This
  /// filters the transaction list already loaded in memory; it does not
  /// issue a new query, and it reuses the same customer lookup the list
  /// already builds to show each sale's customer name.
  List<Transaction> get _filteredTransactions {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return _transactions;

    return _transactions.where((item) {
      final customer = item.customerId == null ? null : _customers[item.customerId!];
      if (customer == null) return false;
      return customer.name.toLowerCase().contains(term) ||
          customer.phone.toLowerCase().contains(term) ||
          customer.email.toLowerCase().contains(term);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.adminService.listTransactions(),
        widget.adminService.listCustomers(),
        widget.adminService.listProducts(),
      ]);
      if (!mounted) return;
      final customers = results[1] as List<Customer>;
      final products = results[2] as List<Product>;
      setState(() {
        _transactions = results[0] as List<Transaction>;
        _customers = {for (final customer in customers) customer.id: customer};
        _products = {for (final product in products) product.id: product};
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load transactions.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openForm({Transaction? transaction, String? customerName}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateTransactionScreen(
          adminService: widget.adminService,
          transaction: transaction,
          customerName: customerName,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(transaction == null ? 'Transaction added.' : 'Transaction updated.'),
        ),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _filteredTransactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          TextButton(onPressed: () => _openForm(), child: const Text('Add')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchField(
              controller: _searchController,
              hintText: 'Search customer...',
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView(message: 'Loading transactions...')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: transactions.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 24),
                                  EmptyView(
                                    message: _searchController.text.trim().isEmpty
                                        ? 'No transactions yet. Tap Add to record a sale.'
                                        : 'No transactions match your search.',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: transactions.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = transactions[index];
                                  final customer = item.customerId == null
                                      ? null
                                      : _customers[item.customerId!];
                                  final product = item.productId == null
                                      ? null
                                      : _products[item.productId!];
                                  final productName =
                                      item.productName ?? product?.name ?? 'Sale';
                                  return Card(
                                    child: ListTile(
                                      title: Text(productName),
                                      subtitle: Text(
                                        '${customer?.name ?? 'Customer'} · ${item.quantity} × ${formatMoney(item.unitPrice)}\n${formatDate(item.createdAt)}',
                                      ),
                                      isThreeLine: true,
                                      trailing: Text(formatMoney(item.totalAmount)),
                                      onTap: () => _openForm(
                                        transaction: item,
                                        customerName: customer?.name,
                                      ),
                                    ),
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

class _CreateTransactionScreen extends StatefulWidget {
  const _CreateTransactionScreen({
    required this.adminService,
    this.transaction,
    this.customerName,
  });

  final AdminService adminService;
  final Transaction? transaction;
  final String? customerName;

  @override
  State<_CreateTransactionScreen> createState() => _CreateTransactionScreenState();
}

class _CreateTransactionScreenState extends State<_CreateTransactionScreen> {
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  List<Customer> _customers = [];
  List<Product> _products = [];
  int? _customerId;
  int? _productId;
  bool _loadingOptions = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.transaction;
    if (existing != null) {
      _quantityController.text = existing.quantity.toString();
      _priceController.text = existing.unitPrice.toString();
      _notesController.text = existing.notes ?? '';
      _customerId = existing.customerId;
      _productId = existing.productId;
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      // Archived customers cannot be used for a new sale, so the dropdown
      // only offers active customers. Editing an existing sale shows the
      // customer as read-only text instead, sourced from the parent list,
      // so this filter does not affect editing.
      final results = await Future.wait([
        widget.adminService.listCustomers(activeOnly: true),
        widget.adminService.listProducts(),
      ]);
      if (!mounted) return;
      final allProducts = results[1] as List<Product>;
      final products = allProducts.where((product) => product.active).toList();
      final currentId = widget.transaction?.productId;
      if (currentId != null && !products.any((product) => product.id == currentId)) {
        final current = allProducts.where((product) => product.id == currentId);
        products.addAll(current);
      }
      if (_productId != null && !products.any((product) => product.id == _productId)) {
        _productId = null;
      }
      setState(() {
        _customers = results[0] as List<Customer>;
        _products = products;
        _loadingOptions = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load customers and products.';
        _loadingOptions = false;
      });
    }
  }

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantityController.text.trim());
    final priceText = _priceController.text.trim();
    final price = priceText.isEmpty ? null : num.tryParse(priceText);

    if ((!_editing && _customerId == null) || _productId == null) {
      setState(() => _error = 'Choose a customer and a product.');
      return;
    }
    if (quantity == null || quantity < 1) {
      setState(() => _error = 'Quantity must be a whole number of at least 1.');
      return;
    }
    if (_editing) {
      if (price == null || price <= 0) {
        setState(() => _error = 'Enter a unit price greater than 0.');
        return;
      }
    } else if (priceText.isNotEmpty && (price == null || price <= 0)) {
      setState(() => _error = 'Unit price must be greater than 0, or leave it blank.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = widget.transaction;
      if (existing == null) {
        await widget.adminService.createTransaction(
          customerId: _customerId!,
          productId: _productId!,
          quantity: quantity,
          unitPrice: price,
          notes: _notesController.text.trim(),
        );
      } else {
        await widget.adminService.updateTransaction(
          id: existing.id,
          productId: _productId!,
          quantity: quantity,
          unitPrice: price!,
          notes: _notesController.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _editing ? 'Could not update the sale.' : 'Could not record the sale.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit sale' : 'Record sale')),
      body: _loadingOptions
          ? const LoadingView(message: 'Loading...')
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (!_editing && (_customers.isEmpty || _products.isEmpty))
                    const EmptyView(
                      message: 'Add a customer and an active product before recording a sale.',
                    ),
                  if (_editing)
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Customer'),
                      child: Text(widget.customerName ?? 'Customer'),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Customer'),
                      items: [
                        for (final customer in _customers)
                          DropdownMenuItem(value: customer.id, child: Text(customer.name)),
                      ],
                      onChanged: _saving ? null : (value) => setState(() => _customerId = value),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: [
                      for (final product in _products)
                        DropdownMenuItem(
                          value: product.id,
                          child: Text('${product.name} · ${formatMoney(product.currentPrice)}'),
                        ),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _productId = value),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _quantityController,
                    label: 'Quantity',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _priceController,
                    label: _editing ? 'Unit price' : 'Unit price (optional)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(controller: _notesController, label: 'Notes (optional)'),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: _editing ? 'Save changes' : 'Save transaction',
                    loading: _saving,
                    onPressed: (_editing ? _products.isEmpty : _customers.isEmpty || _products.isEmpty)
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ),
    );
  }
}
