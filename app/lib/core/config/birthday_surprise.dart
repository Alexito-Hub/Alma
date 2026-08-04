/// Who may see the birthday surprise, and when.
enum SurpriseAccess {
  /// Nothing exists. No button, no hint, no trace anywhere in the UI.
  hidden,

  /// The author: may start it at will, at any time, to test it.
  preview,

  /// The recipient, at or past the moment, never played. Launch it.
  detonate,

  /// The recipient, already played. Reachable again on purpose, but never
  /// launched on its own a second time.
  replay,
}

/// The lock in front of May's birthday surprise.
///
/// Written as pure logic — no Flutter, no storage, no clock of its own — so
/// every branch can be tested rather than trusted. The one thing this must
/// never do is show her something unfinished, so the rules are ordered from
/// "prove who you are" downwards and anything unrecognised falls through to
/// [SurpriseAccess.hidden].
class BirthdaySurprise {
  BirthdaySurprise._();

  /// Identity is matched on **email**, which is already in the cached session
  /// and therefore works with no server and no network. That matters: the
  /// trigger has to fire at midnight whether or not the box at home is up.
  ///
  /// [ownerId] / [recipientId] are optional belt-and-braces for when the
  /// Mongo `_id`s are pinned; either a matching id or a matching email is
  /// enough.
  static const ownerEmail = 'alessandrovillogas@outlook.es';
  static const recipientEmail = 'cerronvillarmaricielo@gmail.com';
  static const String? ownerId = null;
  static const String? recipientId = null;

  /// **The safety catch.** While this is false the recipient can never reach
  /// the surprise, whatever the date says — only the owner's preview works.
  /// Flip it to true once the experience is finished and tested, and not one
  /// minute before: an unfinished sequence detonating on her birthday is the
  /// single worst outcome available here.
  static const bool armedForRecipient = false;

  /// Local midnight opening 14 August 2026 — the instant her birthday starts
  /// on her own phone. Built with local fields on purpose: the device's own
  /// midnight is the one she'll be living in, and it needs no network.
  static DateTime momentFor() => DateTime(2026, 8, 14);

  /// Resolve what this session may do.
  ///
  /// [played] comes from storage, [now] from the caller, so the caller is the
  /// only thing that needs a clock and this stays deterministic.
  static SurpriseAccess accessFor({
    required String? email,
    String? userId,
    required DateTime now,
    required bool played,
    bool armed = armedForRecipient,
  }) {
    // No identity means no decision. Never guess in either direction.
    if (!_identified(email, userId)) return SurpriseAccess.hidden;

    // The owner is checked first, so a misconfiguration that made both
    // constants equal would grant preview rather than detonate.
    if (_isOwner(email, userId)) return SurpriseAccess.preview;

    if (!_isRecipient(email, userId)) return SurpriseAccess.hidden;

    if (!armed) return SurpriseAccess.hidden;
    if (now.isBefore(momentFor())) return SurpriseAccess.hidden;

    // Past the moment. If her phone was off at midnight this still fires the
    // first time she opens the app — late is far better than never.
    return played ? SurpriseAccess.replay : SurpriseAccess.detonate;
  }

  static bool _identified(String? email, String? userId) =>
      _clean(email) != null || _clean(userId) != null;

  static bool _isOwner(String? email, String? userId) =>
      _same(email, ownerEmail) || _same(userId, ownerId);

  static bool _isRecipient(String? email, String? userId) =>
      _same(email, recipientEmail) || _same(userId, recipientId);

  static bool _same(String? value, String? expected) {
    final a = _clean(value);
    final b = _clean(expected);
    return a != null && b != null && a == b;
  }

  /// Trimmed and lower-cased; empty and whitespace-only count as absent, so a
  /// blank field can never match a blank constant.
  static String? _clean(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }
}
