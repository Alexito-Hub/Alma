/// True when [error] (usually `e.toString()`) looks like a connectivity /
/// transport failure rather than a real server rejection — so the UI can show
/// a "no connection" message instead of a generic one.
///
/// Covers the usual suspects: Dio connection/timeout errors, dart:io
/// SocketExceptions, DNS failures, and Android's cleartext-blocked error
/// (`CLEARTEXT communication ... not permitted`), which is a common gotcha
/// when pointing a release/profile build at an http:// dev backend.
bool looksLikeNetworkError(String error) {
  final s = error.toLowerCase();
  const needles = [
    'socketexception',
    'connection',
    'cleartext',
    'timeout',
    'failed host lookup',
    'network is unreachable',
    'connection refused',
    'connection closed',
    'handshake',
    'econnrefused',
  ];
  return needles.any(s.contains);
}
