import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/media.dart';
import '../../../services/tmdb_service.dart';
import '../../../widgets/rating_badge.dart';

/// Auto-rotating featured banner across the top trending items.
class HeroBanner extends StatefulWidget {
  final List<MediaItem> items;
  const HeroBanner({super.key, required this.items});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || widget.items.isEmpty) return;
      _index = (_index + 1) % widget.items.length;
      _page.animateToPage(_index,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      height: height.clamp(360, 620),
      child: Stack(
        children: [
          PageView.builder(
            controller: _page,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.items.length,
            itemBuilder: (_, i) => _slide(context, widget.items[i]),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Row(
              children: List.generate(
                widget.items.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _index ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? AppColors.primary : Colors.white30,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slide(BuildContext context, MediaItem item) {
    return GestureDetector(
      onTap: () => context.push('/${item.mediaType}/${item.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: tmdbImage(item.backdropPath, type: 'backdrop', size: 'large'),
            fit: BoxFit.cover,
            memCacheWidth: 1280,
            errorWidget: (_, _, _) => Container(color: AppColors.navyElevated),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Theme.of(context).canvasColor,
                  Theme.of(context).canvasColor.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      RatingBadge(rating: item.voteAverage, size: 13),
                      const SizedBox(width: 10),
                      Text(
                        item.releaseDate.isNotEmpty ? item.releaseDate.split('-').first : '',
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/${item.mediaType}/${item.id}'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('View & Stream'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
