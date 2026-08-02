import 'package:flutter/material.dart';
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

  /// True when a stored media path is a video rather than a photo.
  static bool isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.m4v') ||
        p.endsWith('.3gp') ||
        p.endsWith('.mkv') ||
        p.endsWith('.avi') ||
        p.endsWith('.webm');
  }

  /// Resolve a typed place ("Parque Kennedy, Lima") into coordinates, so a
  /// moment can be pinned somewhere other than where the phone is standing.
  /// Returns null when the address can't be found.
  static Future<GeoTag?> geocodePlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    try {
      final results = await locationFromAddress(q);
      if (results.isEmpty) return null;
      final loc = results.first;
      return GeoTag(latitude: loc.latitude, longitude: loc.longitude, label: q);
    } catch (_) {
      return null;
    }
  }

  /// Opens the crop UI for [path]. [square] locks a 1:1 ratio (used for
  /// avatars). Returns the cropped file path, or the original if cancelled.
  static Future<String> cropImage(String path, {bool square = false}) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      aspectRatio: square ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar',
          // Brand the native uCrop chrome (values mirror Neo.pink / white).
          toolbarColor: const Color(0xFFFF90A8),
          toolbarWidgetColor: const Color(0xFFFFFFFF),
          activeControlsWidgetColor: const Color(0xFFFF90A8),
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
          accuracy: LocationAccuracy.high,
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
          // Prefer the most specific parts (street/neighbourhood) so the label
          // is an actual place, not just the region.
          final parts = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => s != null && s.trim().isNotEmpty).toList();
          label = parts.isEmpty ? p.name : parts.take(3).join(', ');
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
