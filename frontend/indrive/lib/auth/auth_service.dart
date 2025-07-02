import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
final String _apiHost = '10.0.2.2'; // Host for the backend API
final int _apiPort = 8000; // Port for the backend API
final String _authBasePath = 'api/auth'; // Base path for authentication endpoints
  final _storage = const FlutterSecureStorage();

  String _buildApiUrl(String endpoint) {
    return 'http://$_apiHost:$_apiPort/$_authBasePath/$endpoint';
  }

  Future<void> sendOtp(String phoneNumber) async {
    print('API Host: $_apiHost');
    print('API Port: $_apiPort');
    final url = Uri.parse(_buildApiUrl('send-otp/'));
    print('Sending OTP request to: $url');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send OTP: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phoneNumber, String otp) async {
    final response = await http.post(
      Uri.parse(_buildApiUrl('verify-otp/')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber, 'otp': otp}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access']);
      await _storage.write(key: 'refresh_token', value: data['refresh']);
      return data['user'];
    } else {
      throw Exception('Failed to verify OTP: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.get(
      Uri.parse(_buildApiUrl('profile')),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch user profile: ${response.body}');
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> userData) async {
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      throw Exception('Access token not found. User not authenticated.');
    }

    final response = await http.patch(
      Uri.parse(_buildApiUrl('profile')),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(userData),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update user profile: ${response.body}');
    }
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
