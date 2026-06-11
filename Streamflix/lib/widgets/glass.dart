import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Glassmorphism surface — the Flutter port of the React app's `.glass` /
/// `.glass-strong` utilities (translucent fill + backdrop blur + hairline
/// border). Use this everywhere a flat card used to be so surfaces read
/// vibrant and layered instead of bland.
class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final Color? fill;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final Gradient? gradient;

  const Glass({
    super.key,
    required this.child,
    this.blur = 20,
    this.radius = 20,
    this.fill,
    this.borderColor,
    this.padding,
    this.margin,
    this.onTap,
    this.shadow,
    this.gradient,
  });

  /// Stronger, more opaque variant (ports `.glass-strong`) — for modals/dialogs.
  const Glass.strong({
    super.key,
    required this.child,
    this.blur = 40,
    this.radius = 24,
    this.fill = const Color(0xCC12131C),
    this.borderColor = const Color(0x1FFFFFFF),
    this.padding,
    this.margin,
    this.onTap,
    this.shadow,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    // A glossy sheen: brighter at the top-left, fading to near-transparent —
    // this is what makes the surface read as *glass* rather than a flat tint.
    final sheen = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.14),
        Colors.white.withValues(alpha: 0.04),
        Colors.white.withValues(alpha: 0.02),
      ],
      stops: const [0, 0.5, 1],
    );
    Widget surface = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          // Base tint (translucent fill, or a supplied gradient).
          decoration: BoxDecoration(
            color: gradient == null ? (fill ?? AppColors.glassFill) : null,
            gradient: gradient,
            borderRadius: br,
          ),
          child: Container(
            padding: padding,
            // Glossy sheen + hairline border layered on top of the tint.
            decoration: BoxDecoration(
              gradient: sheen,
              borderRadius: br,
              border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (shadow != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(borderRadius: br, boxShadow: shadow),
        child: surface,
      );
    }

    if (onTap != null) {
      surface = Material(
        color: Colors.transparent,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: surface),
      );
    }

    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}

/// Text painted with the brand violet→cyan gradient (ports `.gradient-text`).
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppColors.brandGradient,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}

/// Primary call-to-action with the brand violet→cyan gradient + soft glow.
/// Replaces flat solid-purple FilledButtons where a vibrant accent is wanted.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool expand;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final btn = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled ? AppColors.glow(blur: 22, alpha: 0.4) : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}
