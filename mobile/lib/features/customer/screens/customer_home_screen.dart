import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/format.dart';
import '../../../models/customer_summary.dart';
import '../../../services/auth_service.dart';
import '../../../services/customer_service.dart';
import '../../../widgets/empty_view.dart';
import '../../../widgets/error_view.dart';
import '../../../widgets/loading_view.dart';
import '../../../widgets/theme_toggle_button.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.authService,
    required this.customerService,
    required this.themeController,
  });

  final AuthService authService;
  final CustomerService customerService;
  final ThemeController themeController;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  CustomerSummary? _summary;
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

    var unauthorized = false;

    try {
      final summary = await widget.customerService.getMySummary();
      if (!mounted) return;
      setState(() => _summary = summary);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        unauthorized = true;
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your account.');
    } finally {
      if (mounted && !unauthorized) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.authService.currentUser?.name ?? 'Customer';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My account'),
        actions: [
          ThemeToggleButton(controller: widget.themeController),
          TextButton(
            onPressed: widget.authService.logout,
            child: const Text('Logout'),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading your account...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _summary == null
                  ? ErrorView(message: 'No account data returned.', onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(name, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 16),
                          _BalanceCard(summary: _summary!),
                          const SizedBox(height: 24),
                          Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
                          if (_summary!.recentTransactions.isEmpty)
                            const EmptyView(message: 'No transactions yet.')
                          else
                            ..._summary!.recentTransactions.map(
                              (item) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.productName ?? 'Sale'),
                                subtitle: Text(
                                  '${item.quantity} × ${formatMoney(item.unitPrice)} · ${formatDate(item.createdAt)}',
                                ),
                                trailing: Text(formatMoney(item.totalAmount)),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text('Recent payments', style: Theme.of(context).textTheme.titleMedium),
                          if (_summary!.recentPayments.isEmpty)
                            const EmptyView(message: 'No payments yet.')
                          else
                            ..._summary!.recentPayments.map(
                              (item) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.paymentMethod),
                                subtitle: Text(formatDate(item.createdAt)),
                                trailing: Text(formatMoney(item.amount)),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final balance = summary.balance;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Outstanding balance', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatMoney(balance.outstandingBalance),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total charges'),
                Text(formatMoney(balance.totalCharges)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total payments'),
                Text(formatMoney(balance.totalPayments)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
