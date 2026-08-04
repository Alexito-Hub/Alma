import 'package:alma/core/config/birthday_surprise.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final before = DateTime(2026, 8, 13, 23, 59, 59);
  final midnight = DateTime(2026, 8, 14);
  final after = DateTime(2026, 8, 14, 9, 30);
  final muchLater = DateTime(2026, 8, 20);

  SurpriseAccess access({
    String? email,
    String? userId,
    required DateTime now,
    bool played = false,
    bool armed = true,
  }) => BirthdaySurprise.accessFor(
    email: email,
    userId: userId,
    now: now,
    played: played,
    armed: armed,
  );

  group('the owner', () {
    test('always gets preview, before the date', () {
      expect(
        access(email: BirthdaySurprise.ownerEmail, now: before),
        SurpriseAccess.preview,
      );
    });

    test('gets preview even while the recipient is disarmed', () {
      expect(
        access(email: BirthdaySurprise.ownerEmail, now: before, armed: false),
        SurpriseAccess.preview,
      );
    });

    test('gets preview again after having played it', () {
      expect(
        access(
          email: BirthdaySurprise.ownerEmail,
          now: muchLater,
          played: true,
        ),
        SurpriseAccess.preview,
      );
    });

    test('is recognised regardless of case or padding', () {
      expect(
        access(email: '  ALESSANDROVILLOGAS@OUTLOOK.ES ', now: before),
        SurpriseAccess.preview,
      );
    });
  });

  group('the recipient', () {
    test('sees nothing at all before the moment', () {
      expect(
        access(email: BirthdaySurprise.recipientEmail, now: before),
        SurpriseAccess.hidden,
      );
    });

    test('detonates exactly at midnight', () {
      expect(
        access(email: BirthdaySurprise.recipientEmail, now: midnight),
        SurpriseAccess.detonate,
      );
    });

    test('one second earlier is still nothing', () {
      expect(
        access(
          email: BirthdaySurprise.recipientEmail,
          now: midnight.subtract(const Duration(seconds: 1)),
        ),
        SurpriseAccess.hidden,
      );
    });

    // Her phone may well be asleep at 00:00. Missing the moment must not mean
    // missing the gift.
    test('still detonates hours later if she opened the app late', () {
      expect(
        access(email: BirthdaySurprise.recipientEmail, now: after),
        SurpriseAccess.detonate,
      );
      expect(
        access(email: BirthdaySurprise.recipientEmail, now: muchLater),
        SurpriseAccess.detonate,
      );
    });

    test('never launches twice on its own', () {
      expect(
        access(
          email: BirthdaySurprise.recipientEmail,
          now: after,
          played: true,
        ),
        SurpriseAccess.replay,
      );
    });

    // The safety catch. This is the test that matters most: while the
    // experience is unfinished, the date must not be able to reach her.
    test('is locked out entirely while disarmed, even past midnight', () {
      expect(
        access(
          email: BirthdaySurprise.recipientEmail,
          now: after,
          armed: false,
        ),
        SurpriseAccess.hidden,
      );
      expect(
        access(
          email: BirthdaySurprise.recipientEmail,
          now: muchLater,
          armed: false,
        ),
        SurpriseAccess.hidden,
      );
    });

    test('ships disarmed', () {
      // Guards against arming it by accident in an unrelated commit; delete
      // this expectation deliberately, on the day it's really ready.
      expect(BirthdaySurprise.armedForRecipient, isFalse);
    });
  });

  group('anyone and anything else', () {
    test('a stranger sees nothing, whatever the date', () {
      for (final now in [before, midnight, after]) {
        expect(
          access(email: 'desconocido@example.com', now: now),
          SurpriseAccess.hidden,
        );
      }
    });

    test('no session sees nothing', () {
      expect(access(now: after), SurpriseAccess.hidden);
    });

    test('blank identity cannot match a blank constant', () {
      expect(access(email: '', now: after), SurpriseAccess.hidden);
      expect(access(email: '   ', now: after), SurpriseAccess.hidden);
      expect(access(userId: '  ', now: after), SurpriseAccess.hidden);
    });
  });

  test('the moment is local midnight opening 14 August', () {
    final m = BirthdaySurprise.momentFor();
    expect(m.year, 2026);
    expect(m.month, 8);
    expect(m.day, 14);
    expect(m.hour, 0);
    expect(m.minute, 0);
    expect(m.second, 0);
    expect(m.isUtc, isFalse);
  });
}
