import 'api_client.dart';
import 'endpoints.dart';

/// Couple-shared PIN gate for the private feed. The PIN lives (hashed) on the
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

  Future<bool> verify(String pin) async {
    final res = await _dio.post(Endpoints.couplePinVerify, data: {'pin': pin});
    return res.data['ok'] == true;
  }
}
