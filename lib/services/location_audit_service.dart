import 'package:geolocator/geolocator.dart';

class LocationAuditService {
  static const double supportedRadiusMeters = 250;
  static Map<String, dynamic>? summarizeTransactionLocation(
    Map<String, dynamic>? metadata,
    List<Map<String, dynamic>> supportedLocations,
  ) {
    if (metadata == null) {
      return null;
    }
    final location = metadata['location'];
    if (location is! Map) {
      return null;
    }
    final latitude = _toDouble(location['latitude']);
    final longitude = _toDouble(location['longitude']);
    if (latitude == null || longitude == null) {
      return null;
    }
    Map<String, dynamic>? nearestLocation;
    double? nearestDistance;
    for (final branch in supportedLocations) {
      final branchLatitude = _toDouble(branch['latitude']);
      final branchLongitude = _toDouble(branch['longitude']);
      if (branchLatitude == null || branchLongitude == null) {
        continue;
      }
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        branchLatitude,
        branchLongitude,
      );
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearestLocation = branch;
      }
    }
    return {
      'location': Map<String, dynamic>.from(location),
      'nearestBranch': nearestLocation,
      'nearestDistanceMeters': nearestDistance,
      'isNearSupportedBranch':
          nearestDistance != null && nearestDistance <= supportedRadiusMeters,
    };
  }

  static String distanceLabel(double meters) {
    if (meters < 1000) {
      return '${meters.round()} متر';
    }
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}
