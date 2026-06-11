import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'widgets/aurora_background.dart';

class StreamflixApp extends ConsumerWidget {
  const StreamflixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    return MaterialApp.router(
      title: 'StreamFlix',
      debugShowCheckedModeBanner: false,
      theme: theme == 'oled' ? AppTheme.oled() : AppTheme.dark(),
      routerConfig: appRouter,
      // Paint the ambient aurora once, behind every route, so the Glass
      // surfaces have something colourful to refract.
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    );
  }
}
