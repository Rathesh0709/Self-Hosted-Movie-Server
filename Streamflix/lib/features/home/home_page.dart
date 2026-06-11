import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/media.dart';
import '../../providers/tmdb_providers.dart';
import '../../providers/watch_history_provider.dart';
import '../../services/tmdb_service.dart';
import '../../widgets/loading_skeleton.dart';
import 'widgets/hero_banner.dart';
import 'widgets/media_carousel.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _page = 1;
  final _scroll = ScrollController();
  final _artworkInFlight = <int>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
        _nextPage();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (mounted) setState(() => _page += 1);
  }

  /// Watch pages 1.._page of a feed and return the deduped concatenation.
  List<MediaItem> _collect(
      ProviderListenable<AsyncValue<List<MediaItem>>> Function(int page) make) {
    final out = <MediaItem>[];
    final seen = <String>{};
    for (var p = 1; p <= _page; p++) {
      final data = ref.watch(make(p)).value;
      if (data != null) {
        for (final item in data) {
          if (seen.add('${item.mediaType}-${item.id}')) out.add(item);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final today = _collect((p) => popularTodayProvider(p));
    final trending = _collect((p) => trendingProvider((window: 'week', page: p)));
    final movies = _collect((p) => popularProvider((type: 'movie', page: p)));
    final tv = _collect((p) => popularProvider((type: 'tv', page: p)));
    final anime = _collect((p) => animeProvider(p));
    final cartoons = _collect((p) => cartoonsProvider(p));
    final top = _collect((p) => topRatedProvider((type: 'movie', page: p)));

    ref.watch(watchHistoryProvider); // rebuild on history changes
    final continueItems = ref.read(watchHistoryProvider.notifier).continueWatching();
    _backfillArtwork(continueItems);

    final hero = trending.take(6).toList();
    final trendingRest = trending.length > 6 ? trending.sublist(6) : const <MediaItem>[];

    final continueMedia = continueItems
        .map((h) => MediaItem(
              id: h.mediaId,
              title: h.title,
              posterPath: h.posterPath,
              backdropPath: h.backdropPath,
              mediaType: h.mediaType,
            ))
        .toList();
    final progressById = {for (final h in continueItems) h.mediaId: h.progress};

    if (_page == 1 && trending.isEmpty) {
      return ListView(
        children: const [HeroSkeleton(), CarouselSkeleton(), CarouselSkeleton()],
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(trendingProvider);
        ref.invalidate(popularTodayProvider);
        ref.invalidate(popularProvider);
        setState(() => _page = 1);
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          HeroBanner(items: hero),
          _categoryChips(context),
          if (continueMedia.isNotEmpty)
            MediaCarousel(
              title: 'Continue Watching',
              items: continueMedia,
              progressById: progressById,
              onRemove: (item) => ref
                  .read(watchHistoryProvider.notifier)
                  .removeFromHistory('${item.mediaType}-${item.id}'),
            ),
          MediaCarousel(title: 'Popular Right Now', items: today, onEndReached: _nextPage),
          MediaCarousel(title: 'Trending This Week', items: trendingRest, onEndReached: _nextPage),
          MediaCarousel(title: 'Popular Movies', items: movies, onEndReached: _nextPage),
          MediaCarousel(title: 'Popular Shows', items: tv, onEndReached: _nextPage),
          MediaCarousel(title: 'Anime', items: anime, onEndReached: _nextPage),
          MediaCarousel(title: 'Cartoons', items: cartoons, onEndReached: _nextPage),
          MediaCarousel(title: 'Top Rated Classics', items: top, onEndReached: _nextPage),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _categoryChips(BuildContext context) {
    const cats = [
      ('Movies', Icons.movie_rounded, '/movies'),
      ('TV Shows', Icons.tv_rounded, '/tvshows'),
      ('Anime', Icons.auto_awesome_rounded, '/anime'),
      ('Cartoons', Icons.child_care_rounded, '/cartoons'),
      ('Popular', Icons.local_fire_department_rounded, '/popular'),
      ('Favorites', Icons.favorite_rounded, '/favorites'),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, icon, route) = cats[i];
          return ActionChip(
            avatar: Icon(icon, size: 16, color: AppColors.primary),
            label: Text(label),
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            backgroundColor: AppColors.navyCard,
            side: const BorderSide(color: AppColors.border),
            onPressed: () => context.push(route),
          );
        },
      ),
    );
  }

  /// Backfill missing Continue-Watching artwork via TMDB title search.
  /// Sequential + error-handled so it doesn't flood TMDB or jank the UI thread.
  Future<void> _backfillArtwork(List items) async {
    for (final item in items) {
      if (item.posterPath != null || item.backdropPath != null) continue;
      if (_artworkInFlight.contains(item.mediaId)) continue;
      _artworkInFlight.add(item.mediaId);
      try {
        final art = await tmdbService.findArtworkByTitle(item.title);
        if (art != null && (art.posterPath != null || art.backdropPath != null)) {
          ref.read(watchHistoryProvider.notifier).updateItemMeta(
                item.id,
                title: art.title,
                posterPath: art.posterPath,
                backdropPath: art.backdropPath,
              );
        }
      } catch (_) {
        // Offline / rate-limited — leave artwork unresolved.
      } finally {
        _artworkInFlight.remove(item.mediaId);
      }
    }
  }
}
