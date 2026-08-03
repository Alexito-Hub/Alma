import 'package:alma/data/local/isar_service.dart';
import 'package:alma/data/remote/endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Endpoints.commentsFor', () {
    // Regression: the background sync worker used to hardcode the feed route
    // for every comment. A diary comment written offline was stored against a
    // post id, never broadcast on the couple channel and never returned by
    // GET /api/notes/:id/comments — while the client marked it synced. Both
    // the repository and the worker route through this one function now.
    test('a diary comment goes to the note thread', () {
      expect(Endpoints.commentsFor('note', 'abc'), '/api/notes/abc/comments');
    });

    test('a feed comment goes to the post thread', () {
      expect(Endpoints.commentsFor('post', 'abc'), '/api/posts/abc/comments');
    });

    test('an unknown target falls back to the post thread', () {
      expect(Endpoints.commentsFor('', 'abc'), '/api/posts/abc/comments');
    });

    test('agrees with the single-target helpers', () {
      expect(Endpoints.commentsFor('note', 'x'), Endpoints.noteComments('x'));
      expect(Endpoints.commentsFor('post', 'x'), Endpoints.postComments('x'));
    });
  });

  group('IsarService.schemas', () {
    // Regression: DateIdeaLocalSchema was missing, so every `dateIdeaLocals`
    // call threw at runtime and Citas was dead — something the analyzer can't
    // see. Isar names its collections after the class, so this catches the
    // next collection somebody forgets to register.
    test('covers every collection the app stores', () {
      final names = IsarService.schemas.map((s) => s.name).toSet();

      expect(
        names,
        containsAll(<String>{
          'PostLocal',
          'NoteLocal',
          'StatusLocal',
          'CommentLocal',
          'SpecialDateLocal',
          'DateIdeaLocal',
        }),
      );
    });

    test('registers each collection once', () {
      final names = IsarService.schemas.map((s) => s.name).toList();
      expect(names.length, names.toSet().length);
    });
  });
}
