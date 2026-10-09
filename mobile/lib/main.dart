import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/theme_controller.dart';
import 'services/admin_service.dart';
import 'services/auth_service.dart';
import 'services/customer_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final tokenStorage = TokenStorage();
  final apiClient = ApiClient(tokenStorage: tokenStorage);
  final authService = AuthService(
    tokenStorage: tokenStorage,
  );
  apiClient.onUnauthorized = authService.handleUnauthorized;

  final themeController = ThemeController();
  await themeController.load();

  runApp(
    PurifyApp(
      authService: authService,
      customerService: CustomerService(),
      adminService: AdminService(),
      themeController: themeController,
    ),
  );
}
