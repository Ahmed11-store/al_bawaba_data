/// GPS Location Service (on-device, offline)
/// ---------------------------------------------------------------
/// Thin wrapper around `geolocator` used only when "الموقع" (GPS
/// tracking mode) is toggled on. Coordinates come straight from
/// device hardware (GPS/GNSS chip) — no network geocoding is ever
/// performed, so this stays fully offline; reverse-geocoding a
/// human-readable address is intentionally NOT done here (that
/// would require network access). The raw lat/lng is stored and
/// handed to Google Maps only when the operator taps the map icon,
/// at which point the OS opens the Maps app itself.
///
/// pubspec.yaml dependency this file assumes:
///   geolocator: ^13.0.1
///
/// Add to AndroidManifest.xml:
///   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
///   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
/// Add to Info.plist:
///   NSLocationWhenInUseUsageDescription
library location_service;

import 'package:geolocator/geolocator.dart';

class LocationCoordinates {
  final double latitude;
  final double longitude;
  const LocationCoordinates({required this.latitude, required this.longitude});
}

class LocationService {
  /// Verifies the location service is on and permission is
  /// granted, requesting it if not. Returns false if the operator
  /// denies permission or device location services are off —
  /// callers should fall back to logging without coordinates
  /// rather than blocking the scan flow.
  Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Fetches a single fix at the moment a plate is recognized (per
  /// the spec: "fetch lat/lng per speech trigger"). Uses `medium`
  /// accuracy as a balance between fix speed and battery — plate
  /// logging doesn't need sub-meter precision.
  Future<LocationCoordinates?> getCurrentLocation() async {
    final ok = await ensurePermission();
    if (!ok) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return LocationCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Timeout / hardware unavailable — treat as "no location for
      // this scan" rather than surfacing an error to the operator
      // mid-inspection.
      return null;
    }
  }
}
