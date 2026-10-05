import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../utils/polyline_decoder.dart';

/// Result of a route lookup: the polyline points plus the real
/// distance/duration OSRM returns alongside the geometry.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class DirectionsService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  Future<RouteResult?> getRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      '$_baseUrl/${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=polyline',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data['code'] != 'Ok') return null;

    final route = data['routes'][0];
    final points = PolylineDecoder.decode(route['geometry']);

    // OSRM returns distance in meters and duration in seconds.
    final distanceKm = (route['distance'] as num) / 1000.0;
    final durationMinutes = ((route['duration'] as num) / 60).round();

    return RouteResult(
      points: points,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
    );
  }
}