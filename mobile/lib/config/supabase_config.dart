/// Supabase project settings supplied at build time.
///
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
class SupabaseConfig {
  static const String projectUrl = String.fromEnvironment('SUPABASE_URL');

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
}
