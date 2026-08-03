import 'package:dio/dio.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Outcome of checking a PIN. Wrong and "you've tried too many times" are
/// different answers and deserve different words on screen — the server now
/// freezes the gate after a handful of failures, and a bare `false` there
/// would have read as "PIN incorrecto" forever.
class PinCheck {
  const PinCheck._(this.ok, this.retryAfter);

  const PinCheck.ok() : this._(true, null);
  const PinCheck.wrong() : this._(false, null);

  /// Locked out; [retryAfter] is roughly how many seconds are left.
  const PinCheck.throttled(int retryAfter) : this._(false, retryAfter);

  final bool ok;
  final int? retryAfter;

  bool get throttled => retryAfter != null;
}

/// Couple-shared PIN gate for the private diary. The PIN lives (hashed) on the
/// server so both partners use the same one; unlocking lasts for the current
/// app session only.
class PinGate {
  PinGate._();
  static final PinGate instance = PinGate._();

  final _dio = ApiClient.instance.dio;

  /// Session-only unlock flag — relocks when the app restarts.
  bool unlocked = false;

  Future<bool> isSet() async {
    final res = await _dio.get(Endpoints.couplePin);
    return res.data['set'] == true;
  }

  Future<void> setPin(String pin) async {
    await _dio.put(Endpoints.couplePin, data: {'pin': pin});
  }

  Future<PinCheck> verify(String pin) async {
    try {
      final res = await _dio.post(
        Endpoints.couplePinVerify,
        data: {'pin': pin},
      );
      return res.data['ok'] == true
          ? const PinCheck.ok()
          : const PinCheck.wrong();
    } on DioException catch (e) {
      final res = e.response;
      if (res?.statusCode == 429) {
        final retry = res?.data is Map ? res!.data['retry_after'] : null;
        return PinCheck.throttled(retry is int ? retry : 300);
      }
      rethrow; // Offline or server down — the caller says so.
    }
  }
}
