import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/media.dart';
import '../../providers/tmdb_providers.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/media_card.dart';
import '../../widgets/search_field.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  int _page = 1;

  bool _lastPageLoaded = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
        if (mounted) setState(() => _page += 1);
      }
    });
  }

  /// Keep loading pages until the grid actually overflows the viewport, so
  /// paging works even when the first page doesn't fill the screen.
  void _fillViewport() {
    if (!_scroll.hasClients || !_lastPageLoaded || _query.isEmpty) return;
    if (_scroll.position.maxScrollExtent <= 0 && _page < 12) {
      setState(() => _page += 1);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _query = value.trim();
          _page = 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Watch pages 1.._page and dedupe into one growing list.
  ({List<MediaItem> items, bool loading, bool error}) _collect() {
    final out = <MediaItem>[];
    final seen = <String>{};
    var loading = false;
    var error = false;
    for (var p = 1; p <= _page; p++) {
      final res = ref.watch(searchProvider((query: _query, page: p)));
      if (p == _page) _lastPageLoaded = res.hasValue || res.hasError;
      res.when(
        data: (data) {
          for (final item in data) {
            if (seen.add('${item.mediaType}-${item.id}')) out.add(item);
          }
        },
        loading: () => loading = true,
        error: (_, _) => error = true,
      );
    }
    return (items: out, loading: loading, error: error);
  }

  @override
  Widget build(BuildContext context) {
    final collected = _query.isEmpty
        ? (items: <MediaItem>[], loading: false, error: false)
        : _collect();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Discover',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                SearchField(
                  controller: _controller,
                  onChanged: _onChanged,
                  autofocus: true,
                ),
              ],
            ),
          ),
          Expanded(child: _body(collected)),
        ],
      ),
    );
  }

  Widget _body(({List<MediaItem> items, bool loading, bool error}) c) {
    if (_query.isEmpty) {
      return const _Hint(
        icon: Icons.search_rounded,
        title: 'Type to search',
        subtitle: 'Find thousands of movies and TV series instantly.',
      );
    }
    if (c.items.isEmpty && c.loading) {
      return const CarouselSkeleton(showTitle: false);
    }
    if (c.items.isEmpty && c.error) {
      return const _Hint(
        icon: Icons.error_outline_rounded,
        title: 'Search failed',
        subtitle: 'Check your connection and try again.',
      );
    }
    if (c.items.isEmpty) {
      return const _Hint(
        icon: Icons.movie_filter_outlined,
        title: 'No results found',
        subtitle: 'Try a different spelling or another title.',
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: c.items.length,
      itemBuilder: (_, i) => MediaCard(item: c.items[i]),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Hint({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.mutedForeground),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mutedForeground, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
