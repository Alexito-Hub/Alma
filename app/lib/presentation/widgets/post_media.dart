import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/env.dart';
import '../../core/theme/neo.dart';
import '../../data/device/media_tools.dart';
import '../../data/device/video_poster.dart';
import '../../data/remote/media_headers.dart';

String absoluteMediaUrl(String u) =>
    u.startsWith('http') ? u : '${Env.apiBaseUrl}$u';

bool isRemoteSource(String src) => src.startsWith('http');

/// One photo or video, sized by its parent.
Widget postMediaTile(String src) {
  if (MediaTools.isVideo(src)) {
    return FeedVideo(src: src, remote: isRemoteSource(src));
  }
  return ColoredBox(
    color: Neo.white,
    child: isRemoteSource(src)
        ? CachedNetworkImage(
            imageUrl: src,
            // `/media` needs a session now; a request without this comes back
            // 401 and renders as a broken image.
            httpHeaders: mediaHeaders(),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorWidget: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          )
        : Image.file(
            File(src),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
  );
}

ImageProvider mediaImageProvider(String src) => isRemoteSource(src)
    ? CachedNetworkImageProvider(src, headers: mediaHeaders()) as ImageProvider
    : FileImage(File(src));

/// Swipeable media for a post or a diary entry.
///
/// The frame takes the proportions of **the item currently on screen**, so a
/// portrait photo, a panorama and a vertical clip each get the shape they
/// deserve instead of everything being forced into the first one's box.
/// Tapping opens the full-screen viewer.
class PostMediaCarousel extends StatefulWidget {
  const PostMediaCarousel({
    super.key,
    required this.sources,
    this.tapToOpen = true,
  });

  final List<String> sources;
  final bool tapToOpen;

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel> {
  final _pager = PageController();
  final Map<int, double> _ratios = {};
  final Map<int, ImageStream> _streams = {};
  final Map<int, ImageStreamListener> _listeners = {};
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _measure(0);
  }

  @override
  void didUpdateWidget(covariant PostMediaCarousel old) {
    super.didUpdateWidget(old);
    if (old.sources.join('|') != widget.sources.join('|')) {
      _detachAll();
      _ratios.clear();
      _page = 0;
      _measure(0);
    }
  }

  /// Resolve an item's aspect ratio. Photos are measured from the decoded
  /// image; videos from their poster frame, so the frame already has the
  /// clip's shape before anyone presses play.
  void _measure(int index) {
    if (index < 0 || index >= widget.sources.length) return;
    if (_ratios.containsKey(index) || _streams.containsKey(index)) return;
    final src = widget.sources[index];

    if (MediaTools.isVideo(src)) {
      VideoPoster.of(src).then((file) {
        if (!mounted || file == null || _ratios.containsKey(index)) return;
        _attach(index, FileImage(file));
      });
      return;
    }
    _attach(index, mediaImageProvider(src));
  }

  void _attach(int index, ImageProvider provider) {
    if (_streams.containsKey(index)) return;
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _ratios[index] = info.image.width / info.image.height);
    });
    _streams[index] = stream;
    _listeners[index] = listener;
    stream.addListener(listener);
  }

  void _detachAll() {
    for (final entry in _streams.entries) {
      final l = _listeners[entry.key];
      if (l != null) entry.value.removeListener(l);
    }
    _streams.clear();
    _listeners.clear();
  }

  @override
  void dispose() {
    _detachAll();
    _pager.dispose();
    super.dispose();
  }

  void _open(int index) {
    if (!widget.tapToOpen) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MediaViewerScreen(sources: widget.sources, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return const SizedBox.shrink();

    // Current item's shape, falling back to the first known one while a photo
    // is still decoding. Clamped so nothing gets absurdly tall or short.
    final ratio = (_ratios[_page] ?? _ratios[0] ?? 4 / 3).clamp(0.6, 2.2);

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pager,
              onPageChanged: (i) {
                setState(() => _page = i);
                _measure(i);
                _measure(i + 1);
              },
              itemCount: widget.sources.length,
              itemBuilder: (_, i) {
                final src = widget.sources[i];
                if (MediaTools.isVideo(src)) {
                  return FeedVideo(
                    src: src,
                    remote: isRemoteSource(src),
                    onRatio: (r) {
                      if (!mounted || _ratios[i] == r) return;
                      setState(() => _ratios[i] = r);
                    },
                    onOpenFullScreen: widget.tapToOpen ? () => _open(i) : null,
                  );
                }
                return GestureDetector(
                  onTap: () => _open(i),
                  child: postMediaTile(src),
                );
              },
            ),
            if (widget.sources.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Neo.white,
                    border: Neo.borderThin,
                    borderRadius: Neo.cornerSm,
                  ),
                  child: Text(
                    '${_page + 1}/${widget.sources.length}',
                    style: const TextStyle(
                      color: Neo.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen viewer: swipe between everything the moment carries, pinch to
/// zoom a photo, play a clip. Deliberately dark so the media reads.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.sources,
    this.initialIndex = 0,
  });

  final List<String> sources;
  final int initialIndex;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pager = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Neo.ink,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pager,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.sources.length,
            itemBuilder: (_, i) {
              final src = widget.sources[i];
              if (MediaTools.isVideo(src)) {
                return FeedVideo(
                  src: src,
                  remote: isRemoteSource(src),
                  fit: BoxFit.contain,
                  background: Neo.ink,
                );
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: mediaImageProvider(src),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Neo.white,
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  NeoIconButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (widget.sources.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Neo.white,
                        border: Neo.borderThin,
                        borderRadius: Neo.cornerSm,
                      ),
                      child: Text(
                        '${_page + 1}/${widget.sources.length}',
                        style: const TextStyle(
                          color: Neo.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A video's cover frame, extracted once and cached. Falls back to a flat neo
/// surface while it's being produced, or if the device can't decode the clip.
class VideoPosterImage extends StatelessWidget {
  const VideoPosterImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.background = Neo.lilac,
  });

  final String src;
  final BoxFit fit;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: VideoPoster.of(src),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return ColoredBox(color: background);
        return ColoredBox(
          color: background,
          child: Image.file(
            file,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => ColoredBox(color: background),
          ),
        );
      },
    );
  }
}

/// Video inside a post. Shows its poster frame with a play button, and only
/// spins up the player once tapped.
class FeedVideo extends StatefulWidget {
  const FeedVideo({
    super.key,
    required this.src,
    required this.remote,
    this.fit = BoxFit.cover,
    this.background = Neo.lilac,
    this.onRatio,
    this.onOpenFullScreen,
  });

  final String src;
  final bool remote;
  final BoxFit fit;
  final Color background;

  /// Reports the clip's real aspect ratio once known, so the surrounding
  /// carousel can take its shape.
  final ValueChanged<double>? onRatio;

  /// Shown as a corner button when the parent can open a full-screen view.
  final VoidCallback? onOpenFullScreen;

  @override
  State<FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<FeedVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;

  /// Never keep a previous clip's player when the widget is recycled for
  /// another source (list reordering after a delete).
  @override
  void didUpdateWidget(covariant FeedVideo old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
    }
  }

  Future<void> _start() async {
    final c = widget.remote
        ? VideoPlayerController.networkUrl(
            Uri.parse(widget.src),
            httpHeaders: mediaHeaders(),
          )
        : VideoPlayerController.file(File(widget.src));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      final size = c.value.size;
      if (size.height > 0) {
        widget.onRatio?.call(size.width / size.height);
      }
      await c.play();
      c.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      // Codec or network trouble — the placeholder stays put.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final playing = _ready && c != null && c.value.isPlaying;

    return GestureDetector(
      onTap: () {
        if (!_ready) {
          _start();
        } else if (c != null) {
          playing ? c.pause() : c.play();
          setState(() {});
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && c != null)
            FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          else
            VideoPosterImage(
              src: widget.src,
              fit: widget.fit,
              background: widget.background,
            ),
          if (!playing)
            Center(
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Neo.pink,
                  border: Neo.border,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Neo.ink,
                  size: 30,
                ),
              ),
            ),
          if (widget.onOpenFullScreen != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: widget.onOpenFullScreen,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Neo.white,
                    border: Neo.borderThin,
                    borderRadius: Neo.cornerSm,
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    size: 18,
                    color: Neo.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
