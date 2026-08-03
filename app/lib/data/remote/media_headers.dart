import 'token_storage.dart';

/// Credentials for fetching a file from `/media`.
///
/// The server no longer serves the couple's photos, clips and voice notes to
/// anyone holding a URL, so every remote-media loader has to identify itself.
/// Synchronous by necessity: image and video widgets take their headers when
/// they are built, not later — see [TokenStorage.cached].
///
/// Empty before sign-in, which is correct: there is nothing of theirs to
/// fetch yet.
Map<String, String> mediaHeaders() {
  final token = TokenStorage.cached;
  return token == null ? const {} : {'Authorization': 'Bearer $token'};
}
