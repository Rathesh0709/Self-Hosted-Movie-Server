import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/theme/app_theme.dart';

class GenreBadge extends StatelessWidget {
  final int id;
  const GenreBadge({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final name = kGenreMap[id];
    if (name == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
        ),
      ),
    );
  }
}
