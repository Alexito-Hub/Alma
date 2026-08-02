import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/local/isar/post_local.dart';
import '../../../data/remote/api_client.dart';
import '../../../data/remote/endpoints.dart';
import '../../../data/remote/ws_client.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/comment_repository.dart';

/// Full-screen view of a single post: the photo at full size (pinch to zoom),
/// its details, and the conversation — inline, not tucked into a sheet.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});
  final PostLocal post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _input = TextEditingController();
  StreamSubscription<dynamic>? _wsSub;
  bool _sending = false;

  String? get _postId => widget.post.remoteId;

  @override
  void initState() {
    super.initState();
    if (_postId != null) _bootstrap(_postId!);
  }

  Future<void> _bootstrap(String postId) async {
    final repo = ref.read(commentRepositoryProvider);
    try {
      final res = await ApiClient.instance.dio.get(
        Endpoints.postComments(postId),
      );
      for (final c in (res.data['comments'] as List? ?? const [])) {
        await repo.upsertFromRemote(Map<String, dynamic>.from(c as Map));
      }
    } catch (_) {
      /* offline → local rows still render */
    }

    try {
      final socket = await WsClient.instance.connect();
      final ch = socket.addChannel(topic: 'post:$postId');
      await ch.join().future;
      _wsSub = ch.messages.listen((msg) async {
        if (msg.event.value == 'new_comment' && msg.payload != null) {
          await repo.upsertFromRemote(Map<String, dynamic>.from(msg.payload!));
        }
      });
    } catch (_) {
      /* WS unavailable */
    }

    await repo.flushPending(postId: postId);
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final postId = _postId;
    if (text.isEmpty || _sending || postId == null) return;
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    setState(() => _sending = true);
    try {
      final repo = ref.read(commentRepositoryProvider);
      await repo.create(postId: postId, authorId: me.id, text: text);
      _input.clear();
      await repo.flushPending(postId: postId);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final hasMedia =
        post.localMediaPaths.isNotEmpty || post.remoteMediaUrls.isNotEmpty;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      post.title,
                      style: txt.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const _InkLine(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (hasMedia) ...[
                    _FullMedia(post: post),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Text(
                        DateFormat('d MMM y', 'es').format(post.createdAt),
                        style: txt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (post.syncStatus != 'synced') ...[
                        const SizedBox(width: 8),
                        Icon(
                          post.syncStatus == 'failed'
                              ? Icons.error_outline_rounded
                              : Icons.schedule_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  if (post.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      post.description,
                      style: txt.bodyLarge?.copyWith(height: 1.45),
                    ),
                  ],
                  if (post.tags.isNotEmpty) ...[
                    const SizedBox(height: 14),
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
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const NeoIconBadge(
                        icon: Icons.mode_comment_rounded,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Text('Comentarios', style: txt.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CommentsList(postId: _postId),
                ],
              ),
            ),
            if (_postId != null) ...[
              const _InkLine(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Escribe un comentario…',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    NeoIconButton(
                      icon: Icons.send_rounded,
                      color: Neo.pink,
                      size: 54,
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentsList extends ConsumerWidget {
  const _CommentsList({required this.postId});
  final String? postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (postId == null) {
      return Text(
        'Esta publicación aún no se sincroniza; podrás comentar cuando suba.',
        style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return ref
        .watch(commentsForPostProvider(postId!))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) {
              return Text(
                'Sé el primero en comentar',
                style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              );
            }
            final me = ref.watch(currentUserProvider);
            final partner = ref.watch(partnerUserProvider);
            return Column(
              children: [
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CommentTile(
                      mine: c.authorId == me?.id,
                      author: c.authorId == me?.id
                          ? (me?.prettyName ?? 'tú')
                          : (partner?.prettyName ?? 'pareja'),
                      text: c.text,
                      pending: c.syncStatus != 'synced',
                    ),
                  ),
              ],
            );
          },
        );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.mine,
    required this.author,
    required this.text,
    required this.pending,
  });
  final bool mine;
  final String author;
  final String text;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      width: double.infinity,
      color: mine ? Neo.rose : Neo.white,
      padding: const EdgeInsets.all(12),
      shadowOffset: const Offset(3, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mine ? Icons.person_rounded : Icons.favorite_rounded,
                size: 14,
                color: Neo.ink,
              ),
              const SizedBox(width: 5),
              Text(author, style: txt.labelSmall?.copyWith(color: Neo.ink)),
              const Spacer(),
              if (pending)
                const Icon(Icons.schedule_rounded, size: 13, color: Neo.ink),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: txt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Full-size, pinch-to-zoom media inside a black-bordered frame.
class _FullMedia extends StatelessWidget {
  const _FullMedia({required this.post});
  final PostLocal post;

  @override
  Widget build(BuildContext context) {
    final hasLocal = post.localMediaPaths.isNotEmpty;
    final Widget image = hasLocal
        ? Image.file(File(post.localMediaPaths.first), fit: BoxFit.contain)
        : CachedNetworkImage(
            imageUrl: '${Env.apiBaseUrl}${post.remoteMediaUrls.first}',
            fit: BoxFit.contain,
            errorWidget: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: Neo.ink),
          );

    return Container(
      decoration: BoxDecoration(
        color: Neo.white,
        border: Neo.border,
        borderRadius: Neo.corner,
        boxShadow: Neo.shadow(Neo.shadowBtn),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: image),
        ),
      ),
    );
  }
}

class _InkLine extends StatelessWidget {
  const _InkLine();
  @override
  Widget build(BuildContext context) =>
      Container(height: Neo.strokeThin, color: Neo.ink);
}
