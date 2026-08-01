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
  static String post(String id) => '/api/posts/$id';
  static String postComments(String postId) => '/api/posts/$postId/comments';

  static const notes = '/api/notes';
  static String note(String id) => '/api/notes/$id';
  static const specialDates = '/api/special_dates';
  static String specialDate(String id) => '/api/special_dates/$id';
  static const status = '/api/status';

  static const mediaUpload = '/api/media';
  static const coupleSettings = '/api/couple/settings';
  static const couplePin = '/api/couple/pin';
  static const couplePinVerify = '/api/couple/pin/verify';
}
