import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Ambient "aurora" backdrop — soft blue + cyan light blooms over the deep
/// navy base. This is the colour that the `Glass` surfaces refract, which is
/// what makes the glassmorphism actually read on screen (a blur over a flat
/// colour looks like nothing). Painted once, behind every route.
///
/// The blooms are soft radial gradients (cheap to paint), so we deliberately
/// avoid a full-screen `BackdropFilter` here — that live blur ran every frame
/// behind every scroll and was the main source of scroll jank.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).canvasColor;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: base)),
        // Blue bloom, top-left.
        _blob(
          top: -160,
          left: -120,
          size: 520,
          color: AppColors.primary.withValues(alpha: 0.30),
        ),
        // Cyan bloom, top-right.
        _blob(
          top: -100,
          right: -140,
          size: 460,
          color: AppColors.cyan.withValues(alpha: 0.20),
        ),
        // Deep-blue bloom, bottom.
        _blob(
          bottom: -200,
          left: 40,
          size: 560,
          color: const Color(0xFF1D4ED8).withValues(alpha: 0.22),
        ),
        child,
      ],
    );
  }

  Widget _blob({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
