import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/couple_request.dart';
import '../remote/api_client.dart';
import '../remote/endpoints.dart';

final coupleRepositoryProvider = Provider<CoupleRepository>(
  (_) => CoupleRepository(),
);

class CoupleInbox {
  final String myCode;
  final List<CoupleRequest> requests;
  const CoupleInbox({required this.myCode, required this.requests});
}

class CoupleRepository {
  final _dio = ApiClient.instance.dio;

  Future<CoupleRequest> sendRequest({
    required String partnerCode,
    DateTime? startedAt,
    String? message,
  }) async {
    final res = await _dio.post(
      Endpoints.coupleRequests,
      data: {
        'code': partnerCode.trim().toLowerCase(),
        if (startedAt != null)
          'started_at': startedAt.toUtc().toIso8601String(),
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    return CoupleRequest.fromJson(
      Map<String, dynamic>.from(res.data['request'] as Map),
    );
  }

  Future<CoupleInbox> inbox() async {
    final res = await _dio.get(Endpoints.coupleRequests);
    final data = res.data as Map;
    final list = (data['requests'] as List? ?? const [])
        .map((j) => CoupleRequest.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    return CoupleInbox(
      myCode: (data['me_code'] as String?) ?? '',
      requests: list,
    );
  }

  Future<CoupleInbox> outbox() async {
    final res = await _dio.get(
      Endpoints.coupleRequests,
      queryParameters: {'type': 'sent'},
    );
    final data = res.data as Map;
    final list = (data['requests'] as List? ?? const [])
        .map((j) => CoupleRequest.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    return CoupleInbox(
      myCode: (data['me_code'] as String?) ?? '',
      requests: list,
    );
  }

  Future<void> accept(String requestId) =>
      _dio.post(Endpoints.coupleRequestAccept(requestId));

  Future<void> reject(String requestId) =>
      _dio.post(Endpoints.coupleRequestReject(requestId));

  Future<void> cancel(String requestId) =>
      _dio.post(Endpoints.coupleRequestCancel(requestId));
}
