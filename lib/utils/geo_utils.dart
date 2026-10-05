import 'dart:math';
import 'package:latlong2/latlong.dart';

class GeoUtils {
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);

  static double distanceToRouteKm(double lat, double lng, List<LatLng> route) {
    double minDist = double.infinity;
    for (final point in route) {
      final d = distanceKm(lat, lng, point.latitude, point.longitude);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }
}