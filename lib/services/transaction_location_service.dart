import 'package:geolocator/geolocator.dart';

class TransactionLocationService {
  static Future<Position?> currentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> captureCurrentLocation() async {
    try {
      final position = await currentPosition();
      if (position == null) {
        return null;
      }
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'capturedAt': DateTime.now().toIso8601String(),
        'source': 'device_gps',
      };
    } catch (_) {
      return null;
    }
  }
}
