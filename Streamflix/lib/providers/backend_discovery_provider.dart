import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../services/backend_service.dart';
import 'settings_provider.dart';

/// Backend auto-discovery — mirrors the effect in App.tsx. Prefers the static
/// Cloudflare tunnel ([kDefaultBackendUrl]); if it's unreachable, falls back to
/// the currently-saved URL, then the candidate list (Tailscale / LAN).
final backendDiscoveryProvider = FutureProvider<void>((ref) async {
  final settings = ref.read(settingsProvider);

  // 1. Primary: the public tunnel. If it answers, lock onto it (and migrate
  //    older installs that still have a Tailscale/LAN URL saved).
  if (await backendService.testConnection(kDefaultBackendUrl)) {
    if (settings.backendUrl != kDefaultBackendUrl) {
      ref.read(settingsProvider.notifier).setBackendUrl(kDefaultBackendUrl);
    }
    return;
  }

  // 2. Tunnel down — keep the saved URL if it works.
  if (await backendService.testConnection(settings.backendUrl)) return;

  // 3. Otherwise try the fallbacks (Tailscale, LAN, …).
  for (final url in kBackendDiscoveryUrls) {
    if (url == settings.backendUrl) continue;
    if (await backendService.testConnection(url)) {
      ref.read(settingsProvider.notifier).setBackendUrl(url);
      return;
    }
  }
});
