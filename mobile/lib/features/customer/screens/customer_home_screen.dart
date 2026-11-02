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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = widget.authService.currentUser?.name ?? 'Customer';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.water_drop_outlined, color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'HydraCare',
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      drawer: _CustomerDrawer(
        name: name,
        themeController: widget.themeController,
        authService: widget.authService,
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
                          Text(name, style: textTheme.headlineSmall),
                          const SizedBox(height: 16),
                          _BalanceCard(summary: _summary!),
                          const SizedBox(height: 24),
                          Text('Recent transactions', style: textTheme.titleMedium),
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
                          Text('Recent payments', style: textTheme.titleMedium),
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

// ── Balance card ──────────────────────────────────────────────────────────────

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
                const Text('Total charges'),
                Text(formatMoney(balance.totalCharges)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total payments'),
                Text(formatMoney(balance.totalPayments)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customer drawer ───────────────────────────────────────────────────────────

class _CustomerDrawer extends StatelessWidget {
  const _CustomerDrawer({
    required this.name,
    required this.themeController,
    required this.authService,
  });

  final String name;
  final ThemeController themeController;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      Icons.water_drop_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HydraCare',
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

            // ── My account (current page label) ─────────────────────────
            ListTile(
              leading: Icon(Icons.person_outline, color: colorScheme.primary),
              title: Text(
                'My account',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              visualDensity: VisualDensity.compact,
            ),

            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Divider(height: 1),
            ),

            // ── Theme toggle ────────────────────────────────────────────
            ListenableBuilder(
              listenable: themeController,
              builder: (context, _) {
                final isDark = themeController.isDark;
                return ListTile(
                  leading: Icon(
                    isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    isDark ? 'Switch to light mode' : 'Switch to dark mode',
                    style: textTheme.bodyLarge,
                  ),
                  onTap: () => themeController.setDark(!isDark),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),

            // ── Logout ──────────────────────────────────────────────────
            ListTile(
              leading: Icon(Icons.logout, color: colorScheme.error),
              title: Text(
                'Logout',
                style: textTheme.bodyLarge?.copyWith(color: colorScheme.error),
              ),
              onTap: authService.logout,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
