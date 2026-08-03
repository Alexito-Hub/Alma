import 'dart:io';

import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

import '../remote/media_headers.dart';

/// Poster frames for videos, so a clip is recognisable at a glance instead of
/// being a flat coloured block — the way a gallery shows them.
///
/// Each frame is extracted once and cached on disk under a name derived from
/// the source, then remembered in memory for the rest of the session. Failures
/// are cached too (as null) so a codec the device can't read isn't retried on
/// every rebuild.
class VideoPoster {
  VideoPoster._();

  static final Map<String, Future<File?>> _cache = {};

  /// Returns a JPEG frame for [source] (a local path or a URL), or null when
  /// one can't be produced.
  static Future<File?> of(String source) =>
      _cache.putIfAbsent(source, () => _generate(source));

  static Future<File?> _generate(String source) async {
    try {
      final dir = await getTemporaryDirectory();
      final cached = File('${dir.path}/poster_${source.hashCode}.jpg');
      if (await cached.exists() && await cached.length() > 0) return cached;

      final thumb = await VideoThumbnail.thumbnailFile(
        video: source,
        // A remote clip is fetched over HTTP to grab the frame, and `/media`
        // is authenticated now. Harmless for a local path.
        headers: source.startsWith('http') ? mediaHeaders() : null,
        thumbnailPath: cached.path,
        imageFormat: ImageFormat.JPEG,
        // Big enough for a full-width card, small enough to stay cheap.
        maxHeight: 720,
        quality: 70,
      );

      final file = File(thumb.path);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }
}
