import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workmanager/workmanager.dart';

import 'core/router/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'data/local/isar_service.dart';
import 'data/remote/token_storage.dart';
import 'data/sync/sync_worker.dart';
import 'presentation/screens/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Neo-brutalist canvas is light: keep status/nav bar glyphs dark.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFFCEFDA),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await initializeDateFormatting('es');
  await IsarService.instance.open();

  // Warm the in-memory token before the first frame. Media widgets read it
  // synchronously to authenticate against `/media`, so a photo built before
  // the first API call would otherwise render as broken once and stay cached
  // that way.
  await TokenStorage.read();

  // workmanager only supports Android/iOS. On desktop the app still
  // syncs while in the foreground via SyncWorker called from the UI.
  final supportsBackgroundSync =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (supportsBackgroundSync) {
    await Workmanager().initialize(syncCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      SyncWorker.taskId,
      SyncWorker.taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      // `update` so an app update actually refreshes the scheduled work
      // instead of leaving whatever an older install registered.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  runApp(const ProviderScope(child: AlmaApp()));
}

class AlmaApp extends StatelessWidget {
  const AlmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alma',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.neo(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(child: AppShell()),
    );
  }
}
