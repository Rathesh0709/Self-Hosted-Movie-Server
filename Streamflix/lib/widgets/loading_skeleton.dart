import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme/app_theme.dart';

/// A subtly pulsing placeholder block.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const ShimmerBox({super.key, this.width, this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.navyElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 700.ms)
        .then()
        .fade(begin: 1, end: 0.45, duration: 700.ms);
  }
}

/// Horizontal carousel skeleton row.
class CarouselSkeleton extends StatelessWidget {
  final bool showTitle;
  const CarouselSkeleton({super.key, this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ShimmerBox(width: 160, height: 20),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => const AspectRatio(
                aspectRatio: 2 / 3,
                child: ShimmerBox(radius: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: AspectRatio(aspectRatio: 16 / 10, child: ShimmerBox(radius: 24)),
    );
  }
}
