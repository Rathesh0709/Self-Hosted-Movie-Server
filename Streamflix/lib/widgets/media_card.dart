import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_theme.dart';
import '../models/media.dart';
import '../services/tmdb_service.dart';
import 'rating_badge.dart';

/// Poster card used across carousels and grids. Tapping opens the detail page.
class MediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onRemove;
  final double? progress; // optional continue-watching progress bar (0..1)

  const MediaCard({super.key, required this.item, this.onRemove, this.progress});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
      onTap: () => context.push('/${item.mediaType}/${item.id}'),
      onLongPress: onRemove,
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
                  CachedNetworkImage(
                    imageUrl: tmdbImage(item.posterPath, type: 'poster', size: 'medium'),
                    fit: BoxFit.cover,
                    // Decode at roughly the display resolution (poster slots are
                    // ~120–160px wide; 2x for crispness on hi-dpi). Avoids
                    // decoding full-size bitmaps into memory while scrolling.
                    memCacheWidth: 320,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, _) => Container(color: AppColors.navyElevated),
                    errorWidget: (_, _, _) => Container(
                      color: AppColors.navyElevated,
                      child: const Icon(Icons.movie_outlined, color: AppColors.mutedForeground),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: RatingBadge(rating: item.voteAverage),
                  ),
                  if (onRemove != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        minHeight: 3,
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
