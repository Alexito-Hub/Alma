import 'package:alma/data/repositories/couple_settings_repository.dart';
import 'package:alma/domain/entities/status_message.dart';
import 'package:alma/domain/entities/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('User', () {
    test('fromJson maps snake_case fields and accepts _id or id', () {
      final a = User.fromJson({
        '_id': 'u1',
        'email': 'ada@alma.app',
        'display_name': 'Ada',
        'couple_id': 'c1',
        'couple_started_at': '2024-01-02T03:04:05.000Z',
      });
      expect(a.id, 'u1');
      expect(a.email, 'ada@alma.app');
      expect(a.displayName, 'Ada');
      expect(a.coupleId, 'c1');
      expect(a.coupleStartedAt, DateTime.utc(2024, 1, 2, 3, 4, 5));

      final b = User.fromJson({'id': 'u2', 'email': 'grace@alma.app'});
      expect(b.id, 'u2');
      expect(b.displayName, isNull);
      expect(b.coupleStartedAt, isNull);
    });

    test('prettyName prefers displayName, falls back to email local-part', () {
      const withName = User(id: '1', email: 'x@y.z', displayName: 'Lin');
      expect(withName.prettyName, 'Lin');

      const noName = User(id: '2', email: 'hello@world.com');
      expect(noName.prettyName, 'hello');

      const blankName = User(id: '3', email: 'blank@x.io', displayName: '   ');
      expect(blankName.prettyName, 'blank');
    });

    test('copyWith overrides only the given fields', () {
      const base = User(id: '1', email: 'x@y.z', displayName: 'A');
      final next = base.copyWith(displayName: 'B');
      expect(next.id, '1');
      expect(next.email, 'x@y.z');
      expect(next.displayName, 'B');
    });
  });

  group('StatusMessage', () {
    test('fromJson parses author, text and timestamp', () {
      final s = StatusMessage.fromJson({
        'author_id': 'u1',
        'text': 'te extraño',
        'updated_at': '2025-06-01T12:00:00.000Z',
      });
      expect(s.authorId, 'u1');
      expect(s.text, 'te extraño');
      expect(s.updatedAt, DateTime.utc(2025, 6, 1, 12));
    });

    test('fromJson defaults missing text to empty string', () {
      final s = StatusMessage.fromJson({
        'author_id': 'u1',
        'updated_at': '2025-06-01T12:00:00.000Z',
      });
      expect(s.text, '');
    });
  });

  group('CoupleSettings', () {
    test('fromJson maps background_url and tint', () {
      final s = CoupleSettings.fromJson({
        'background_url': '/media/bg.jpg',
        'tint': 'pink',
      });
      expect(s.backgroundUrl, '/media/bg.jpg');
      expect(s.tint, 'pink');
    });

    test('empty has null fields', () {
      expect(CoupleSettings.empty.backgroundUrl, isNull);
      expect(CoupleSettings.empty.tint, isNull);
    });
  });
}
