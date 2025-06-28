import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:indrive/auth/auth_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart'; // Import WebSocketChannel

class RideService {
  final String _baseUrl = 'http://10.0.2.2:8000/api/rides/';
  final AuthService _authService = AuthService();
  WebSocketChannel? _channel;

  // Helper to get access token
  Future<String?> _getAccessToken() async {
    return await _authService.getAccessToken();
  }

  // Helper for common headers
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAccessToken();
    if (token == null) {
      throw Exception('Access token not found. User not authenticated.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> requestRide({
    required LatLng pickupLocation,
    required LatLng destinationLocation,
    required double proposedFare, // New parameter for proposed fare
  }) async {
    final response = await http.post(
      Uri.parse(_baseUrl), // Changed to base URL for ViewSet creation
      headers: await _getHeaders(),
      body: jsonEncode({
        'pickup_latitude': pickupLocation.latitude,
        'pickup_longitude': pickupLocation.longitude,
        'destination_latitude': destinationLocation.latitude,
        'destination_longitude': destinationLocation.longitude,
        'proposed_fare': proposedFare, // Include proposed fare
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to request ride: ${response.body}');
    }
  }

  Future<List<dynamic>> getRides({String? status, String? userRole}) async {
    // Consolidated method for fetching rides
    final Map<String, String> queryParams = {};
    if (status != null) queryParams['status'] = status;
    if (userRole != null) queryParams['user_role'] = userRole;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: await _getHeaders());

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch rides: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateRideStatus(
    int rideId,
    String status,
  ) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl$rideId/'),
      headers: await _getHeaders(),
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update ride status: ${response.body}');
    }
  }

  // New methods for bidding system
  Future<Map<String, dynamic>> submitDriverBid(
    int rideId,
    double amount,
    String message,
  ) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$rideId/driver-bid/'),
      headers: await _getHeaders(),
      body: jsonEncode({'amount': amount, 'message': message}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to submit driver bid: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> submitCounterOffer(
    int rideId,
    double amount,
    String message,
  ) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$rideId/submit-counter/'),
      headers: await _getHeaders(),
      body: jsonEncode({'amount': amount, 'message': message}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to submit counter offer: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> acceptBid(int rideId, int bidIndex) async {
    final response = await http.post(
      Uri.parse('$_baseUrl$rideId/accept-bid/$bidIndex/'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to accept bid: ${response.body}');
    }
  }

  // WebSocket connection for ride updates
  WebSocketChannel connectToRideUpdates(String token) {
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://10.0.2.2:8000/ws/rides/?token=$token'),
    );
    return _channel!;
  }

  void dispose() {
    _channel?.sink.close();
  }
}
