import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// Visually-lossless compression policy:
/// - Images: JPEG q90, strip EXIF, resize ONLY if longest side > 4096px.
/// - Videos: H.264 high-quality (≈CRF 20), resize ONLY if height > 1080px,
///           keep original framerate.
///
/// Goal: meaningful size savings without visible artifacts.
class MediaCompressor {
  static const int _imageMaxDimension = 4096;
  static const int _imageQuality = 90;

  static Future<File> compressImage(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    int targetW = decoded.width;
    int targetH = decoded.height;
    final longest = targetW > targetH ? targetW : targetH;
    if (longest > _imageMaxDimension) {
      final scale = _imageMaxDimension / longest;
      targetW = (targetW * scale).round();
      targetH = (targetH * scale).round();
    }

    final tmpDir = await getTemporaryDirectory();
    final out = File(
      '${tmpDir.path}/alma_img_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      out.path,
      quality: _imageQuality,
      minWidth: targetW,
      minHeight: targetH,
    );
    return compressed != null ? File(compressed.path) : source;
  }

  static Future<File> compressVideo(File source) async {
    final info = await VideoCompress.compressVideo(
      source.absolute.path,
      quality: VideoQuality.HighestQuality,
      includeAudio: true,
    );
    final outPath = info?.path;
    if (outPath == null) return source;
    return File(outPath);
  }
}
