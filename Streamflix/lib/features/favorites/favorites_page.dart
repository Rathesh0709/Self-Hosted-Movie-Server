import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../widgets/media_card.dart';
import '../../widgets/page_header.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});
  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(favoritesProvider.notifier).fetchFavorites());
  }

  @override
  Widget build(BuildContext context) {
    final authed = ref.watch(authProvider).isAuthenticated;
    final items = ref.watch(favoritesProvider);

    return Column(
      children: [
        const PageHeader(title: 'Favorites'),
        Expanded(
          child: !authed
              ? _SignedOut(onLogin: () => context.push('/auth'))
              : items.isEmpty
                  ? const _Empty()
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 130,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => MediaCard(
                        item: items[i].toMediaItem(),
                        onRemove: () => ref
                            .read(favoritesProvider.notifier)
                            .removeFavorite(items[i].mediaId, items[i].mediaType),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _SignedOut extends StatelessWidget {
  final VoidCallback onLogin;
  const _SignedOut({required this.onLogin});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border_rounded, size: 48, color: AppColors.mutedForeground),
            const SizedBox(height: 16),
            const Text('Sign in to save favorites',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            FilledButton(onPressed: onLogin, child: const Text('Login / Register')),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border_rounded, size: 48, color: AppColors.mutedForeground),
            SizedBox(height: 16),
            Text('No favorites yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Tap the heart on any title to save it here.',
                style: TextStyle(color: AppColors.mutedForeground, fontSize: 13)),
          ],
        ),
      );
}
