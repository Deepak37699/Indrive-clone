import 'package:flutter/material.dart';
import 'package:indrive/auth/auth_service.dart';
import 'package:indrive/login_screen.dart';
import 'package:indrive/rides/ride_service.dart'; // Import RideService
import 'package:web_socket_channel/web_socket_channel.dart'; // Import WebSocketChannel
import 'package:indrive/map_screen.dart'; // Import MapScreen
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import Google Maps LatLng
import 'package:geolocator/geolocator.dart'; // Import geolocator
import 'dart:async'; // Import for StreamSubscription
import 'dart:convert'; // Import for jsonEncode

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Map<String, dynamic> _currentUser;
  final AuthService _authService = AuthService();
  final RideService _rideService = RideService(); // Initialize RideService

  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  bool _isRequestingRide = false;

  List<dynamic> _rides = []; // To store rider's or driver's rides
  WebSocketChannel? _channel; // WebSocket channel
  StreamSubscription<Position>? _positionStreamSubscription; // Location stream
  GoogleMapController? _mapController; // Google Map controller
  Set<Marker> _markers = {}; // Markers for map
  Set<Polyline> _polylines = {}; // Polylines for map
  Map<String, dynamic>? _activeRide; // Store the currently active ride

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _fetchRides(); // Fetch rides when the screen initializes
    _connectWebSocket(); // Connect WebSocket
    _startLocationTracking(); // Start location tracking
  }

  @override
  void dispose() {
    _channel?.sink.close(); // Close WebSocket connection
    _positionStreamSubscription?.cancel(); // Cancel location stream
    _mapController?.dispose(); // Dispose map controller
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _updateMapMarkers(LatLng position, String markerId, String title) {
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: position,
          infoWindow: InfoWindow(title: title),
        ),
      );
    });
  }

  void _updateMapPolylines(List<LatLng> points) {
    setState(() {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: Colors.blue,
          width: 5,
        ),
      );
    });
  }

  void _startLocationTracking() async {
    // Check and request location permissions
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permissions are permanently denied, we cannot request permissions.',
            ),
          ),
        );
      }
      return;
    }

    // Configure location accuracy and interval
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {
          // Send location to backend if user is a driver and has an active ride
          if (_currentUser['role'] == 'driver' && _channel != null) {
            // Find an active ride to associate location with (for simplicity, use the first accepted ride)
            final activeRide = _rides.firstWhere(
              (ride) =>
                  ride['status'] == 'accepted' || ride['status'] == 'started',
              orElse: () => null,
            );

            if (activeRide != null) {
              _channel!.sink.add(
                jsonEncode({
                  'type': 'location_update',
                  'latitude': position.latitude,
                  'longitude': position.longitude,
                  'ride_id': activeRide['id'], // Associate with an active ride
                }),
              );
            }
          }
        });
  }

  void _connectWebSocket() async {
    try {
      final accessToken = await _authService.getAccessToken();
      if (accessToken == null) {
        throw Exception('Access token not found. Cannot connect WebSocket.');
      }
      // Use wss:// for secure WebSocket connections in production
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:8000/ws/rides/?token=$accessToken'),
      );
      _channel?.stream.listen(
        (message) {
          // Handle incoming WebSocket messages
          final data = jsonDecode(message);
          if (data['type'] == 'ride_update') {
            setState(() {
              _activeRide = data['content'];
              _updateRideMap(_activeRide);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ride Update: ${data['content']['status']}'),
              ),
            );
            _fetchRides(); // Refresh rides list
          } else if (data['type'] == 'location_update') {
            final LatLng newPosition = LatLng(
              data['latitude'],
              data['longitude'],
            );
            final String markerId = 'user_${data['user_id']}';
            _updateMapMarkers(newPosition, markerId, 'Live Location');
            // Optionally move camera to new position
            _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('WS Message: $message')));
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('WebSocket error: $error')));
          }
        },
        onDone: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('WebSocket disconnected.')),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect WebSocket: $e')),
        );
      }
    }
  }

  void _updateRideMap(Map<String, dynamic>? ride) {
    _markers.clear();
    _polylines.clear();

    if (ride == null) {
      setState(() {});
      return;
    }

    // Add pickup and destination markers
    final LatLng pickupLatLng = _parseLatLng(ride['pickup_location']);
    final LatLng destinationLatLng = _parseLatLng(ride['destination_location']);

    _updateMapMarkers(pickupLatLng, 'pickup', 'Pickup');
    _updateMapMarkers(destinationLatLng, 'destination', 'Destination');

    // Draw polyline (basic straight line for now)
    _updateMapPolylines([pickupLatLng, destinationLatLng]);

    // Move camera to show both points
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            pickupLatLng.latitude < destinationLatLng.latitude
                ? pickupLatLng.latitude
                : destinationLatLng.latitude,
            pickupLatLng.longitude < destinationLatLng.longitude
                ? pickupLatLng.longitude
                : destinationLatLng.longitude,
          ),
          northeast: LatLng(
            pickupLatLng.latitude > destinationLatLng.latitude
                ? pickupLatLng.latitude
                : destinationLatLng.latitude,
            pickupLatLng.longitude > destinationLatLng.longitude
                ? pickupLatLng.longitude
                : destinationLatLng.longitude,
          ),
        ),
        100.0, // padding
      ),
    );
    setState(() {});
  }

  void _updateRole(String? newRole) async {
    if (newRole != null && newRole != _currentUser['role']) {
      try {
        await _authService.updateUserProfile({'role': newRole});
        final updatedUser = await _authService.getUserProfile();
        setState(() {
          _currentUser = updatedUser;
          _fetchRides(); // Refetch rides based on new role
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Role updated to $newRole')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
        }
      }
    }
  }

  Future<void> _fetchRides() async {
    try {
      if (_currentUser['role'] == 'rider') {
        _rides = await _rideService.getRiderRides();
      } else if (_currentUser['role'] == 'driver') {
        _rides = await _rideService.getDriverRides();
      }
      setState(() {}); // Update UI with new rides
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch rides: $e')));
      }
    }
  }

  Future<void> _requestRide() async {
    setState(() {
      _isRequestingRide = true;
    });
    try {
      final newRide = await _rideService.requestRide(
        pickupLocation: _parseLatLng(_pickupController.text),
        destinationLocation: _parseLatLng(_destinationController.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ride requested! ID: ${newRide['id']}')),
        );
        _pickupController.clear();
        _destinationController.clear();
        _fetchRides(); // Refresh rides list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error requesting ride: $e')));
      }
    } finally {
      setState(() {
        _isRequestingRide = false;
      });
    }
  }

  // Helper function to parse LatLng from string
  LatLng _parseLatLng(String latLngString) {
    final parts = latLngString.split(',');
    if (parts.length == 2) {
      final latitude = double.tryParse(parts[0].trim());
      final longitude = double.tryParse(parts[1].trim());
      if (latitude != null && longitude != null) {
        return LatLng(latitude, longitude);
      }
    }
    // Return a default or throw an error if parsing fails
    return const LatLng(0.0, 0.0); // Default to (0,0) or handle error
  }

  Future<void> _acceptRide(int rideId) async {
    try {
      await _rideService.updateRideStatus(rideId, 'accepted');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ride accepted!')));
        _fetchRides(); // Refresh rides list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error accepting ride: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRides),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Welcome!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            Text('Phone Number: ${_currentUser['phone_number']}'),
            Text('Current Role: ${_currentUser['role']}'),
            const SizedBox(height: 20),
            DropdownButton<String>(
              value: _currentUser['role'],
              onChanged: _updateRole,
              items: <String>['rider', 'driver'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value.toUpperCase()),
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
            // Rider UI
            if (_currentUser['role'] == 'rider')
              Column(
                children: [
                  Text(
                    'Request a Ride',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pickupController,
                    readOnly:
                        true, // Make it read-only as location is picked from map
                    onTap: () async {
                      final LatLng? selectedLocation = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MapScreen(),
                        ),
                      );
                      if (selectedLocation != null) {
                        _pickupController.text =
                            '${selectedLocation.latitude}, ${selectedLocation.longitude}';
                        // In a real app, you'd convert LatLng to a human-readable address
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Pickup Location',
                      hintText: 'Tap to select from map',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.map),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _destinationController,
                    readOnly: true, // Make it read-only
                    onTap: () async {
                      final LatLng? selectedLocation = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MapScreen(),
                        ),
                      );
                      if (selectedLocation != null) {
                        _destinationController.text =
                            '${selectedLocation.latitude}, ${selectedLocation.longitude}';
                        // In a real app, you'd convert LatLng to a human-readable address
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Destination Location',
                      hintText: 'Tap to select from map',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.map),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _isRequestingRide
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _requestRide,
                          child: const Text('Request Ride'),
                        ),
                  const SizedBox(height: 30),
                  Text(
                    'My Rides',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _rides.length,
                      itemBuilder: (context, index) {
                        final ride = _rides[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ListTile(
                            title: Text(
                              '${ride['pickup_location']} to ${ride['destination_location']}',
                            ),
                            subtitle: Text('Status: ${ride['status']}'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            // Driver UI
            if (_currentUser['role'] == 'driver')
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Available Rides',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _rides.length,
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ListTile(
                              title: Text(
                                '${ride['pickup_location']} to ${ride['destination_location']}',
                              ),
                              subtitle: Text('Status: ${ride['status']}'),
                              trailing: ride['status'] == 'requested'
                                  ? ElevatedButton(
                                      onPressed: () => _acceptRide(ride['id']),
                                      child: const Text('Accept'),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
