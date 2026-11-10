import 'dart:convert';

/// Build-time settings, passed with `--dart-define-from-file=dart_defines.json`.
/// The file is never committed. Only the public publishable (publishable) key belongs here.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Null when the configuration is usable, otherwise a message for the owner.
  static String? get problem => checkConfig(url: supabaseUrl, publishableKey: supabasePublishableKey);

  static String? checkConfig({required String url, required String publishableKey}) {
    if (url.isEmpty || publishableKey.isEmpty) {
      return 'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are not set. '
          'Copy dart_defines.example.json to dart_defines.json, fill it in, '
          'and run with --dart-define-from-file=dart_defines.json.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'SUPABASE_URL is not a valid address.';
    }
    final keyProblem = checkPublishableKey(publishableKey);
    if (keyProblem != null) return keyProblem;
    return null;
  }

  /// Refuses a privileged key. The service-role key must never be inside the app.
  static String? checkPublishableKey(String key) {
    const refusal = 'SUPABASE_PUBLISHABLE_KEY holds a secret (service-role) key. '
        'Use the public publishable or publishable key. The secret key must never be put in the app.';
    if (key.startsWith('sb_secret_')) return refusal;
    final parts = key.split('.');
    if (parts.length == 3) {
      try {
        final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
        final claims = jsonDecode(payload);
        if (claims is Map && claims['role'] == 'service_role') return refusal;
      } catch (_) {
        // Not a readable token; leave it to the server to reject.
      }
    }
    return null;
  }
}
