import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';

class RouteResult {
  final List<LatLng> points;
  final int durationSeconds;
  final String distanceText;
  const RouteResult({required this.points, required this.durationSeconds, required this.distanceText});
}

class RouteService {
  Future<RouteResult?> getDrivingRoute({required LatLng origin, required LatLng destination}) async {
    final key = AppConfig.googleMapsApiKey;
    if (key.isEmpty) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': key,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final leg = (route['legs'] as List<dynamic>).first as Map<String, dynamic>;
    final duration = (leg['duration'] as Map<String, dynamic>)['value'] as num;
    final distance = (leg['distance'] as Map<String, dynamic>)['text'] as String;
    final encoded = (route['overview_polyline'] as Map<String, dynamic>)['points'] as String;
    return RouteResult(
      points: _decodePolyline(encoded),
      durationSeconds: duration.toInt(),
      distanceText: distance,
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, resultValue = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        resultValue |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (resultValue & 1) != 0 ? ~(resultValue >> 1) : (resultValue >> 1);

      shift = 0;
      resultValue = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        resultValue |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (resultValue & 1) != 0 ? ~(resultValue >> 1) : (resultValue >> 1);

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}
