import 'dart:convert';

/// Build-time settings, passed with `--dart-define-from-file=dart_defines.json`.
/// The file is never committed. Only the public publishable key belongs here.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Address of the reporting service (reports, Excel/PDF export, backup). Optional: without it the rest of the app
  /// works and the Reports screen says the service is not set up. Never put a key or token here.
  static const reportApiUrl = String.fromEnvironment('REPORT_API_URL');

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
        'Use the public publishable key. The secret key must never be put in the app.';
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

  /// Reads [url] (the `REPORT_API_URL` value). Returns the base address ending without a slash, or a message.
  /// `https` is required, except for a phone testing against a computer on the same network (`http` to localhost, the
  /// Android emulator host `10.0.2.2` or a private address), which only debug builds may reach.
  static ReportUrlCheck checkReportUrl(String url) {
    final text = url.trim();
    if (text.isEmpty) return const ReportUrlCheck.problem('REPORT_API_URL is not set.');
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return const ReportUrlCheck.problem('REPORT_API_URL is not a valid web address.');
    }
    if (uri.hasQuery || uri.hasFragment) return const ReportUrlCheck.problem('REPORT_API_URL must not contain a query or fragment.');
    if (uri.scheme == 'http' && !_isLocalHost(uri.host)) {
      return const ReportUrlCheck.problem('REPORT_API_URL must start with https:// (http:// is only allowed for a computer on your own network).');
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return ReportUrlCheck.ok(uri.replace(path: path));
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host == '10.0.2.2' || host.endsWith('.local')) return true;
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(host);
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
}

/// The result of [AppConfig.checkReportUrl].
class ReportUrlCheck {
  const ReportUrlCheck.ok(Uri this.baseUrl) : problem = null;
  const ReportUrlCheck.problem(String this.problem) : baseUrl = null;

  final Uri? baseUrl;
  final String? problem;
}
