import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/media.dart';
import '../../../widgets/media_card.dart';

/// Titled horizontal row of [MediaCard]s with end-reached paging support.
class MediaCarousel extends StatefulWidget {
  final String title;
  final List<MediaItem> items;
  final VoidCallback? onEndReached;
  final void Function(MediaItem item)? onRemove;
  final Map<int, double>? progressById;

  const MediaCarousel({
    super.key,
    required this.title,
    required this.items,
    this.onEndReached,
    this.onRemove,
    this.progressById,
  });

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (widget.onEndReached != null &&
          _controller.position.pixels >= _controller.position.maxScrollExtent - 600) {
        widget.onEndReached!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text(
            widget.title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.foreground),
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final item = widget.items[i];
              return SizedBox(
                width: 120,
                child: MediaCard(
                  item: item,
                  progress: widget.progressById?[item.id],
                  onRemove: widget.onRemove == null ? null : () => widget.onRemove!(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
