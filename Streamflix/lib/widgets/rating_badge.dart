import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Small star + score chip used on cards and detail headers.
class RatingBadge extends StatelessWidget {
  final double rating;
  final double size;
  const RatingBadge({super.key, required this.rating, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final color = rating >= 7
        ? const Color(0xFF86EFAC)
        : rating >= 5
            ? const Color(0xFFFCD34D)
            : AppColors.mutedForeground;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.5, vertical: size * 0.25),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(size),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: size + 2, color: color),
          SizedBox(width: size * 0.25),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
