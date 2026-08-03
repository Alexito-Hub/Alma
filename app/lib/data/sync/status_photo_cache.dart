import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/env.dart';

/// Download a status snapshot into the cache directory and return its local
/// path, re-using an existing copy so repeated hydrations don't re-fetch.
///
/// The home-screen widget can only read files, never URLs, so every path that
/// feeds it goes through here. Takes the [dio] to use because the background
/// isolate has its own client — that difference is the only reason this lived
/// twice, once in [Hydrator] and once in the WorkManager entrypoint.
Future<String?> cacheStatusPhotoWith(Dio dio, String? url) async {
  if (url == null || url.isEmpty) return null;
  final absolute = url.startsWith('http') ? url : '${Env.apiBaseUrl}$url';
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/status_${absolute.hashCode}.img');
    if (await file.exists()) return file.path;
    final res = await dio.get<List<int>>(
      absolute,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) return null;
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}
