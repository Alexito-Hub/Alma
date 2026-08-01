import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/local/isar/post_local.dart';
import '../../../data/remote/pin_gate.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/post_repository.dart';
import '../../../data/sync/sync_worker.dart';
import '../../widgets/neo_confirm_dialog.dart';
import 'post_detail_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _gridMode = false;
  String? _activeTag;

  Future<void> _editPost(PostLocal p) => _editPostFlow(context, ref, p);

  Future<void> _confirmDeletePost(PostLocal p) =>
      _confirmDeletePostFlow(context, ref, p);

  /// PIN gate: create the couple PIN on first use, verify afterwards, then
  /// open the private feed. Unlock lasts for this app session.
  Future<void> _openPrivate() async {
    final gate = PinGate.instance;
    if (!gate.unlocked) {
      bool isSet;
      try {
        isSet = await gate.isSet();
      } catch (_) {
        _snack('Necesitas conexión para abrir el feed privado');
        return;
      }
      if (!mounted) return;
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => _PinDialog(create: !isSet),
      );
      if (pin == null) return;
      try {
        if (isSet) {
          if (!await gate.verify(pin)) {
            _snack('PIN incorrecto');
            return;
          }
        } else {
          await gate.setPin(pin);
        }
      } catch (_) {
        _snack('No se pudo validar el PIN');
        return;
      }
      gate.unlocked = true;
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PrivateFeedScreen()));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(postsProvider);
    final myId = ref.watch(currentUserProvider)?.id;
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
                  const SizedBox(width: 8),
                  NeoIconButton(
                    icon: Icons.lock_outline_rounded,
                    tooltip: 'Feed privado',
                    color: Neo.rose,
                    onPressed: _openPrivate,
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
                            : _PostList(
                                posts: visible,
                                myId: myId,
                                onEdit: _editPost,
                                onDelete: _confirmDeletePost,
                              ),
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
  const _PostList({required this.posts, this.myId, this.onEdit, this.onDelete});
  final List<PostLocal> posts;
  final String? myId;
  final void Function(PostLocal)? onEdit;
  final void Function(PostLocal)? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final p = posts[i];
        final mine = myId != null && p.authorId == myId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () => _openPost(context, p),
            child: _PostCard(
              post: p,
              mine: mine,
              onEdit: mine && onEdit != null ? () => onEdit!(p) : null,
              onDelete: mine && onDelete != null ? () => onDelete!(p) : null,
            ),
          ),
        );
      },
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
  const _PostCard({
    required this.post,
    this.mine = false,
    this.onEdit,
    this.onDelete,
  });
  final PostLocal post;
  final bool mine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
                    if (onEdit != null) ...[
                      const SizedBox(width: 8),
                      NeoIconButton(
                        icon: Icons.edit_outlined,
                        size: 38,
                        iconSize: 17,
                        onPressed: onEdit,
                      ),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(width: 6),
                      NeoIconButton(
                        icon: Icons.delete_outline_rounded,
                        size: 38,
                        iconSize: 17,
                        onPressed: onDelete,
                      ),
                    ],
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

// ─── shared post actions (main + private feed) ───────────────────────────────

Future<void> _editPostFlow(
  BuildContext context,
  WidgetRef ref,
  PostLocal p,
) async {
  final result =
      await showDialog<({String title, String description, List<String> tags})>(
        context: context,
        builder: (_) => _EditPostDialog(post: p),
      );
  if (result == null) return;
  await ref
      .read(postRepositoryProvider)
      .update(
        isarId: p.isarId,
        title: result.title,
        description: result.description,
        tags: result.tags,
      );
  unawaited(runForegroundSync());
}

Future<void> _confirmDeletePostFlow(
  BuildContext context,
  WidgetRef ref,
  PostLocal p,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => NeoConfirmDialog(
      title: 'Eliminar publicación',
      message:
          '¿Quieres eliminar "${p.title}"? También se borran sus '
          'comentarios y desaparecerá para tu pareja.',
      confirmLabel: 'Eliminar',
    ),
  );
  if (ok == true) {
    await ref.read(postRepositoryProvider).delete(p.isarId);
    unawaited(runForegroundSync());
  }
}

// ─── private feed (PIN-gated) ────────────────────────────────────────────────

/// Private couple-only feed behind the PIN gate. These posts never appear in
/// the main feed or grid, and their media lives only inside the app (nothing
/// is written to the device gallery).
class PrivateFeedScreen extends ConsumerWidget {
  const PrivateFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts =
        ref.watch(privatePostsProvider).valueOrNull ?? const <PostLocal>[];
    final myId = ref.watch(currentUserProvider)?.id;
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  const NeoIconBadge(icon: Icons.lock_rounded, color: Neo.rose),
                  const SizedBox(width: 10),
                  Text('Feed privado', style: txt.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: posts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Nada privado aún. Al capturar un momento, marca '
                          '"Privado" y aparecerá solo aquí.',
                          textAlign: TextAlign.center,
                          style: txt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _PostList(
                      posts: posts,
                      myId: myId,
                      onEdit: (p) => _editPostFlow(context, ref, p),
                      onDelete: (p) => _confirmDeletePostFlow(context, ref, p),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for (or creates) the couple's private-feed PIN. Pops the entered PIN.
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.create});
  final bool create;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pin.text.trim();
    if (p.length < 4) {
      setState(() => _error = 'El PIN necesita al menos 4 dígitos');
      return;
    }
    if (widget.create && p != _confirm.text.trim()) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.create ? 'Crear PIN privado' : 'Feed privado',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.create
                  ? 'Este PIN lo compartirán los dos para ver lo privado.'
                  : 'Ingresa el PIN de pareja.',
              textAlign: TextAlign.center,
              style: txt.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN'),
              onSubmitted: (_) {
                if (!widget.create) _submit();
              },
            ),
            if (widget.create) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Confirmar PIN'),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              NeoErrorBanner(message: _error!),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    label: 'Cancelar',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeoButton(
                    label: widget.create ? 'Crear' : 'Entrar',
                    color: Neo.rose,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Text-only edit of an own post: title, description and tags. Media stays
/// immutable (delete + re-publish to change it).
class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({required this.post});
  final PostLocal post;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.post.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.post.description,
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.post.tags.map((t) => '#$t').join(' '),
  );

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar publicación',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Título'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Descripción (opcional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                hintText: 'Tags separadas por espacio (#viaje #risa)',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    label: 'Cancelar',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeoButton(
                    label: 'Guardar',
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () {
                      final tags = _tags.text
                          .split(RegExp(r'[\s,]+'))
                          .where((t) => t.isNotEmpty)
                          .map((t) => t.replaceAll('#', '').toLowerCase())
                          .toList();
                      Navigator.pop(context, (
                        title: _title.text.trim().isEmpty
                            ? 'Sin título'
                            : _title.text.trim(),
                        description: _description.text.trim(),
                        tags: tags,
                      ));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
