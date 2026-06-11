import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backend_discovery_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/watch_history_provider.dart';
import '../../services/freekeys.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Defer until after first frame — modifying providers during initState
    // (build phase) is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final settings = ref.read(settingsProvider);
    var hasKey = settings.tmdbApiKey.isNotEmpty;
    if (!hasKey) {
      ref.read(settingsProvider.notifier).setTmdbApiKey(freeTmdbKey());
      hasKey = true;
    }

    // Fire-and-forget backend discovery + session sync.
    ref.read(backendDiscoveryProvider.future).catchError((_) {});
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      ref.read(authProvider.notifier).loadUser();
      ref.read(watchHistoryProvider.notifier).syncWithServer();
      ref.read(favoritesProvider.notifier).fetchFavorites();
    }

    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    context.go(hasKey ? '/home' : '/settings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 120,
            left: 40,
            child: _glow(AppColors.primary.withValues(alpha: 0.25)),
          ),
          Positioned(
            bottom: 120,
            right: 40,
            child: _glow(AppColors.accent.withValues(alpha: 0.18)),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 4),
                  ],
                ),
                child: const Icon(Icons.movie_filter_rounded, size: 44, color: Colors.white),
              ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack).fadeIn(),
              const SizedBox(height: 24),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 38, letterSpacing: -1),
                  children: [
                    TextSpan(text: 'STREAM', style: TextStyle(color: Colors.white)),
                    TextSpan(text: 'FLIX', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 800.ms).moveY(begin: 16, end: 0),
              const SizedBox(height: 8),
              Text(
                'ULTIMATE TORRENT STREAMING',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedForeground.withValues(alpha: 0.8),
                ),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
          Positioned(
            bottom: 70,
            child: SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color c) => Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c, blurRadius: 160, spreadRadius: 40)],
        ),
      );
}
