import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ev_station.dart';

class EvStationService {
  // Change this based on how you're testing:
  // Android Emulator: 'http://10.0.2.2:3000'
  // Physical device (same WiFi): 'http://YOUR_COMPUTER_IP:3000'
  // iOS Simulator: 'http://localhost:3000'
  static const String baseUrl = 'http://192.168.1.2:3000';

  Future<List<EvStation>> getAllStations() async {
    final response = await http.get(Uri.parse('$baseUrl/stations'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => EvStation.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load stations (status ${response.statusCode})');
    }
  }
}