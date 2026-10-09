import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/admin/screens/admin_home_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/customer/screens/customer_home_screen.dart';
import 'services/admin_service.dart';
import 'services/auth_service.dart';
import 'services/customer_service.dart';
import 'widgets/loading_view.dart';

class PurifyApp extends StatefulWidget {
  const PurifyApp({
    super.key,
    required this.authService,
    required this.customerService,
    required this.adminService,
    required this.themeController,
  });

  final AuthService authService;
  final CustomerService customerService;
  final AdminService adminService;
  final ThemeController themeController;

  @override
  State<PurifyApp> createState() => _PurifyAppState();
}

class _PurifyAppState extends State<PurifyApp> {
  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onChanged);
    widget.themeController.addListener(_onChanged);
    widget.authService.restore();
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onChanged);
    widget.themeController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;

    Widget home;
    if (widget.authService.isRestoring) {
      home = const Scaffold(body: LoadingView(message: 'Starting...'));
    } else if (user == null) {
      home = LoginScreen(
        authService: widget.authService,
        themeController: widget.themeController,
      );
    } else if (user.isAdmin) {
      home = AdminHomeScreen(
        authService: widget.authService,
        adminService: widget.adminService,
        themeController: widget.themeController,
      );
    } else {
      home = CustomerHomeScreen(
        authService: widget.authService,
        customerService: widget.customerService,
        themeController: widget.themeController,
      );
    }

    return MaterialApp(
      title: 'HydraCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: widget.themeController.mode,
      home: home,
    );
  }
}
