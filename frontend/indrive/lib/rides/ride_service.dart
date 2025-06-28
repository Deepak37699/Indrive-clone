import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:indrive/auth/auth_service.dart'; // Import AuthService to get token
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import LatLng

class RideService {
  final String _baseUrl =
      'http://10.0.2.2:8000/api/rides/'; // Use 10.0.2.2 for Android emulator to access host machine
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> requestRide({
    required LatLng pickupLocation,
    required LatLng destinationLocation,
  }) async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/request/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'pickup_latitude': pickupLocation.latitude,
        'pickup_longitude': pickupLocation.longitude,
        'destination_latitude': destinationLocation.latitude,
        'destination_longitude': destinationLocation.longitude,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to request ride: ${response.body}');
    }
  }

  Future<List<dynamic>> getRiderRides() async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/rider/list/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch rider rides: ${response.body}');
    }
  }

  Future<List<dynamic>> getDriverRides() async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/driver/list/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch driver rides: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateRideStatus(
    int rideId,
    String status,
  ) async {
    final accessToken = await _authService.getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.patch(
      Uri.parse('$_baseUrl/$rideId/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update ride status: ${response.body}');
    }
  }
}
