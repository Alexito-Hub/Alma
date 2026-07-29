import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phoenix_socket/phoenix_socket.dart';

import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/ws_client.dart';
import '../sync/media_compressor.dart';
import 'auth_repository.dart';

final coupleSettingsRepositoryProvider = Provider<CoupleSettingsRepository>(
  (_) => CoupleSettingsRepository(),
);

/// The couple's shared settings (background, tint). Watching it subscribes to
/// the couple channel and kicks a one-off refresh; updates arrive from our own
/// writes and from the partner over the WebSocket.
final coupleSettingsProvider = StreamProvider.autoDispose<CoupleSettings>((
  ref,
) {
  final me = ref.watch(currentUserProvider);
  final repo = ref.watch(coupleSettingsRepositoryProvider);
  final coupleId = me?.coupleId;
  if (coupleId != null && coupleId.isNotEmpty) {
    repo.subscribeToCouple(coupleId);
    repo.refresh().ignore();
  }
  return repo.watch();
});

class CoupleSettings {
  final String? backgroundUrl;
  final String? tint;
  const CoupleSettings({this.backgroundUrl, this.tint});

  factory CoupleSettings.fromJson(Map<String, dynamic> j) => CoupleSettings(
    backgroundUrl: j['background_url'] as String?,
    tint: j['tint'] as String?,
  );

  static const empty = CoupleSettings();
}

/// Source of truth for `couple_settings`. Streams updates that come either
/// from our own write or from the partner via the couple Channel.
class CoupleSettingsRepository {
  final _dio = ApiClient.instance.dio;
  final _controller = StreamController<CoupleSettings>.broadcast();
  CoupleSettings _last = CoupleSettings.empty;
  StreamSubscription? _wsSub;

  Stream<CoupleSettings> watch() => _controller.stream;
  CoupleSettings get current => _last;

  Future<CoupleSettings> refresh() async {
    final res = await _dio.get(Endpoints.coupleSettings);
    final raw = res.data['settings'];
    final s = raw == null
        ? CoupleSettings.empty
        : CoupleSettings.fromJson(Map<String, dynamic>.from(raw as Map));
    _emit(s);
    return s;
  }

  String? _subscribedCoupleId;
  PhoenixChannel? _channel;

  Future<void> subscribeToCouple(String coupleId) async {
    if (_subscribedCoupleId == coupleId && _channel != null) return;

    await _wsSub?.cancel();
    if (_channel != null) {
      try {
        await _channel!.leave().future;
      } catch (_) {
        /* ignore */
      }
      _channel = null;
    }

    try {
      final socket = await WsClient.instance.connect();
      final ch = socket.addChannel(topic: 'couple:$coupleId');
      _wsSub = ch.messages.listen((msg) {
        if (msg.event.value == 'settings_updated' && msg.payload != null) {
          _emit(
            CoupleSettings.fromJson(Map<String, dynamic>.from(msg.payload!)),
          );
        }
      });
      await ch.join().future;
      _channel = ch;
      _subscribedCoupleId = coupleId;
    } catch (_) {
      // Offline / not authorized — polling via refresh() still works.
    }
  }

  Future<CoupleSettings> setBackgroundFromFile(File source) async {
    final compressed = await MediaCompressor.compressImage(source);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        compressed.path,
        filename: compressed.uri.pathSegments.last,
      ),
    });
    final up = await _dio.post(Endpoints.mediaUpload, data: form);
    final url = up.data['url'] as String?;
    if (url == null) throw StateError('media upload returned no url');
    final res = await _dio.put(
      Endpoints.coupleSettings,
      data: {'background_url': url},
    );
    final s = CoupleSettings.fromJson(
      Map<String, dynamic>.from(res.data['settings'] as Map),
    );
    _emit(s);
    return s;
  }

  void _emit(CoupleSettings s) {
    _last = s;
    _controller.add(s);
  }
}
