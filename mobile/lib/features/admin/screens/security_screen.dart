import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer.dart';
import '../../../models/customer_summary.dart';
import '../../../services/admin_service.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/search_field.dart';
import 'customers_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, required this.adminService});

  final AdminService adminService;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<_SecurityCustomer> _customers = [];
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
      final customers = await widget.adminService.listCustomers();
      final summaries = await Future.wait(
        customers.map(
          (customer) => widget.adminService.getCustomerSummary(customer.id),
        ),
      );
      if (!mounted) return;
      setState(() {
        _customers = [
          for (var index = 0; index < customers.length; index++)
            _SecurityCustomer(
                customer: customers[index], summary: summaries[index]),
        ];
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load security ledgers.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCustomer(Customer customer) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerDetailsScreen(
          adminService: widget.adminService,
          customer: customer,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _addSecurityCustomer() async {
    final customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SecurityCustomerSearchSheet(
        adminService: widget.adminService,
      ),
    );
    if (customer != null && mounted) {
      await _openCustomer(customer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security'),
        actions: [
          IconButton(
            onPressed: _addSecurityCustomer,
            icon: const Icon(Icons.add),
            tooltip: 'Add customer',
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading security ledgers...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _customers.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: 24),
                            EmptyView(message: 'No customers yet.'),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _customers[index];
                            final bottles = item.summary.bottleBalance;
                            return Card(
                              child: ListTile(
                                title: Text(item.customer.name),
                                subtitle: Text(
                                  'Security: ${formatMoney(item.summary.securityBalance)}\n'
                                  '19L outstanding: ${bottles.outstanding}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openCustomer(item.customer),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _SecurityCustomerSearchSheet extends StatefulWidget {
  const _SecurityCustomerSearchSheet({required this.adminService});

  final AdminService adminService;

  @override
  State<_SecurityCustomerSearchSheet> createState() =>
      _SecurityCustomerSearchSheetState();
}

class _SecurityCustomerSearchSheetState
    extends State<_SecurityCustomerSearchSheet> {
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
      // Query customers directly, rather than the security ledger, so a
      // newly registered customer with no security history is selectable.
      final customers = await widget.adminService.listCustomers(
        activeOnly: null,
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

class _SecurityCustomer {
  const _SecurityCustomer({required this.customer, required this.summary});

  final Customer customer;
  final CustomerSummary summary;
}
