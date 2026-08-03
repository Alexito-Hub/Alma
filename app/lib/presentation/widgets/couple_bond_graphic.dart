import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/neo.dart';
import '../../data/remote/media_headers.dart';

/// Two framed avatars joined by a solid black bond, with a heart block that
/// beats in the middle. Pure neo-brutalism: hard strokes, flat fills, block
/// shadows — no glows, no gradients. Lives at the bottom of the Dashboard.
class CoupleBondGraphic extends StatefulWidget {
  const CoupleBondGraphic({
    super.key,
    required this.leftAvatarUrl,
    required this.rightAvatarUrl,
    this.leftLabel,
    this.rightLabel,
  });

  final String? leftAvatarUrl;
  final String? rightAvatarUrl;
  final String? leftLabel;
  final String? rightLabel;

  @override
  State<CoupleBondGraphic> createState() => _CoupleBondGraphicState();
}

class _CoupleBondGraphicState extends State<CoupleBondGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 84,
          child: Row(
            children: [
              _Avatar(url: widget.leftAvatarUrl),
              Expanded(
                child: SizedBox(
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Solid black bond line.
                      Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: Neo.ink,
                      ),
                      // Beating heart block. RepaintBoundary keeps this
                      // continuous animation off the Dashboard's raster; the
                      // const avatar is passed as `child` so only the scale
                      // rebuilds each tick.
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _beat,
                          builder: (_, child) {
                            final t = Curves.easeInOut.transform(_beat.value);
                            return Transform.scale(
                              scale: .9 + t * .22,
                              child: child,
                            );
                          },
                          child: const NeoAvatar(
                            size: 46,
                            color: Neo.pink,
                            child: Icon(
                              Icons.favorite,
                              size: 22,
                              color: Neo.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _Avatar(url: widget.rightAvatarUrl),
            ],
          ),
        ),
        if (_hasLabels) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _NameTag(widget.leftLabel)),
              const SizedBox(width: 52),
              Expanded(child: _NameTag(widget.rightLabel)),
            ],
          ),
        ],
      ],
    );
  }

  bool get _hasLabels =>
      (widget.leftLabel != null && widget.leftLabel!.isNotEmpty) ||
      (widget.rightLabel != null && widget.rightLabel!.isNotEmpty);
}

class _NameTag extends StatelessWidget {
  const _NameTag(this.label);
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null || label!.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Neo.white,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Text(
          label!,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Neo.ink,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return NeoAvatar(
      size: 72,
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
              httpHeaders: mediaHeaders(),
              fit: BoxFit.cover,
              width: 72,
              height: 72,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.person, color: Neo.ink),
            )
          : const Icon(Icons.person, size: 30, color: Neo.ink),
    );
  }
}
