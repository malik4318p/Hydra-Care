import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer.dart';
import '../../../models/customer_balance.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/search_field.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Customer> _customers = [];
  Map<int, CustomerBalance> _balances = {};
  bool _showArchived = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    setState(() {}); // Refreshes the clear button's visibility immediately.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _onFilterChanged(bool showArchived) {
    setState(() => _showArchived = showArchived);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final search = _searchController.text.trim();

    try {
      final customers = await widget.adminService.listCustomers(
        activeOnly: !_showArchived,
        search: search.isEmpty ? null : search,
      );
      final balances = await Future.wait(
        customers.map((customer) => widget.adminService.getCustomerBalance(customer.id)),
      );
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _balances = {for (final balance in balances) balance.customerId: balance};
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load customers.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openForm({Customer? customer}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CreateCustomerScreen(
          adminService: widget.adminService,
          customer: customer,
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(customer == null ? 'Customer added.' : 'Customer updated.')),
      );
      await _load();
    }
  }

  String get _emptyMessage {
    if (_searchController.text.trim().isNotEmpty) {
      return 'No customers match your search.';
    }
    return _showArchived
        ? 'No archived customers.'
        : 'No customers yet. Tap Add to create one.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          TextButton(onPressed: () => _openForm(), child: const Text('Add')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                SearchField(
                  controller: _searchController,
                  hintText: 'Search customers...',
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Active')),
                    ButtonSegment(value: true, label: Text('Archived')),
                  ],
                  selected: {_showArchived},
                  onSelectionChanged: (selection) => _onFilterChanged(selection.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView(message: 'Loading customers...')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _customers.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 24),
                                  EmptyView(message: _emptyMessage),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: _customers.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final customer = _customers[index];
                                  final balance = _balances[customer.id];
                                  return Card(
                                    child: ListTile(
                                      title: Row(
                                        children: [
                                          Expanded(child: Text(customer.name)),
                                          if (!customer.active) ...[
                                            const SizedBox(width: 8),
                                            const _ArchivedBadge(),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${customer.phone}\n${customer.email}\n${customer.address}',
                                      ),
                                      isThreeLine: true,
                                      trailing: balance == null
                                          ? null
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(formatMoney(balance.outstandingBalance)),
                                                Text(
                                                  'Due',
                                                  style: Theme.of(context).textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                      onTap: () => _openForm(customer: customer),
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

class _ArchivedBadge extends StatelessWidget {
  const _ArchivedBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Archived',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _CreateCustomerScreen extends StatefulWidget {
  const _CreateCustomerScreen({required this.adminService, this.customer});

  final AdminService adminService;
  final Customer? customer;

  @override
  State<_CreateCustomerScreen> createState() => _CreateCustomerScreenState();
}

class _CreateCustomerScreenState extends State<_CreateCustomerScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  bool _loading = false;
  bool _archiving = false;
  String? _error;
  CustomerBalance? _balance;
  bool _balanceLoading = false;
  String? _balanceError;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer == null) return;
    _nameController.text = customer.name;
    _phoneController.text = customer.phone;
    _emailController.text = customer.email;
    _addressController.text = customer.address;
    _balanceLoading = true;
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final customer = widget.customer;
    if (customer == null) return;

    try {
      final balance = await widget.adminService.getCustomerBalance(customer.id);
      if (!mounted) return;
      setState(() => _balance = balance);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _balanceError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _balanceError = 'Could not load the balance.');
    } finally {
      if (mounted) {
        setState(() => _balanceLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this customer?'),
        content: const Text(
          'Archived customers will be hidden from the active customer list and '
          'cannot be used for new transactions. Their transaction and payment '
          'history will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _setArchived(true);
  }

  Future<void> _restore() => _setArchived(false);

  Future<void> _setArchived(bool archived) async {
    final customer = widget.customer;
    if (customer == null) return;

    setState(() {
      _archiving = true;
      _error = null;
    });

    try {
      if (archived) {
        await widget.adminService.archiveCustomer(customer.id);
      } else {
        await widget.adminService.restoreCustomer(customer.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = archived
            ? 'Could not archive the customer.'
            : 'Could not restore the customer.';
      });
    } finally {
      if (mounted) {
        setState(() => _archiving = false);
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final address = _addressController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || address.isEmpty) {
      setState(() => _error = 'Name, phone, email, and address are required.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (!_editing && password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final existing = widget.customer;
      if (existing == null) {
        await widget.adminService.createCustomer(
          name: name,
          phone: phone,
          email: email,
          password: password,
          address: address,
        );
      } else {
        await widget.adminService.updateCustomer(
          id: existing.id,
          name: name,
          phone: phone,
          email: email,
          address: address,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _editing ? 'Could not update the customer.' : 'Could not add the customer.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit customer' : 'Add customer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_editing) ...[
              if (_balanceLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                )
              else if (_balance != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Outstanding balance',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatMoney(_balance!.outstandingBalance),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text('Total charges: ${formatMoney(_balance!.totalCharges)}'),
                        Text('Total payments: ${formatMoney(_balance!.totalPayments)}'),
                      ],
                    ),
                  ),
                )
              else if (_balanceError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _balanceError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            AppTextField(controller: _nameController, label: 'Name'),
            const SizedBox(height: 16),
            AppTextField(
              controller: _phoneController,
              label: 'Phone',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            if (!_editing) ...[
              const SizedBox(height: 16),
              AppTextField(
                controller: _passwordController,
                label: 'Password',
                obscureText: true,
              ),
            ],
            const SizedBox(height: 16),
            AppTextField(controller: _addressController, label: 'Address'),
            if (_editing) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _archiving
                      ? null
                      : (widget.customer!.active ? _archive : _restore),
                  icon: Icon(
                    widget.customer!.active
                        ? Icons.archive_outlined
                        : Icons.unarchive_outlined,
                  ),
                  label: Text(
                    widget.customer!.active ? 'Archive customer' : 'Restore customer',
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: _editing ? 'Save changes' : 'Save customer',
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
