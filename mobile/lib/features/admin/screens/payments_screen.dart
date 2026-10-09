import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer.dart';
import '../../../models/payment.dart';
import '../../../models/transaction.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/search_field.dart';

const _paymentMethods = ['Cash', 'Card', 'Bank transfer'];

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _searchController = TextEditingController();

  List<Payment> _payments = [];
  Map<int, Customer> _customers = {};
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
  /// filters the payment list already loaded in memory; it does not issue
  /// a new query, and it reuses the same customer lookup the list already
  /// builds to show each payment's customer name.
  List<Payment> get _filteredPayments {
    final term = _searchController.text.trim().toLowerCase();
    if (term.isEmpty) return _payments;

    return _payments.where((item) {
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
        widget.adminService.listPayments(),
        widget.adminService.listCustomers(),
      ]);
      if (!mounted) return;
      final customers = results[1] as List<Customer>;
      setState(() {
        _payments = results[0] as List<Payment>;
        _customers = {for (final customer in customers) customer.id: customer};
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load payments.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openForm({Payment? payment, String? customerName}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreatePaymentScreen(
          adminService: widget.adminService,
          payment: payment,
          customerName: customerName,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payment == null ? 'Payment added.' : 'Payment updated.')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = _filteredPayments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
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
                ? const LoadingView(message: 'Loading payments...')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: payments.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 24),
                                  EmptyView(
                                    message: _searchController.text.trim().isEmpty
                                        ? 'No payments yet. Tap Add to record one.'
                                        : 'No payments match your search.',
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: payments.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = payments[index];
                                  final customer = item.customerId == null
                                      ? null
                                      : _customers[item.customerId!];
                                  final linked = item.transactionId == null
                                      ? ''
                                      : '\nSale #${item.transactionId}';
                                  return Card(
                                    child: ListTile(
                                      title: Text(customer?.name ?? 'Customer'),
                                      subtitle: Text(
                                        '${item.paymentMethod} · ${formatDate(item.createdAt)}$linked',
                                      ),
                                      trailing: Text(formatMoney(item.amount)),
                                      onTap: () =>
                                          _openForm(payment: item, customerName: customer?.name),
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

class _CreatePaymentScreen extends StatefulWidget {
  const _CreatePaymentScreen({
    required this.adminService,
    this.payment,
    this.customerName,
  });

  final AdminService adminService;
  final Payment? payment;
  final String? customerName;

  @override
  State<_CreatePaymentScreen> createState() => _CreatePaymentScreenState();
}

class _CreatePaymentScreenState extends State<_CreatePaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  List<Customer> _customers = [];
  List<Transaction> _transactions = [];
  int? _customerId;
  int? _transactionId;
  String _method = _paymentMethods.first;
  bool _loadingOptions = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.payment != null;

  List<String> get _methods {
    if (_paymentMethods.contains(_method)) return _paymentMethods;
    return [..._paymentMethods, _method];
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.payment;
    if (existing != null) {
      _amountController.text = existing.amount.toString();
      _notesController.text = existing.notes ?? '';
      _customerId = existing.customerId;
      _transactionId = existing.transactionId;
      _method = existing.paymentMethod;
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      // An archived customer can still receive a new payment toward their
      // existing balance, so the dropdown offers both active and archived
      // customers (unlike the transaction dropdown). Editing an existing
      // payment shows the customer as read-only text instead, sourced from
      // the parent list, so this does not affect editing.
      final results = await Future.wait([
        widget.adminService.listCustomers(),
        widget.adminService.listTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = results[0] as List<Customer>;
        _transactions = results[1] as List<Transaction>;
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
        _error = 'Could not load customers and sales.';
        _loadingOptions = false;
      });
    }
  }

  List<Transaction> get _customerTransactions {
    return _transactions.where((item) => item.customerId == _customerId).toList();
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amountController.text.trim());

    if (!_editing && _customerId == null) {
      setState(() => _error = 'Choose a customer.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than 0.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = widget.payment;
      if (existing == null) {
        await widget.adminService.createPayment(
          customerId: _customerId!,
          amount: amount,
          paymentMethod: _method,
          transactionId: _transactionId,
          notes: _notesController.text.trim(),
        );
      } else {
        await widget.adminService.updatePayment(
          id: existing.id,
          amount: amount,
          paymentMethod: _method,
          transactionId: _transactionId,
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
      setState(() => _error = _editing ? 'Could not update the payment.' : 'Could not record the payment.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = _customerTransactions;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit payment' : 'Record payment')),
      body: _loadingOptions
          ? const LoadingView(message: 'Loading...')
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (!_editing && _customers.isEmpty)
                    const EmptyView(message: 'Add a customer before recording a payment.'),
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
                          DropdownMenuItem(
                            value: customer.id,
                            child: Text(
                              customer.active ? customer.name : '${customer.name} (Archived)',
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                                _customerId = value;
                                _transactionId = null;
                              }),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    key: ValueKey(_customerId),
                    initialValue: _transactionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sale (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Not linked to a sale')),
                      for (final sale in sales)
                        DropdownMenuItem<int?>(
                          value: sale.id,
                          child: Text(
                            'Sale #${sale.id} · ${formatMoney(sale.totalAmount)} · ${formatDate(sale.createdAt)}',
                          ),
                        ),
                      if (_transactionId != null && !sales.any((sale) => sale.id == _transactionId))
                        DropdownMenuItem<int?>(
                          value: _transactionId,
                          child: Text('Sale #$_transactionId'),
                        ),
                    ],
                    onChanged: _saving || _customerId == null
                        ? null
                        : (value) => setState(() => _transactionId = value),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _amountController,
                    label: 'Amount',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Payment method'),
                    items: [
                      for (final method in _methods)
                        DropdownMenuItem(value: method, child: Text(method)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _method = value);
                          },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(controller: _notesController, label: 'Notes (optional)'),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: _editing ? 'Save changes' : 'Save payment',
                    loading: _saving,
                    onPressed: !_editing && _customers.isEmpty ? null : _submit,
                  ),
                ],
              ),
            ),
    );
  }
}
