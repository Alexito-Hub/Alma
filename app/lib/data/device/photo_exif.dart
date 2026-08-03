import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What a photo remembers about itself: where and when it was taken.
class PhotoExif {
  const PhotoExif({this.latitude, this.longitude, this.takenAt});

  final double? latitude;
  final double? longitude;
  final DateTime? takenAt;

  bool get hasLocation => latitude != null && longitude != null;
  bool get isEmpty => !hasLocation && takenAt == null;
}

/// Read the GPS fix and capture time the camera wrote into [file].
///
/// Only the EXIF block is parsed — `decodeJpgExif` walks the JPEG markers
/// instead of decoding pixels — and only the head of the file is read, since
/// EXIF lives in an APP1 segment right after the start marker and a segment
/// can't exceed 64 KB. A 20 MP photo therefore costs a few hundred KB here,
/// not its full size.
///
/// Returns null when the file isn't a JPEG, carries no EXIF, or can't be read.
/// This only ever *adds* information, so every failure is silent.
Future<PhotoExif?> readPhotoExif(File file) async {
  try {
    final head = await _readHead(file, 512 * 1024);
    if (head == null) return null;

    final exif = img.decodeJpgExif(head);
    if (exif == null || exif.isEmpty) return null;

    final gps = exif.gpsIfd;
    final lat = _degrees(gps.data[0x0002], gps.gpsLatitudeRef, 'S');
    final lon = _degrees(gps.data[0x0004], gps.gpsLongitudeRef, 'W');

    final result = PhotoExif(
      latitude: lat,
      longitude: lon,
      takenAt: _takenAt(exif),
    );
    return result.isEmpty ? null : result;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _readHead(File file, int maxBytes) async {
  final handle = await file.open();
  try {
    final length = await file.length();
    return await handle.read(length < maxBytes ? length : maxBytes);
  } finally {
    await handle.close();
  }
}

/// Turn an EXIF coordinate into a signed decimal degree.
///
/// EXIF writes a position as three rationals — degrees, minutes, seconds —
/// and keeps the hemisphere in a separate tag ('N'/'S', 'E'/'W'). Reading the
/// value straight through `IfdValue.toDouble()` hands back only the degrees,
/// which looks plausible and is wrong by up to a degree: that is the mistake
/// this function exists to prevent, and why it's tested on its own.
///
/// [negativeRef] is the hemisphere letter that flips the sign — 'S' for
/// latitude, 'W' for longitude. Returns null for values that can't be a
/// coordinate.
double? exifCoordinate({
  required double degrees,
  required double minutes,
  required double seconds,
  required String negativeRef,
  String? ref,
}) {
  final decimal = degrees + minutes / 60 + seconds / 3600;
  if (decimal.isNaN || decimal.isInfinite || decimal > 180) return null;
  final south = ref?.trim().toUpperCase().startsWith(negativeRef) ?? false;
  return south ? -decimal : decimal;
}

double? _degrees(img.IfdValue? value, String? ref, String negative) {
  if (value == null || value.length < 3) return null;
  // Named so all three positions read the same way; the whole hazard here is
  // taking index 0 and calling it the coordinate.
  double at(int i) => value.toDouble(i);
  return exifCoordinate(
    degrees: at(0),
    minutes: at(1),
    seconds: at(2),
    ref: ref,
    negativeRef: negative,
  );
}

/// `DateTimeOriginal` is written as "YYYY:MM:DD HH:MM:SS" — colons in the date
/// part, which `DateTime.parse` won't take.
DateTime? _takenAt(img.ExifData exif) {
  final raw =
      exif.imageIfd.data[0x9003]?.toString() ??
      exif.imageIfd.data[0x0132]?.toString();
  if (raw == null || raw.length < 19) return null;
  final normalised =
      '${raw.substring(0, 4)}-${raw.substring(5, 7)}-${raw.substring(8, 10)}'
      'T${raw.substring(11, 19)}';
  return DateTime.tryParse(normalised);
}
