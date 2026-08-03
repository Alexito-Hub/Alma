import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/local/isar/note_local.dart';
import '../../../data/remote/api_client.dart';
import '../../widgets/post_media.dart';
import 'diary_screen.dart' show entryMediaSources;

/// Turns a diary entry into a shareable image in Alma's own style.
///
/// The preview below is the exact widget that gets rasterised, so what you see
/// is what gets shared: cream canvas, black strokes, the entry's photo (or a
/// video's poster frame), its text, mood and place — and no app chrome, since
/// the composer and navigation aren't part of the card.
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({super.key, required this.note, required this.author});

  final NoteLocal note;
  final String author;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  Future<Uint8List?> _render() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 3x so the card still looks crisp when opened on another phone.
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      if (bytes == null) throw StateError('render failed');

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/alma_${widget.note.isarId}_'
        '${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], fileNameOverrides: ['alma.png']),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar la imagen')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Share the clip itself rather than a still of it. A local file goes
  /// straight out; a synced one is downloaded to the cache first, because the
  /// share sheet can only hand over files that exist on this device.
  Future<void> _shareVideo(String src) async {
    setState(() => _busy = true);
    try {
      var path = src;
      if (src.startsWith('http')) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/alma_video_${src.hashCode}.mp4');
        if (!await file.exists()) {
          await ApiClient.instance.dio.download(src, file.path);
        }
        path = file.path;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo compartir el vídeo')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final videos = entryMediaSources(
      widget.note,
    ).where(MediaTools.isVideo).toList();

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Compartir recuerdo', style: txt.titleLarge),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Center(
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: _EntryCard(note: widget.note, author: widget.author),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  if (videos.isNotEmpty) ...[
                    NeoButton(
                      label: videos.length == 1
                          ? 'Compartir el vídeo'
                          : 'Compartir el primer vídeo',
                      icon: Icons.movie_rounded,
                      color: Neo.lilac,
                      expand: true,
                      busy: _busy,
                      onPressed: () => _shareVideo(videos.first),
                    ),
                    const SizedBox(height: 10),
                  ],
                  NeoButton(
                    label: 'Compartir la tarjeta',
                    icon: Icons.ios_share_rounded,
                    expand: true,
                    busy: _busy,
                    onPressed: _share,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card itself. Deliberately self-contained: no providers, no scrolling —
/// everything it needs is passed in so it rasterises identically off-screen.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.note, required this.author});

  final NoteLocal note;
  final String author;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final media = entryMediaSources(note);
    final cover = media.isEmpty ? null : media.first;

    return Container(
      width: 340,
      color: Neo.paper,
      padding: const EdgeInsets.all(18),
      child: NeoBox(
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header strip, same language as the diary card.
            Container(
              width: double.infinity,
              color: Neo.pink,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  if (note.mood != null) ...[
                    Text(note.mood!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: txt.labelLarge?.copyWith(color: Neo.ink),
                    ),
                  ),
                  Text(
                    DateFormat("d 'de' MMMM, y", 'es').format(note.createdAt),
                    style: txt.labelSmall?.copyWith(
                      color: Neo.ink.withValues(alpha: .75),
                    ),
                  ),
                ],
              ),
            ),
            if (cover != null)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: MediaTools.isVideo(cover)
                    ? VideoPosterImage(src: cover)
                    : postMediaTile(cover),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                note.body,
                style: txt.bodyLarge?.copyWith(
                  color: Neo.ink,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if ((note.placeLabel ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    const Icon(Icons.place_rounded, size: 14, color: Neo.ink),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        note.placeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: txt.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            // Signature line — it's a couple's keepsake, so it's branded.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logotype/alma.png',
                    height: 22,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ALMA',
                    style: txt.labelSmall?.copyWith(
                      letterSpacing: 3,
                      color: Neo.ink.withValues(alpha: .6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
