import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/device_store.dart';
import 'core/auth/supabase_auth_service.dart';
import 'core/backend/backend_gateway.dart';
import 'core/backend/supabase_backend_gateway.dart';
import 'core/config/app_config.dart';
import 'core/db/local_store.dart';
import 'core/db/sqflite_local_store.dart';
import 'core/sync/sync_runner.dart';
import 'features/auth/presentation/startup_problem_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final problem = AppConfig.problem;
  if (problem != null) {
    runApp(StartupProblemApp(title: 'App is not configured', message: problem));
    return;
  }

  try {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
    final client = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();
    final localStore = await SqfliteLocalStore.open();

    runApp(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(SupabaseAuthService(client.auth)),
        backendGatewayProvider.overrideWithValue(SupabaseBackendGateway(client)),
        deviceStoreProvider.overrideWithValue(SharedPrefsDeviceStore(prefs)),
        localStoreProvider.overrideWithValue(localStore),
      ],
      child: const SyncRunner(child: ShaktiKramApp()),
    ));
  } catch (e) {
    runApp(StartupProblemApp(title: 'The app could not start', message: '$e'));
  }
}
