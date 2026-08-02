import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../../core/theme/neo.dart';

/// Flat neo-brutalist card showing the partner's most recent status
/// (their breve "qué siento ahora"). Animates whenever the text changes and
/// shows a relative timestamp ("hace 5 min").
class StatusBox extends StatelessWidget {
  const StatusBox({
    super.key,
    required this.text,
    this.updatedAt,
    this.partnerLabel,
    this.imagePath,
    this.imageUrl,
  });

  final String? text;
  final DateTime? updatedAt;
  final String? partnerLabel;

  /// The snapshot that came with the status: a downloaded local copy when we
  /// have one, otherwise the server URL.
  final String? imagePath;
  final String? imageUrl;

  bool get _isEmpty => text == null || text!.trim().isEmpty;
  bool get _hasPhoto =>
      (imagePath != null && imagePath!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final showText = _isEmpty ? '…esperando un pensamiento' : text!;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: NeoBox(
        key: ValueKey(showText),
        width: double.infinity,
        color: Neo.mint,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const NeoIconBadge(
                  icon: Icons.favorite_rounded,
                  color: Neo.white,
                  size: 28,
                  iconSize: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (partnerLabel == null
                            ? 'tu pareja siente'
                            : '$partnerLabel siente')
                        .toUpperCase(),
                    style: txt.labelSmall?.copyWith(letterSpacing: 1.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (updatedAt != null)
                  Text(
                    _relative(updatedAt!),
                    style: txt.labelSmall?.copyWith(
                      color: Neo.ink.withValues(alpha: .6),
                    ),
                  ),
              ],
            ),
            if (_hasPhoto) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: Neo.cornerSm,
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Neo.borderThin),
                    child: _photo(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (!(_isEmpty && _hasPhoto))
              Text(
                showText,
                style: txt.titleMedium?.copyWith(
                  fontStyle: _isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: Neo.ink.withValues(alpha: _isEmpty ? .55 : 1),
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _photo() {
    if (imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }
    final url = imageUrl!.startsWith('http')
        ? imageUrl!
        : '${Env.apiBaseUrl}${imageUrl!}';
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) =>
          const ColoredBox(color: Neo.white, child: Icon(Icons.image_outlined)),
    );
  }

  static String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return '${t.day}/${t.month}';
  }
}
