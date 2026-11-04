import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/format.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../models/customer.dart';
import '../../../models/sales_metric.dart';
import '../../../services/admin_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/brand_mark.dart';
import 'customers_screen.dart';
import 'orders_screen.dart';
import 'payments_screen.dart';
import 'products_screen.dart';
import 'security_screen.dart';
import 'transactions_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({
    super.key,
    required this.authService,
    required this.adminService,
    required this.themeController,
  });

  final AuthService authService;
  final AdminService adminService;
  final ThemeController themeController;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Customer> _results = [];
  bool _loading = false;
  bool _searched = false; // true once user has typed something
  String? _error;
  List<SalesMetric> _todaySales = [];
  bool _salesLoading = true;
  String? _salesError;

  @override
  void initState() {
    super.initState();
    _loadTodaySales();
  }

  Future<void> _loadTodaySales() async {
    setState(() {
      _salesLoading = true;
      _salesError = null;
    });
    try {
      final sales = await widget.adminService.listTodaySalesByProduct();
      if (!mounted) return;
      setState(() => _todaySales = sales);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _salesError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salesError = 'Could not load today\'s sales.');
    } finally {
      if (mounted) setState(() => _salesLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _error = null;
    });

    _debounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final customers = await widget.adminService.listCustomers(search: query);
      if (!mounted) return;
      setState(() => _results = customers);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not search customers.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openCustomer(Customer customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomersScreen(
          adminService: widget.adminService,
          initialCustomer: customer,
        ),
      ),
    );
  }

  Future<void> _navigate(Widget screen) async {
    Navigator.of(context).pop(); // close drawer
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    // Today's Sales reads straight from `transactions`, and only these
    // destinations can add a row there: Transactions directly, or an order
    // screen if the admin delivers a pending order from within it (at any
    // navigation depth — this still awaits until we're back here). Every
    // other drawer destination (Customers, Products, Payments, Security)
    // cannot affect it, so skip the reload for those.
    final affectsTodaySales = screen is TransactionsScreen ||
        screen is TotalOrdersScreen ||
        screen is DeliveredOrdersScreen ||
        screen is UndeliveredOrdersScreen;
    if (affectsTodaySales && mounted) {
      await _loadTodaySales();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = widget.authService.currentUser?.name ?? 'Admin';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 28),
            const SizedBox(width: 8),
            Text(
              'HydraCure',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      drawer: _AppDrawer(
        name: name,
        themeController: widget.themeController,
        authService: widget.authService,
        onNavigate: _navigate,
        adminService: widget.adminService,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search card ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer search',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Find a customer by name or phone number.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SearchField(
                  controller: _searchController,
                  hintText: 'Search by name or phone…',
                  onChanged: _onSearchChanged,
                ),
              ],
            ),
          ),

          _TodaySalesCard(
            sales: _todaySales,
            loading: _salesLoading,
            error: _salesError,
            onRetry: _loadTodaySales,
          ),

          const SizedBox(height: 8),

          // ── Results area ─────────────────────────────────────────────────
          Expanded(
            child: _buildBody(colorScheme, textTheme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, TextTheme textTheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _search, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 56,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Start typing to search customers',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 56,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No customers found',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final customer = _results[index];
        return _CustomerResultTile(
          customer: customer,
          onTap: () => _openCustomer(customer),
        );
      },
    );
  }
}

class _TodaySalesCard extends StatelessWidget {
  const _TodaySalesCard({
    required this.sales,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<SalesMetric> sales;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final soldProducts = sales
        .where((item) => item.quantity > 0 && item.totalAmount > 0)
        .toList(growable: false);
    final total =
        soldProducts.fold<num>(0, (sum, item) => sum + item.totalAmount);
    final units = soldProducts.fold<int>(0, (sum, item) => sum + item.quantity);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Today\'s sales · Pakistan',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (error != null)
                          IconButton(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                          ),
                      ],
                    ),
                    if (loading)
                      const LinearProgressIndicator()
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _SalesSummaryMetric(
                              label: 'Total sales',
                              value: formatMoney(total),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _SalesSummaryMetric(
                              label: 'Total units',
                              value: '$units',
                            ),
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ] else if (soldProducts.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('No sales recorded today.'),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (!loading && error == null)
              ...soldProducts.map(
                (item) => _ProductSalesCard(metric: item),
              ),
          ],
        ),
      ),
    );
  }
}

class _SalesSummaryMetric extends StatelessWidget {
  const _SalesSummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _ProductSalesCard extends StatelessWidget {
  const _ProductSalesCard({required this.metric});

  final SalesMetric metric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.productName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SalesSummaryMetric(
                      label: 'Quantity sold',
                      value: '${metric.quantity}',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SalesSummaryMetric(
                      label: 'Sales amount',
                      value: formatMoney(metric.totalAmount),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Customer result tile ──────────────────────────────────────────────────────

class _CustomerResultTile extends StatelessWidget {
  const _CustomerResultTile({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!customer.active) ...[
                          const SizedBox(width: 8),
                          _ArchivedChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.phone,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchivedChip extends StatelessWidget {
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

// ── Navigation drawer ─────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.name,
    required this.themeController,
    required this.authService,
    required this.onNavigate,
    required this.adminService,
  });

  final String name;
  final ThemeController themeController;
  final AuthService authService;
  final void Function(Widget screen) onNavigate;
  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    child: const BrandMark(size: 40),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HydraCure',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          name,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Divider(height: 1),
            ),

            // ── Nav items ───────────────────────────────────────────────
            _DrawerItem(
              icon: Icons.people_outline,
              label: 'Customers',
              onTap: () =>
                  onNavigate(CustomersScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.inventory_2_outlined,
              label: 'Products',
              onTap: () =>
                  onNavigate(ProductsScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.receipt_long_outlined,
              label: 'Transactions',
              onTap: () =>
                  onNavigate(TransactionsScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.payments_outlined,
              label: 'Payments',
              onTap: () =>
                  onNavigate(PaymentsScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.list_alt_outlined,
              label: 'Total Orders',
              onTap: () =>
                  onNavigate(TotalOrdersScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.local_shipping_outlined,
              label: 'Delivered Orders',
              onTap: () => onNavigate(
                  DeliveredOrdersScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.pending_actions_outlined,
              label: 'Undelivered Orders',
              onTap: () => onNavigate(
                  UndeliveredOrdersScreen(adminService: adminService)),
            ),
            _DrawerItem(
              icon: Icons.shield_outlined,
              label: 'Security',
              onTap: () =>
                  onNavigate(SecurityScreen(adminService: adminService)),
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Divider(height: 1),
            ),

            // ── Theme toggle ─────────────────────────────────────────────
            ListenableBuilder(
              listenable: themeController,
              builder: (context, _) {
                final isDark = themeController.isDark;
                return _DrawerItem(
                  icon: isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  label:
                      isDark ? 'Switch to light mode' : 'Switch to dark mode',
                  onTap: () => themeController.setDark(!isDark),
                );
              },
            ),

            // ── Logout ───────────────────────────────────────────────────
            _DrawerItem(
              icon: Icons.logout,
              label: 'Logout',
              iconColor: colorScheme.error,
              labelColor: colorScheme.error,
              onTap: authService.logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: labelColor,
            ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}
