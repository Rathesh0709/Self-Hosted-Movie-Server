import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/media.dart';
import '../../models/stream.dart';
import '../../providers/player_provider.dart';
import '../../services/backend_service.dart';
import '../../services/tmdb_service.dart';
import '../../widgets/glass.dart';
import '../../widgets/page_header.dart';
import '../../widgets/rating_badge.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  List<DownloadedFile> _files = [];
  List<ActiveDownload> _downloads = [];
  final Map<String, MediaItem> _art = {}; // path -> resolved artwork/title
  final Set<String> _artInFlight = {};
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _startingPath;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _loadDownloads());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await backendService.getDownloadedFiles();
      if (mounted) setState(() => _files = files);
      _resolveArtwork(files);
      await _loadDownloads();
    } catch (_) {
      if (mounted) setState(() => _error = 'Backend offline or unreachable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDownloads() async {
    try {
      final d = await backendService.getActiveDownloads();
      if (mounted) setState(() => _downloads = d);
    } catch (_) {}
  }

  /// Resolve TMDB poster + clean title for each downloaded file (like the
  /// React Library's per-card artwork enrichment). Runs SEQUENTIALLY with
  /// error handling — firing all lookups in parallel floods TMDB (connection
  /// resets) and janks the UI thread.
  Future<void> _resolveArtwork(List<DownloadedFile> files) async {
    for (final f in files) {
      if (!mounted) return;
      if (_art.containsKey(f.path) || _artInFlight.contains(f.path)) continue;
      _artInFlight.add(f.path);
      try {
        final m = await tmdbService.findArtworkByTitle(f.name);
        if (m != null && mounted) setState(() => _art[f.path] = m);
      } catch (_) {
        // Offline / rate-limited — skip artwork for this file, keep going.
      } finally {
        _artInFlight.remove(f.path);
      }
    }
  }

  Future<void> _play(DownloadedFile file) async {
    setState(() => _startingPath = file.path);
    try {
      final res = await backendService.startFileStream(file.path);
      if (!res.success) throw Exception('fail');
      final art = _art[file.path];
      final media = MediaItem(
        id: art?.id ?? file.path.hashCode,
        title: art?.title ?? normalizeTitle(file.name),
        posterPath: art?.posterPath,
        backdropPath: art?.backdropPath,
        mediaType: art?.mediaType ?? 'movie',
      );
      ref
          .read(playerProvider.notifier)
          .setStream(
            res.streamId,
            backendService.playableUrl(res.stream),
            media,
          );
      if (mounted) context.push('/player/${res.streamId}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start file playback.')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingPath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered =
        _files.where((f) => f.name.toLowerCase().contains(q)).toList();

    return Column(
      children: [
        PageHeader(
          title: 'Downloaded Library',
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _refresh)
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        slivers: [
                          // Active downloads
                          if (_downloads.isNotEmpty)
                            SliverToBoxAdapter(child: _downloadsPanel()),
                          // Search box
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 440),
                                child: TextField(
                                  onChanged: (v) => setState(() => _query = v),
                                  decoration: const InputDecoration(
                                    hintText: 'Search downloaded files...',
                                    prefixIcon: Icon(Icons.search_rounded),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (filtered.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyLibrary(),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 160,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 2 / 3.36,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _DownloadedCard(
                                    file: filtered[i],
                                    art: _art[filtered[i].path],
                                    starting:
                                        _startingPath == filtered[i].path,
                                    onTap: () => _play(filtered[i]),
                                  ),
                                  childCount: filtered.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _downloadsPanel() => Glass(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Downloads',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 12),
            for (final d in _downloads) ...[
              Text(
                d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.progress.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d.done
                    ? 'Completed'
                    : '${(d.progress * 100).toStringAsFixed(0)}% • ${d.numPeers} peers',
                style: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
}

/// Poster card for a downloaded file — 1:1 with React's DownloadedMediaCard:
/// poster artwork, rating badge top-right, "size • HEVC/AVI" badge top-left,
/// and a "Starting..." overlay while the backend boots the stream.
class _DownloadedCard extends StatelessWidget {
  final DownloadedFile file;
  final MediaItem? art;
  final bool starting;
  final VoidCallback onTap;
  const _DownloadedCard({
    required this.file,
    required this.art,
    required this.starting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sizeLabel =
        '${formatBytes(file.size)}${file.needsTranscode ? ' • HEVC/AVI' : ''}';
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (art?.posterPath != null)
                    CachedNetworkImage(
                      imageUrl: tmdbImage(art!.posterPath,
                          type: 'poster', size: 'medium'),
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.navyElevated),
                      errorWidget: (_, _, _) => _fallback(),
                    )
                  else
                    _fallback(),
                  // Gradient scrim so the title is legible on bright posters
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Size / codec badge (top-left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        sizeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Rating badge (top-right) when we have artwork
                  if (art != null)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: RatingBadge(rating: 7),
                    ),
                  // Title overlay (bottom)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Text(
                      art?.title ?? normalizeTitle(file.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Starting overlay
                  if (starting)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        alignment: Alignment.center,
                        child: const Text(
                          'Starting...',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.navyElevated,
        child: const Icon(Icons.movie_outlined, color: AppColors.mutedForeground),
      );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 48, color: AppColors.mutedForeground),
            SizedBox(height: 14),
            Text(
              'No downloaded files yet.',
              style: TextStyle(
                color: AppColors.mutedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.mutedForeground,
            ),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
