import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user.dart';
import '../local/isar_service.dart';
import '../local/user_cache.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';
import '../remote/token_storage.dart';
import '../remote/ws_client.dart';
import '../sync/media_compressor.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (_) => AuthRepository(),
);
final currentUserProvider = StateProvider<User?>((_) => null);
final partnerUserProvider = StateProvider<User?>((_) => null);

class AuthResult {
  final User me;
  final User? partner;
  const AuthResult({required this.me, this.partner});
}

class AuthRepository {
  final _dio = ApiClient.instance.dio;

  Future<User> register(String email, String password) async {
    final res = await _dio.post(
      Endpoints.register,
      data: {'email': email, 'password': password},
    );
    await TokenStorage.write(res.data['token']);
    return User.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
  }

  Future<User> login(String email, String password) async {
    final res = await _dio.post(
      Endpoints.login,
      data: {'email': email, 'password': password},
    );
    await TokenStorage.write(res.data['token']);
    return User.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
  }

  Future<AuthResult?> me() async {
    final token = await TokenStorage.read();
    if (token == null) return null;
    final res = await _dio.get(Endpoints.me);
    final rawUser = Map<String, dynamic>.from(res.data['user'] as Map);
    final rawPartner = res.data['partner'] == null
        ? null
        : Map<String, dynamic>.from(res.data['partner'] as Map);
    // Refresh the offline-session snapshot on every successful round-trip.
    unawaited(UserCache.write(rawUser, rawPartner));
    final user = User.fromJson(rawUser);
    final partner = rawPartner == null ? null : User.fromJson(rawPartner);
    return AuthResult(me: user, partner: partner);
  }

  Future<User> linkCouple(String code) async {
    final res = await _dio.post(Endpoints.linkCouple, data: {'code': code});
    return User.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
  }

  /// Update display_name (and optionally other profile fields) on the
  /// current user doc.
  Future<User> updateProfile({String? displayName}) async {
    final res = await _dio.put(
      '/api/auth/profile',
      data: {if (displayName != null) 'display_name': displayName},
    );
    return User.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
  }

  /// Uploads a (compressed) avatar and writes the URL on the user doc.
  Future<User> uploadAvatar(File source) async {
    final compressed = await MediaCompressor.compressImage(source);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        compressed.path,
        filename: compressed.uri.pathSegments.last,
      ),
    });
    final up = await _dio.post(Endpoints.mediaUpload, data: form);
    final url = up.data['url'] as String?;
    if (url == null) {
      throw StateError('media upload returned no url');
    }
    final res = await _dio.put('/api/auth/avatar', data: {'avatar_url': url});
    return User.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
  }

  Future<void> logout() async {
    await TokenStorage.clear();
    await UserCache.clear();
    // Drop every cached row so the next account that signs in on this
    // device starts clean.
    try {
      await IsarService.instance.wipe();
    } catch (_) {
      /* ignore if isar not open */
    }
    await WsClient.instance.dispose();
  }
}
