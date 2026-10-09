/// One place to point the app at the Express API.
///
/// Android emulator: http://10.0.2.2:5000/api
/// iOS simulator:    http://127.0.0.1:5000/api
/// Physical device:  http://LAN-IP:5000/api
///
/// Override without editing this file:
/// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:5000/api
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.97:5000/api',
  );
}
