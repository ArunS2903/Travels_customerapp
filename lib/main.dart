import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers/app_providers.dart';
import 'core/storage/prefs_store.dart';
import 'core/storage/token_store.dart';
import 'features/authentication/providers/auth_controller.dart';

void main() {
  runZonedGuarded(_start, (error, stack) {
    // Release la ethu crash aanaalum screen la kaattum
    runApp(_ErrorApp('UNCAUGHT ERROR:\n$error\n\n$stack'));
  });
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Widget build error vandha black/grey ku badhula text kaattum
  ErrorWidget.builder = (details) => Material(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'WIDGET ERROR:\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  /// Raise the decoded-image budget.
  ///
  /// A vehicle gallery is five photographs the operator uploaded at whatever
  /// resolution their phone produced. Flutter's 100MB default is enough for
  /// about three of those decoded at full size, so the fourth evicted the
  /// first and swiping back re-downloaded it. `AppNetworkImage` cuts the cost
  /// per image by decoding at display size; this makes sure the ones that fit
  /// stay put.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = AppConfig.imageCacheBytes
    ..maximumSize = AppConfig.imageCacheCount;

  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    final tokenStore = TokenStore();
    await tokenStore.load().timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
              throw TimeoutException('tokenStore.load() hung (keystore)'),
        );

    final prefsStore = await PrefsStore.create().timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('PrefsStore.create() hung'),
    );

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore),
        prefsStoreProvider.overrideWithValue(prefsStore),
      ],
    );

    // Push: await pannala, aana error-ah catch pannrom
    final pushService = container.read(pushServiceProvider);
    pushService.initialize().then((available) {
      if (!available && AppConfig.debugLogging) {
        // ignore: avoid_print
        print('[push] unavailable: ${pushService.unavailableReason}');
      }
    }).catchError((Object e, StackTrace s) {
      // ignore: avoid_print
      print('[push] init error: $e');
    });

    // Session bootstrap: error vandha catch pannrom
    try {
      final f = container.read(authControllerProvider.notifier).bootstrap();
      // ignore: unnecessary_type_check
      if (f is Future) {
        f.catchError((Object e, StackTrace s) {
          // ignore: avoid_print
          print('[auth] bootstrap error: $e');
        });
      }
    } catch (e, s) {
      // ignore: avoid_print
      print('[auth] bootstrap sync error: $e\n$s');
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const CustomerApp(),
      ),
    );
  } catch (e, s) {
    runApp(_ErrorApp('STARTUP ERROR:\n$e\n\n$s'));
  }
}

class _ErrorApp extends StatelessWidget {
  const _ErrorApp(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}