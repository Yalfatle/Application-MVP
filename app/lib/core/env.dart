/// Build-time configuration, passed with --dart-define-from-file=config/<env>.json
/// so no keys are ever committed to the repo.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where the staff website is hosted. Invite links point here.
  static const adminWebUrl = String.fromEnvironment('ADMIN_WEB_URL');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
