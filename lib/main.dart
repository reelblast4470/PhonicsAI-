import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/env/app_config.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();
  final overrides = await bootstrap(config);
  installGlobalErrorHandling();
  runApp(
    ProviderScope(
      overrides: overrides,
      child: const PhonicsAiApp(),
    ),
  );
}
