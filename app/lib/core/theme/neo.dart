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

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      width: widget.width,
      margin: widget.margin,
      padding: widget.padding,
      transform: Matrix4.translationValues(
        pressed ? off.dx : 0,
        pressed ? off.dy : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: widget.color,
        border: Border.all(color: Neo.ink, width: widget.borderWidth),
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: pressed ? const [] : Neo.shadow(off),
      ),
      // antiAliasWithSaveLayer avoids the child colour bleeding ~1px past the
      // rounded corners (the little "punta" over the black border).
      clipBehavior: widget.clip ? Clip.antiAliasWithSaveLayer : Clip.none,
      child: widget.child,
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
        borderRadius: widget.circle
            ? BorderRadius.circular(widget.size)
            : Neo.cornerSm,
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Neo.ink, width: borderWidth),
        boxShadow: Neo.shadow(shadowOffset),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
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
    this.selected = false,
    this.color = Neo.lilac,
    this.onTap,
  });

  final String label;
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
      child: Text(
        label,
        style: const TextStyle(
          color: Neo.ink,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
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
