import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/media.dart';
import '../../providers/tmdb_providers.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/media_card.dart';
import '../../widgets/page_header.dart';

/// Browse grid for Movies / TV Shows / Anime / Cartoons / Popular with a
/// client-side genre filter and infinite paging.
class CategoryPage extends ConsumerStatefulWidget {
  final String category; // movies | tvshows | anime | cartoons | popular
  const CategoryPage({super.key, required this.category});

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  int _page = 1;
  int? _genre; // null = All
  final _scroll = ScrollController();

  String get _title => switch (widget.category) {
    'movies' => 'Movies',
    'tvshows' => 'TV Shows',
    'anime' => 'Anime',
    'cartoons' => 'Cartoons',
    'popular' => 'Popular',
    _ => 'Browse',
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
        setState(() => _page += 1);
      }
    });
  }

  /// When the loaded items don't fill the viewport there's nothing to scroll,
  /// so the scroll listener never fires and paging stalls. Pull the next page
  /// until the grid is actually scrollable (capped to avoid runaway loops).
  void _fillViewport() {
    if (!_scroll.hasClients || !_lastPageLoaded) return;
    if (_scroll.position.maxScrollExtent <= 0 && _page < 12) {
      setState(() => _page += 1);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ProviderListenable<AsyncValue<List<MediaItem>>> _providerFor(int page) =>
      switch (widget.category) {
        'movies' => popularProvider((type: 'movie', page: page)),
        'tvshows' => popularProvider((type: 'tv', page: page)),
        'anime' => animeProvider(page),
        'cartoons' => cartoonsProvider(page),
        'popular' => popularTodayProvider(page),
        _ => popularProvider((type: 'movie', page: page)),
      };

  bool _lastPageLoaded = false;

  List<MediaItem> _collect() {
    final out = <MediaItem>[];
    final seen = <String>{};
    for (var p = 1; p <= _page; p++) {
      final value = ref.watch(_providerFor(p));
      if (p == _page) _lastPageLoaded = value.hasValue || value.hasError;
      final data = value.value;
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
    final items = _collect();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());

    final genres =
        <int>{
            for (final i in items) ...i.genreIds,
          }.where(kGenreMap.containsKey).toList()
          ..sort((a, b) => kGenreMap[a]!.compareTo(kGenreMap[b]!));

    final filtered = _genre == null
        ? items
        : items.where((i) => i.genreIds.contains(_genre)).toList();

    return Column(
      children: [
        PageHeader(title: _title),
        if (items.isEmpty)
          const Expanded(child: CarouselSkeleton(showTitle: false))
        else ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _genreChip(
                  'All',
                  _genre == null,
                  () => setState(() => _genre = null),
                ),
                for (final g in genres)
                  _genreChip(
                    kGenreMap[g]!,
                    _genre == g,
                    () => setState(() => _genre = g),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                childAspectRatio: 0.52,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => MediaCard(item: filtered[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _genreChip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: active ? Colors.white : AppColors.mutedForeground,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.navyCard,
      side: const BorderSide(color: AppColors.border),
    ),
  );
}
