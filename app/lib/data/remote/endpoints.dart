/// Single source of truth for backend routes. Mirrors the Phoenix router.
class Endpoints {
  static const register = '/api/auth/register';
  static const login = '/api/auth/login';
  static const me = '/api/auth/me';
  static const linkCouple = '/api/couple/link';
  static const coupleRequests = '/api/couple/requests';
  static String coupleRequestAccept(String id) =>
      '/api/couple/requests/$id/accept';
  static String coupleRequestReject(String id) =>
      '/api/couple/requests/$id/reject';
  static String coupleRequestCancel(String id) =>
      '/api/couple/requests/$id/cancel';

  static const syncBatch = '/api/sync/batch';

  static const posts = '/api/posts';
  static String postComments(String postId) => '/api/posts/$postId/comments';

  static const notes = '/api/notes';
  static const status = '/api/status';

  static const mediaUpload = '/api/media';
  static const coupleSettings = '/api/couple/settings';
}
