import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Voice notes for the diary, WhatsApp-style: hold to record, release to keep.
///
/// Files land in the cache directory as AAC/m4a — small enough to sync without
/// a second compression pass, and playable by `just_audio` on both ends.
class VoiceRecorder {
  VoiceRecorder();

  final _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begin recording. Returns the destination path, or null when the mic
  /// permission was denied.
  Future<String?> start() async {
    if (!await _recorder.hasPermission()) return null;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/alma_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(bitRate: 96000), path: path);
    return path;
  }

  /// Stop and keep the take. Returns the recorded file path.
  Future<String?> stop() async {
    try {
      return await _recorder.stop();
    } catch (_) {
      return null;
    }
  }

  /// Stop and throw the take away (slid to cancel).
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      /* nothing to discard */
    }
  }

  Future<void> dispose() => _recorder.dispose();
}
