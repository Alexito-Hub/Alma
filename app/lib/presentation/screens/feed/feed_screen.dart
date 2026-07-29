import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/local/isar/post_local.dart';
import '../../../data/repositories/post_repository.dart';
import 'post_detail_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _gridMode = false;
  String? _activeTag;

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(postsProvider);
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 16, 8),
              child: Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.photo_library_rounded,
                    color: Neo.sky,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nuestro feed', style: txt.titleLarge),
                        Text(
                          'Recuerdos compartidos',
                          style: txt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ModeToggle(
                    gridMode: _gridMode,
                    onChanged: (v) => setState(() => _gridMode = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: postsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const _EmptyFeed(),
                data: (all) {
                  final visible = _activeTag == null
                      ? all
                      : all.where((p) => p.tags.contains(_activeTag)).toList();
                  if (all.isEmpty) return const _EmptyFeed();

                  return Column(
                    children: [
                      _TagsStrip(
                        posts: all,
                        active: _activeTag,
                        onTap: (t) => setState(
                          () => _activeTag = _activeTag == t ? null : t,
                        ),
                      ),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  'Sin publicaciones con #$_activeTag',
                                  style: txt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : _gridMode
                            ? _PostGrid(posts: visible)
                            : _PostList(posts: visible),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── header bits ─────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.gridMode, required this.onChanged});
  final bool gridMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Neo.white,
        border: Neo.border,
        borderRadius: Neo.cornerSm,
        boxShadow: Neo.shadow(const Offset(3, 3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: Icons.view_agenda_rounded,
            active: !gridMode,
            onTap: () => onChanged(false),
          ),
          Container(width: Neo.strokeThin, height: 40, color: Neo.ink),
          _PillButton(
            icon: Icons.grid_view_rounded,
            active: gridMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 40,
        alignment: Alignment.center,
        color: active ? Neo.pink : Neo.white,
        child: Icon(icon, size: 19, color: Neo.ink),
      ),
    );
  }
}

class _TagsStrip extends StatelessWidget {
  const _TagsStrip({
    required this.posts,
    required this.active,
    required this.onTap,
  });
  final List<PostLocal> posts;
  final String? active;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tags = <String>{};
    for (final p in posts) {
      tags.addAll(p.tags);
    }
    if (tags.isEmpty) return const SizedBox(height: 8);

    final list = tags.toList();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = list[i];
          return Center(
            child: NeoChip(
              label: '#$t',
              selected: active == t,
              color: Neo.pastel(i),
              onTap: () => onTap(t),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NeoAvatar(
              size: 88,
              color: Neo.sky,
              child: Icon(
                Icons.photo_library_rounded,
                size: 42,
                color: Neo.ink,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin publicaciones aún',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Comparte una foto, un viaje o un recuerdo. Aparecerá aquí en orden cronológico.',
              style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── list / grid ─────────────────────────────────────────────────────────────

class _PostList extends StatelessWidget {
  const _PostList({required this.posts});
  final List<PostLocal> posts;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: posts.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: () => _openPost(context, posts[i]),
          child: _PostCard(post: posts[i]),
        ),
      ),
    );
  }
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.posts});
  final List<PostLocal> posts;

  @override
  Widget build(BuildContext context) {
    final media = posts
        .where(
          (p) => p.localMediaPaths.isNotEmpty || p.remoteMediaUrls.isNotEmpty,
        )
        .toList();
    if (media.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aún no hay imágenes para mostrar en cuadrícula',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: media.length,
      itemBuilder: (_, i) {
        final p = media[i];
        return GestureDetector(
          onTap: () => _openPost(context, p),
          child: Container(
            decoration: BoxDecoration(
              border: Neo.borderThin,
              borderRadius: Neo.cornerSm,
              boxShadow: Neo.shadow(const Offset(3, 3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _MediaThumb(post: p),
          ),
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.post});
  final PostLocal post;

  @override
  Widget build(BuildContext context) {
    final hasLocal = post.localMediaPaths.isNotEmpty;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: hasLocal
          ? Image.file(File(post.localMediaPaths.first), fit: BoxFit.cover)
          : CachedNetworkImage(
              imageUrl: '${Env.apiBaseUrl}${post.remoteMediaUrls.first}',
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined),
            ),
    );
  }
}

/// Feed media that sizes itself to the photo's real aspect ratio. Wide shots
/// show fully; tall (portrait) shots are clamped so a single photo can't take
/// over the whole feed.
class _AdaptiveMedia extends StatefulWidget {
  const _AdaptiveMedia({required this.post});
  final PostLocal post;

  @override
  State<_AdaptiveMedia> createState() => _AdaptiveMediaState();
}

class _AdaptiveMediaState extends State<_AdaptiveMedia> {
  late final ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _provider = p.localMediaPaths.isNotEmpty
        ? FileImage(File(p.localMediaPaths.first))
        : CachedNetworkImageProvider(
            '${Env.apiBaseUrl}${p.remoteMediaUrls.first}',
          );
    _stream = _provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _ratio = info.image.width / info.image.height);
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Until we know the real size, assume 4:3; then clamp so portraits don't
    // exceed ~5:4 tall and panoramas don't get too short.
    final ratio = (_ratio ?? 4 / 3).clamp(0.8, 1.9);
    return AspectRatio(
      aspectRatio: ratio,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Image(
          image: _provider,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

// ─── card ────────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final PostLocal post;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final hasMedia =
        post.localMediaPaths.isNotEmpty || post.remoteMediaUrls.isNotEmpty;

    return NeoBox(
      width: double.infinity,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMedia)
            Stack(
              children: [
                _AdaptiveMedia(post: post),
                // Solid caption block — flat, no gradient.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: Neo.ink,
                      border: Border(
                        top: BorderSide(color: Neo.ink, width: Neo.strokeThin),
                      ),
                    ),
                    child: Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: txt.titleMedium?.copyWith(color: Neo.white),
                    ),
                  ),
                ),
              ],
            ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: hasMedia
                  ? const Border(
                      top: BorderSide(color: Neo.ink, width: Neo.stroke),
                    )
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasMedia)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(post.title, style: txt.titleLarge),
                  ),
                if (post.description.isNotEmpty)
                  Text(
                    post.description,
                    style: txt.bodyMedium?.copyWith(height: 1.4),
                  ),
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < post.tags.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Neo.pastel(i),
                            border: Neo.borderThin,
                            borderRadius: Neo.cornerSm,
                          ),
                          child: Text(
                            '#${post.tags[i]}',
                            style: txt.labelSmall?.copyWith(color: Neo.ink),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    NeoButton(
                      label: 'Comentar',
                      icon: Icons.mode_comment_rounded,
                      color: Neo.yellow,
                      shadowOffset: Neo.shadowSm,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      textStyle: txt.labelMedium,
                      onPressed: () => _openPost(context, post),
                    ),
                    const Spacer(),
                    if (post.syncStatus != 'synced')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          post.syncStatus == 'failed'
                              ? Icons.error_outline_rounded
                              : Icons.schedule_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      DateFormat('d MMM', 'es').format(post.createdAt),
                      style: txt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── open detail ─────────────────────────────────────────────────────────────

void _openPost(BuildContext context, PostLocal post) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
}
