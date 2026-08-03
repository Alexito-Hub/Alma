import 'dart:io';
import 'dart:typed_data';

import 'package:alma/data/device/photo_exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('exifCoordinate', () {
    // The whole point of this function: EXIF keeps degrees, minutes and
    // seconds apart, and the obvious `toDouble()` returns only the first of
    // the three. Reading Miraflores as -12 instead of -12.12 is 13 km off.
    test('combines degrees, minutes and seconds', () {
      expect(
        exifCoordinate(
          degrees: 12,
          minutes: 7,
          seconds: 12,
          ref: 'S',
          negativeRef: 'S',
        ),
        closeTo(-12.12, 0.0001),
      );
    });

    test('south and west are negative', () {
      expect(
        exifCoordinate(
          degrees: 77,
          minutes: 1,
          seconds: 48,
          ref: 'W',
          negativeRef: 'W',
        ),
        closeTo(-77.03, 0.0001),
      );
    });

    test('north and east stay positive', () {
      expect(
        exifCoordinate(
          degrees: 48,
          minutes: 51,
          seconds: 30,
          ref: 'N',
          negativeRef: 'S',
        ),
        closeTo(48.8583, 0.0001),
      );
      expect(
        exifCoordinate(
          degrees: 2,
          minutes: 17,
          seconds: 40,
          ref: 'E',
          negativeRef: 'W',
        ),
        closeTo(2.2944, 0.0001),
      );
    });

    test('a missing hemisphere is treated as positive, not as an error', () {
      expect(
        exifCoordinate(degrees: 10, minutes: 30, seconds: 0, negativeRef: 'S'),
        closeTo(10.5, 0.0001),
      );
    });

    test('the reference is matched regardless of case or padding', () {
      expect(
        exifCoordinate(
          degrees: 10,
          minutes: 0,
          seconds: 0,
          ref: ' s ',
          negativeRef: 'S',
        ),
        closeTo(-10, 0.0001),
      );
    });

    test('rejects values that cannot be a coordinate', () {
      expect(
        exifCoordinate(degrees: 999, minutes: 0, seconds: 0, negativeRef: 'S'),
        isNull,
      );
      expect(
        exifCoordinate(
          degrees: double.nan,
          minutes: 0,
          seconds: 0,
          negativeRef: 'S',
        ),
        isNull,
      );
    });
  });

  group('readPhotoExif', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('alma_exif_test');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<File> write(String name, List<int> bytes) async {
      final f = File('${tmp.path}/$name');
      await f.writeAsBytes(bytes);
      return f;
    }

    // Every failure here has to be silent: this only ever *adds* a suggestion
    // to the composer, so a photo it can't read must not break picking one.
    test('a photo with no EXIF yields null', () async {
      final file = await write(
        'bare.jpg',
        img.encodeJpg(img.Image(width: 4, height: 4)),
      );
      expect(await readPhotoExif(file), isNull);
    });

    test('a file that is not an image yields null', () async {
      final file = await write(
        'notes.txt',
        Uint8List.fromList('esto no es una foto'.codeUnits),
      );
      expect(await readPhotoExif(file), isNull);
    });

    test('an empty file yields null', () async {
      final file = await write('empty.jpg', const <int>[]);
      expect(await readPhotoExif(file), isNull);
    });

    test('a missing file yields null', () async {
      expect(await readPhotoExif(File('${tmp.path}/no-existe.jpg')), isNull);
    });
  });
}
