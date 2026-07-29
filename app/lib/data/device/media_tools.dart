import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_cropper/image_cropper.dart';

/// A captured geotag: coordinates plus a best-effort human place label.
class GeoTag {
  const GeoTag({required this.latitude, required this.longitude, this.label});
  final double latitude;
  final double longitude;
  final String? label;
}

/// Thin wrappers over the native media/device plugins so the UI stays clean.
class MediaTools {
  MediaTools._();

  /// Opens the crop UI for [path]. [square] locks a 1:1 ratio (used for
  /// avatars). Returns the cropped file path, or the original if cancelled.
  static Future<String> cropImage(String path, {bool square = false}) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      aspectRatio: square ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar',
          lockAspectRatio: square,
          hideBottomControls: square,
        ),
        IOSUiSettings(title: 'Recortar', aspectRatioLockEnabled: square),
      ],
    );
    return cropped?.path ?? path;
  }

  /// Best-effort current location + a human place label. Returns null if
  /// permission is denied or the location can't be read.
  static Future<GeoTag?> captureLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      String? label;
      try {
        final places = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (places.isNotEmpty) {
          final p = places.first;
          final parts = [
            p.locality,
            p.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).toList();
          label = parts.isNotEmpty ? parts.join(', ') : p.name;
        }
      } catch (_) {
        // Reverse-geocoding is optional; coordinates are enough.
      }
      return GeoTag(
        latitude: pos.latitude,
        longitude: pos.longitude,
        label: (label == null || label.isEmpty) ? null : label,
      );
    } catch (_) {
      return null;
    }
  }
}
