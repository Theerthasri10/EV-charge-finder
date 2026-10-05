// lib/services/geocoding_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceSuggestion {
  final String displayName;
  final LatLng location;

  PlaceSuggestion({required this.displayName, required this.location});
}

class GeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';
  static const String _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';
  static const _headers = {'User-Agent': 'EvChargeFinderApp/1.0 (student project)'};

  Future<LatLng?> geocode(String address) async {
    final url = Uri.parse('$_baseUrl?q=${Uri.encodeComponent(address)}&format=json&limit=1');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return null;

    final List data = jsonDecode(response.body);
    if (data.isEmpty) return null;

    return LatLng(double.parse(data[0]['lat']), double.parse(data[0]['lon']));
  }

  /// Returns up to 5 place suggestions matching the partial query text.
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    if (query.trim().length < 3) return []; // don't search on 1-2 characters, too noisy

    final url = Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}&format=json&limit=5');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return [];

    final List data = jsonDecode(response.body);
    return data.map((item) {
      return PlaceSuggestion(
        displayName: item['display_name'],
        location: LatLng(double.parse(item['lat']), double.parse(item['lon'])),
      );
    }).toList();
  }

  /// Converts coordinates back into a readable address string.
  Future<String?> reverseGeocode(LatLng location) async {
    final url = Uri.parse(
      '$_reverseUrl?lat=${location.latitude}&lon=${location.longitude}&format=json',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    return data['display_name'];
  }
}