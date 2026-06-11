import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/stream.dart';

/// Torrent source row in the stream-selection dialog. 1:1 port of React's
/// StreamCard.tsx: glass `white/5` surface, colored quality badge, seeders +
/// size header, filename, and codec/source footer chips.
class StreamCard extends StatefulWidget {
  final ParsedStream stream;
  final VoidCallback onTap;
  final bool disabled;
  const StreamCard({
    super.key,
    required this.stream,
    required this.onTap,
    this.disabled = false,
  });

  @override
  State<StreamCard> createState() => _StreamCardState();
}

class _StreamCardState extends State<StreamCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final q = AppColors.qualityBadge(s.quality);
    return Opacity(
      opacity: widget.disabled ? 0.6 : 1,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.disabled ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hover ? 0.1 : 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: _hover ? 0.12 : 0.06),
              ),
              gradient: _hover
                  ? LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: quality badge + seeders + size
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: q.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: q.border),
                      ),
                      child: Text(
                        s.quality,
                        style: TextStyle(
                          color: q.fg,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${s.seeders} seeders',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB5B5C0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: AppColors.cyan,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.size,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB5B5C0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Torrent title
                Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.35,
                    color: _hover ? Colors.white : const Color(0xFFD6D6DE),
                  ),
                ),
                const SizedBox(height: 12),
                // Footer chips: codec + source
                Row(
                  children: [
                    _chip(Icons.movie_creation_outlined, s.codec),
                    const SizedBox(width: 8),
                    Flexible(child: _chip(Icons.info_outline_rounded, s.source)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.mutedForeground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      );
}
