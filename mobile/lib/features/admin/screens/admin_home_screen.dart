import 'package:flutter/material.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../services/admin_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/theme_toggle_button.dart';
import 'customers_screen.dart';
import 'payments_screen.dart';
import 'products_screen.dart';
import 'transactions_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    required this.authService,
    required this.adminService,
    required this.themeController,
  });

  final AuthService authService;
  final AdminService adminService;
  final ThemeController themeController;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final name = authService.currentUser?.name ?? 'Admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          ThemeToggleButton(controller: themeController),
          TextButton(
            onPressed: authService.logout,
            child: const Text('Logout'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Hello, $name', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Record customers, products, sales, and payments.'),
          const SizedBox(height: 24),
          _ActionTile(
            icon: Icons.people_outline,
            title: 'Customers',
            subtitle: 'Create and review customer accounts',
            onTap: () => _open(
              context,
              CustomersScreen(adminService: adminService),
            ),
          ),
          _ActionTile(
            icon: Icons.inventory_2_outlined,
            title: 'Products',
            subtitle: 'Bottles and refills',
            onTap: () => _open(
              context,
              ProductsScreen(adminService: adminService),
            ),
          ),
          _ActionTile(
            icon: Icons.receipt_long_outlined,
            title: 'Transactions',
            subtitle: 'Record a sale',
            onTap: () => _open(
              context,
              TransactionsScreen(adminService: adminService),
            ),
          ),
          _ActionTile(
            icon: Icons.payments_outlined,
            title: 'Payments',
            subtitle: 'Record money received',
            onTap: () => _open(
              context,
              PaymentsScreen(adminService: adminService),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
