import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Alma's Neo-Brutalist design language.
///
/// Hard rules, applied everywhere:
///   • Solid black strokes (2–3px) on every container.
///   • Solid black offset shadows (blur: 0) — a displaced block, never a blur.
///   • Flat, saturated pastel fills. No gradients, no translucency on fills.
///   • Heavy black type on pastel/white.
///   • Buttons sink into their shadow when pressed (mechanical press).
class Neo {
  Neo._();

  // ── Palette ────────────────────────────────────────────────────────────
  /// Near-black used for every stroke, shadow and most text.
  static const Color ink = Color(0xFF141210);

  /// Warm cream canvas.
  static const Color paper = Color(0xFFFCEFDA);

  /// Crisp white for the highest-contrast surfaces.
  static const Color white = Color(0xFFFFFFFF);

  // Saturated pastels — each reads with black type on top.
  static const Color pink = Color(0xFFFF90A8); // primary / romance
  static const Color rose = Color(0xFFFFCBD8); // soft pink
  static const Color lilac = Color(0xFFC4A9FF); // purple
  static const Color yellow = Color(0xFFFFD645); // highlight
  static const Color mint = Color(0xFF86E0AF); // green
  static const Color sky = Color(0xFF93CCFF); // blue
  static const Color coral = Color(0xFFFF8A66); // secondary warm

  /// Vivid accent used for input focus and active states.
  static const Color accent = Color(0xFFFF5C3A);

  static const Color danger = Color(0xFFFF4D4D);

  // ── Geometry ───────────────────────────────────────────────────────────
  static const double stroke = 3.0;
  static const double strokeThin = 2.0;
  static const double radius = 12.0;
  static const double radiusSm = 8.0;

  static const Offset shadowCard = Offset(6, 6);
  static const Offset shadowBtn = Offset(4, 4);
  static const Offset shadowSm = Offset(3, 3);

  static Border get border => Border.all(color: ink, width: stroke);
  static Border get borderThin => Border.all(color: ink, width: strokeThin);
  static BorderRadius get corner => BorderRadius.circular(radius);
  static BorderRadius get cornerSm => BorderRadius.circular(radiusSm);

  /// A single hard, blur-free block shadow.
  static List<BoxShadow> shadow([Offset offset = shadowCard]) => [
    BoxShadow(color: ink, offset: offset),
  ];

  /// Rotating pastel used to give sibling cards distinct fills.
  static const List<Color> deck = [pink, lilac, yellow, mint, sky, coral, rose];
  static Color pastel(int i) => deck[i % deck.length];
}

/// Generic bordered + hard-shadowed block. The atom of every surface.
///
/// Pass [onTap] to make it tappable with a subtle mechanical sink; leave it
/// null for a static container.
class NeoBox extends StatefulWidget {
  const NeoBox({
    super.key,
    required this.child,
    this.color = Neo.white,
    this.padding,
    this.margin,
    this.shadowOffset = Neo.shadowCard,
    this.radius = Neo.radius,
    this.borderWidth = Neo.stroke,
    this.onTap,
    this.width,
    this.clip = false,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Offset shadowOffset;
  final double radius;
  final double borderWidth;
  final VoidCallback? onTap;
  final double? width;
  final bool clip;

  @override
  State<NeoBox> createState() => _NeoBoxState();
}

class _NeoBoxState extends State<NeoBox> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    final pressed = _down && tappable;
    final off = widget.shadowOffset;

    final outer = BorderRadius.circular(widget.radius);
    // The stroke is painted inside the outer edge, so content has to be inset
    // by it and clipped to the *inner* curve. Clipping to the outer shape
    // instead lets a full-bleed child — a coloured header, a photo — paint
    // over the corner and stick out past the black border as a little point.
    final innerRadius = (widget.radius - widget.borderWidth).clamp(
      0.0,
      widget.radius,
    );

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }
    content = Padding(
      padding: EdgeInsets.all(widget.borderWidth),
      child: widget.clip
          ? ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: content,
            )
          : content,
    );

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      width: widget.width,
      margin: widget.margin,
      transform: Matrix4.translationValues(
        pressed ? off.dx : 0,
        pressed ? off.dy : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: outer,
        boxShadow: pressed ? const [] : Neo.shadow(off),
      ),
      child: Stack(
        children: [
          content,
          // Stroke last, so nothing can bleed across it.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: outer,
                  border: Border.all(color: Neo.ink, width: widget.borderWidth),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!tappable) return box;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: box,
    );
  }
}

/// Entrance animation: fades in while sliding up a little. Give siblings
/// increasing [delay]s to stagger a screen so it assembles itself instead of
/// appearing all at once.
class NeoReveal extends StatefulWidget {
  const NeoReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<NeoReveal> createState() => _NeoRevealState();
}

class _NeoRevealState extends State<NeoReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Bordered, clipped surface for **full-bleed** content: photos, video,
/// segmented controls — anything that paints all the way to the edge.
///
/// Uses the same three passes as [NeoBox] (fill → content clipped to the
/// *inner* curve → stroke on top). Clipping to the outer shape instead lets
/// the content paint over the rounded corner and stick out past the stroke as
/// a little point, which is why raw `Container(clipBehavior: ...)` must not be
/// used for this.
class NeoFrame extends StatelessWidget {
  const NeoFrame({
    super.key,
    required this.child,
    this.color = Neo.white,
    this.radius = Neo.radiusSm,
    this.borderWidth = Neo.strokeThin,
    this.shadowOffset,
    this.width,
    this.height,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double borderWidth;

  /// Null means no block shadow (used for tiles inside another surface).
  final Offset? shadowOffset;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final outer = BorderRadius.circular(radius);
    final inner = (radius - borderWidth).clamp(0.0, radius);
    final off = shadowOffset;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: outer,
        boxShadow: off == null ? null : Neo.shadow(off),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Padding(
            padding: EdgeInsets.all(borderWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(inner),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: outer,
                  border: Border.all(color: Neo.ink, width: borderWidth),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The signature Neo button: pastel fill, black stroke, hard shadow, and a
/// real mechanical press — it slides onto its shadow when held.
class NeoButton extends StatefulWidget {
  const NeoButton({
    super.key,
    this.onPressed,
    this.child,
    this.label,
    this.icon,
    this.color = Neo.pink,
    this.expand = false,
    this.busy = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
    this.shadowOffset = Neo.shadowBtn,
    this.textStyle,
  });

  final VoidCallback? onPressed;
  final Widget? child;
  final String? label;
  final IconData? icon;
  final Color color;
  final bool expand;
  final bool busy;
  final EdgeInsetsGeometry padding;
  final Offset shadowOffset;
  final TextStyle? textStyle;

  @override
  State<NeoButton> createState() => _NeoButtonState();
}

class _NeoButtonState extends State<NeoButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final pressed = _down && enabled;
    final off = widget.shadowOffset;

    final baseStyle =
        (widget.textStyle ??
                Theme.of(context).textTheme.labelLarge ??
                const TextStyle())
            .copyWith(color: Neo.ink, fontWeight: FontWeight.w800);

    Widget content;
    if (widget.busy) {
      content = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 3, color: Neo.ink),
      );
    } else if (widget.child != null) {
      content = widget.child!;
    } else {
      final row = <Widget>[
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 20, color: Neo.ink),
          const SizedBox(width: 8),
        ],
        if (widget.label != null)
          Flexible(child: Text(widget.label!, style: baseStyle)),
      ];
      content = Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: row,
      );
    }

    final fill = enabled ? widget.color : const Color(0xFFE6DCC9);

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      curve: Curves.easeOut,
      width: widget.expand ? double.infinity : null,
      padding: widget.padding,
      transform: Matrix4.translationValues(
        pressed ? off.dx : 0,
        pressed ? off.dy : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: fill,
        border: Neo.border,
        borderRadius: Neo.corner,
        boxShadow: (pressed || !enabled) ? const [] : Neo.shadow(off),
      ),
      child: IconTheme(
        data: const IconThemeData(color: Neo.ink),
        child: DefaultTextStyle(
          style: baseStyle,
          textAlign: TextAlign.center,
          child: content,
        ),
      ),
    );

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            }
          : null,
      child: Opacity(opacity: enabled ? 1 : .6, child: button),
    );
  }
}

/// Square icon button with the same mechanical press.
class NeoIconButton extends StatefulWidget {
  const NeoIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color = Neo.white,
    this.iconColor = Neo.ink,
    this.size = 46,
    this.iconSize = 22,
    this.tooltip,
    this.shadowOffset = Neo.shadowSm,
    this.circle = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Offset shadowOffset;
  final bool circle;

  @override
  State<NeoIconButton> createState() => _NeoIconButtonState();
}

class _NeoIconButtonState extends State<NeoIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;
    final off = widget.shadowOffset;

    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      curve: Curves.easeOut,
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      transform: Matrix4.translationValues(
        pressed ? off.dx : 0,
        pressed ? off.dy : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: enabled ? widget.color : const Color(0xFFE6DCC9),
        border: Neo.border,
        // A true circle, not a rounded rect with an oversized radius: the
        // latter gets clamped and leaves the stroke's inner edge slightly oval.
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle ? null : Neo.cornerSm,
        boxShadow: (pressed || !enabled) ? const [] : Neo.shadow(off),
      ),
      child: Icon(widget.icon, size: widget.iconSize, color: widget.iconColor),
    );

    box = GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      child: Opacity(opacity: enabled ? 1 : .6, child: box),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: box);
    }
    return box;
  }
}

/// Circular avatar framed with a black stroke and a hard shadow.
class NeoAvatar extends StatelessWidget {
  const NeoAvatar({
    super.key,
    required this.size,
    this.child,
    this.color = Neo.white,
    this.shadowOffset = Neo.shadowSm,
    this.borderWidth = Neo.stroke,
  });

  final double size;
  final Widget? child;
  final Color color;
  final Offset shadowOffset;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    // Painted in three passes so the stroke never fights the content:
    //   1. fill + hard shadow on the outer circle,
    //   2. content clipped to the *inner* circle (inset by the stroke), and
    //   3. the ring on top.
    // Clipping to the outer circle instead — the obvious one-Container
    // version — leaves the child sitting under the stroke, and the two
    // antialiased edges meet as a ragged dark fringe.
    final inner = (size - borderWidth * 2).clamp(0.0, size);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: Neo.shadow(shadowOffset),
            ),
          ),
          if (child != null)
            ClipOval(
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: SizedBox(width: inner, height: inner, child: child),
            ),
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Neo.ink, width: borderWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small square badge holding an icon — used as a header adornment so icons
/// read as deliberate blocks rather than floating glyphs.
class NeoIconBadge extends StatelessWidget {
  const NeoIconBadge({
    super.key,
    required this.icon,
    this.color = Neo.yellow,
    this.size = 34,
    this.iconSize = 19,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        border: Neo.borderThin,
        borderRadius: Neo.cornerSm,
      ),
      child: Icon(icon, size: iconSize, color: Neo.ink),
    );
  }
}

/// Flat bordered tag/chip. Fills solid when [selected].
class NeoChip extends StatelessWidget {
  const NeoChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.color = Neo.lilac,
    this.onTap,
  });

  final String label;

  /// Optional leading glyph. Icons — never emoji — are the house style.
  final IconData? icon;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? color : Neo.white,
        border: Neo.borderThin,
        borderRadius: Neo.cornerSm,
        boxShadow: selected ? Neo.shadow(const Offset(2, 2)) : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Neo.ink),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Neo.ink,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: chip,
    );
  }
}

/// Inline error banner: solid danger-tinted block with a black stroke.
class NeoErrorBanner extends StatelessWidget {
  const NeoErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD9D9),
        border: Neo.border,
        borderRadius: Neo.cornerSm,
        boxShadow: Neo.shadow(const Offset(3, 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Neo.ink, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Neo.ink,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section label with a badge icon + heavy title, reused across sheets/forms.
class NeoSectionLabel extends StatelessWidget {
  const NeoSectionLabel({
    super.key,
    required this.icon,
    required this.label,
    this.color = Neo.yellow,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoIconBadge(icon: icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Neo.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
