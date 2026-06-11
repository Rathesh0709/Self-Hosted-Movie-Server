import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/credits.dart';
import '../../models/media.dart';
import '../../models/watch_history.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tmdb_providers.dart';
import '../../providers/watch_history_provider.dart';
import '../../services/backend_service.dart';
import '../../services/tmdb_service.dart';
import '../../services/wake_service.dart';
import '../../widgets/genre_badge.dart';
import '../../widgets/glass.dart';
import '../../widgets/rating_badge.dart';
import 'widgets/episode_card.dart';
import 'widgets/stream_selection_sheet.dart';

class DetailsPage extends ConsumerStatefulWidget {
  final String mediaType; // 'movie' | 'tv'
  final int id;
  const DetailsPage({super.key, required this.mediaType, required this.id});

  @override
  ConsumerState<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends ConsumerState<DetailsPage> {
  int _season = 1;
  bool _continuing = false;

  bool get _isMovie => widget.mediaType == 'movie';

  void selectSeason(int s) => setState(() => _season = s);

  @override
  Widget build(BuildContext context) {
    final imdbId = ref
        .watch(imdbIdProvider((type: widget.mediaType, id: widget.id)))
        .value;
    final credits = ref
        .watch(creditsProvider((type: widget.mediaType, id: widget.id)))
        .value;

    if (_isMovie) {
      final movie = ref.watch(movieDetailsProvider(widget.id));
      return movie.when(
        loading: () => const _DetailsLoading(),
        error: (e, _) => _ErrorScaffold(onBack: () => context.pop()),
        data: (m) => _Scaffold(
          backdrop: m.backdropPath,
          poster: m.posterPath,
          title: m.title,
          rating: m.voteAverage,
          year: formatYear(m.releaseDate),
          runtime: formatRuntime(m.runtime),
          genres: m.genres,
          overview: m.overview,
          media: m.toMediaItem().copyWith(imdbId: imdbId),
          imdbId: imdbId,
          credits: credits,
          state: this,
        ),
      );
    }
    final tv = ref.watch(tvDetailsProvider(widget.id));
    return tv.when(
      loading: () => const _DetailsLoading(),
      error: (e, _) => _ErrorScaffold(onBack: () => context.pop()),
      data: (t) => _Scaffold(
        backdrop: t.backdropPath,
        poster: t.posterPath,
        title: t.name,
        rating: t.voteAverage,
        year: formatYear(t.firstAirDate),
        runtime: t.episodeRunTime.isNotEmpty
            ? formatRuntime(t.episodeRunTime.first)
            : '',
        genres: t.genres,
        overview: t.overview,
        media: t.toMediaItem().copyWith(imdbId: imdbId),
        imdbId: imdbId,
        credits: credits,
        tv: t,
        state: this,
      ),
    );
  }

  // ---- actions ----
  Future<void> _openSheet(
    MediaItem media,
    String imdbId, {
    required String mode,
    int? season,
    int? episode,
  }) async {
    final backendUrl = ref.read(settingsProvider).backendUrl;
    final wol = ref.read(settingsProvider).wolEnabled;
    final online = await backendService.testConnection(backendUrl);
    if (!online && wol) await wakeService.wakeServer();
    if (!mounted) return;
    await showStreamSelection(
      context,
      media: media,
      imdbId: imdbId,
      mode: mode,
      season: season,
      episode: episode,
    );
  }

  Future<void> _toggleFavorite(MediaItem media) async {
    if (!ref.read(authProvider).isAuthenticated) {
      context.push('/auth');
      return;
    }
    final favNotifier = ref.read(favoritesProvider.notifier);
    if (favNotifier.isFavorite(widget.id, widget.mediaType)) {
      await favNotifier.removeFavorite(widget.id, widget.mediaType);
    } else {
      await favNotifier.addFavorite(media, category: _favoriteCategory(media));
    }
    setState(() {});
  }

  String _favoriteCategory(MediaItem media) {
    if (_isMovie) return 'movie';
    final isAnimation = media.genreIds.contains(16);
    final isAnime = isAnimation && media.originCountry.contains('JP');
    if (isAnime) return 'anime';
    if (isAnimation) return 'cartoon';
    return 'tv';
  }

  Future<void> _continuePlaying(
    WatchHistoryItem historyItem,
    MediaItem media,
  ) async {
    setState(() => _continuing = true);
    try {
      final backendUrl = ref.read(settingsProvider).backendUrl;
      final wol = ref.read(settingsProvider).wolEnabled;
      final online = await backendService.testConnection(backendUrl);
      if (!online && wol) await wakeService.wakeServer();

      final magnet = historyItem.magnetURI;
      if (magnet != null) {
        final res = await backendService.startStream(
          magnet,
          fileIdx: historyItem.fileIdx,
        );
        if (res.success && res.streamId.isNotEmpty) {
          final url = backendService.playableUrl(res.stream);
          ref
              .read(playerProvider.notifier)
              .setStream(
                res.streamId,
                url,
                media,
                magnetURI: magnet,
                fileIdx: historyItem.fileIdx,
              );
          if (!mounted) return;
          context.push('/player/${res.streamId}');
          return;
        }
      }
      final streamId = historyItem.streamId;
      if (streamId != null) {
        final url = backendService.resolveBackendUrl(
          historyItem.streamUrl ?? '/api/stream/$streamId',
        );
        ref
            .read(playerProvider.notifier)
            .setStream(
              streamId,
              url,
              media,
              magnetURI: historyItem.magnetURI,
              fileIdx: historyItem.fileIdx,
            );
        if (!mounted) return;
        context.push('/player/$streamId');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resume stream.')),
        );
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }
}

class _Scaffold extends ConsumerWidget {
  final String? backdrop;
  final String? poster;
  final String title;
  final double rating;
  final String year;
  final String runtime;
  final List<Genre> genres;
  final String overview;
  final MediaItem media;
  final String? imdbId;
  final Credits? credits;
  final TVDetails? tv;
  final _DetailsPageState state;

  const _Scaffold({
    required this.backdrop,
    required this.poster,
    required this.title,
    required this.rating,
    required this.year,
    required this.runtime,
    required this.genres,
    required this.overview,
    required this.media,
    required this.imdbId,
    required this.credits,
    required this.state,
    this.tv,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchHistoryProvider);
    final historyItem = ref
        .read(watchHistoryProvider.notifier)
        .getItem('${media.mediaType}-${media.id}');
    final hasHistory =
        historyItem != null &&
        historyItem.progress > 0.02 &&
        historyItem.progress < 0.9 &&
        historyItem.streamId != null;
    final favorited = ref
        .watch(favoritesProvider.notifier)
        .isFavorite(media.id, media.mediaType);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _backdropBar(context, wide),
              SliverToBoxAdapter(
                child: wide
                    ? _wideBody(context, hasHistory, historyItem, favorited)
                    : _narrowBody(context, hasHistory, historyItem, favorited),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SliverAppBar _backdropBar(BuildContext context, bool wide) => SliverAppBar(
    expandedHeight: wide ? 420 : 300,
    pinned: true,
    backgroundColor: Colors.transparent,
    leading: Padding(
      padding: const EdgeInsets.all(8),
      child: CircleAvatar(
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
    ),
    flexibleSpace: FlexibleSpaceBar(
      background: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: tmdbImage(backdrop, type: 'backdrop', size: 'large'),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(color: AppColors.navyElevated),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Theme.of(context).canvasColor,
                  Theme.of(
                    context,
                  ).canvasColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ---------------- Wide (desktop / TV) ----------------
  Widget _wideBody(
    BuildContext context,
    bool hasHistory,
    WatchHistoryItem? historyItem,
    bool favorited,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, -90),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      _poster(260, 390),
                      const SizedBox(height: 16),
                      _actions(context, hasHistory, historyItem, favorited),
                    ],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _metaRow(),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in genres) GenreBadge(id: g.id),
                          ],
                        ),
                        const SizedBox(height: 18),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Text(
                            overview.isEmpty
                                ? 'No description available.'
                                : overview,
                            style: const TextStyle(
                              color: AppColors.foreground,
                              height: 1.6,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (credits != null && credits!.cast.isNotEmpty) _castSection(),
                if (tv != null) _episodesSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Narrow (mobile) ----------------
  Widget _narrowBody(
    BuildContext context,
    bool hasHistory,
    WatchHistoryItem? historyItem,
    bool favorited,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, -50),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _poster(108, 162),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _metaRow(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actions(context, hasHistory, historyItem, favorited),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final g in genres) GenreBadge(id: g.id)],
                ),
                const SizedBox(height: 14),
                Text(
                  overview.isEmpty ? 'No description available.' : overview,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    height: 1.55,
                    fontSize: 14,
                  ),
                ),
                if (credits != null && credits!.cast.isNotEmpty) _castSection(),
                if (tv != null) _episodesSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _poster(double w, double h) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: CachedNetworkImage(
      imageUrl: tmdbImage(poster, type: 'poster', size: 'large'),
      width: w,
      height: h,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) =>
          Container(width: w, height: h, color: AppColors.navyElevated),
    ),
  );

  Widget _metaRow() => Wrap(
    spacing: 12,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      RatingBadge(rating: rating, size: 13),
      if (year.isNotEmpty) _meta(Icons.calendar_today_rounded, year),
      if (runtime.isNotEmpty) _meta(Icons.schedule_rounded, runtime),
    ],
  );

  Widget _actions(
    BuildContext context,
    bool hasHistory,
    WatchHistoryItem? historyItem,
    bool favorited,
  ) {
    return Column(
      children: [
        if (state._isMovie)
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  onPressed: imdbId == null
                      ? null
                      : () => state._openSheet(media, imdbId!, mode: 'stream'),
                  icon: Icons.play_arrow_rounded,
                  label: 'Stream',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: imdbId == null
                      ? null
                      : () =>
                            state._openSheet(media, imdbId!, mode: 'download'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => state._toggleFavorite(media),
            icon: Icon(
              favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: favorited ? AppColors.favorite : null,
            ),
            label: Text(favorited ? 'Favorited' : 'Add to Favorites'),
          ),
        ),
        if (hasHistory) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navyElevated,
              ),
              onPressed: state._continuing
                  ? null
                  : () => state._continuePlaying(historyItem!, media),
              icon: state._continuing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_rounded),
              label: const Text('Continue Playing'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _castSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 24),
      const Text(
        'Main Cast',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: credits!.cast.length.clamp(0, 12),
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final a = credits!.cast[i];
            return SizedBox(
              width: 74,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.navyElevated,
                    backgroundImage: CachedNetworkImageProvider(
                      tmdbImage(a.profilePath, type: 'profile', size: 'medium'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    a.character,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _episodesSection(BuildContext context) => Consumer(
    builder: (context, ref, _) {
      final season = ref.watch(
        seasonProvider((showId: media.id, season: state._season)),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Episodes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              DropdownButton<int>(
                value: state._season,
                dropdownColor: AppColors.navyElevated,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (var s = 1; s <= (tv?.numberOfSeasons ?? 1); s++)
                    DropdownMenuItem(value: s, child: Text('Season $s')),
                ],
                onChanged: (v) => state.selectSeason(v ?? 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          season.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No episodes found.',
                style: TextStyle(color: AppColors.mutedForeground),
              ),
            ),
            data: (s) => Column(
              children: [
                for (final ep in s.episodes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: EpisodeCard(
                      episode: ep,
                      onPlay: imdbId == null
                          ? () {}
                          : () => state._openSheet(
                              media,
                              imdbId!,
                              mode: 'stream',
                              season: state._season,
                              episode: ep.episodeNumber,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.accent),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
        ),
      ),
    ],
  );
}

class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}

class _ErrorScaffold extends StatelessWidget {
  final VoidCallback onBack;
  const _ErrorScaffold({required this.onBack});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: BackButton(onPressed: onBack)),
    body: const Center(child: Text('Failed to load details.')),
  );
}
