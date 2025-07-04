import 'package:flutter/material.dart';
import 'package:indrive/ride_history_screen.dart';
import 'package:indrive/settings_screen.dart';
import 'package:indrive/ride_request_screen.dart'; // Import RideRequestScreen
import 'package:indrive/auth/auth_service.dart';
import 'package:indrive/login_screen.dart';
import 'package:indrive/rides/ride_service.dart'; // Import RideService
import 'package:web_socket_channel/web_socket_channel.dart'; // Import WebSocketChannel
import 'package:indrive/map_screen.dart'; // Import MapScreen
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import Google Maps LatLng
import 'package:geolocator/geolocator.dart'; // Import geolocator
import 'dart:async'; // Import for StreamSubscription
import 'dart:convert'; // Import for jsonEncode
import 'package:indrive/utils/map_utils.dart'; // Import map_utils.dart

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
  final TextEditingController _fareController = TextEditingController(); // New
  bool _isRequestingRide = false;

  List<dynamic> _rides = []; // To store rider's or driver's rides
  WebSocketChannel? _channel; // WebSocket channel
  StreamSubscription<Position>? _positionStreamSubscription; // Location stream
  GoogleMapController? _mapController; // Google Map controller
  final Set<Marker> _markers = {}; // Markers for map
  final Set<Polyline> _polylines = {}; // Polylines for map
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
      // Ensure we have a fresh access token
      String? accessToken = await _authService.getAccessToken();
      if (accessToken == null) {
        // Attempt to refresh token if available or re-authenticate
        // For simplicity, just throw error if no token is found.
        throw Exception('Access token not found. Cannot connect WebSocket.');
      }

      // Re-connect WebSocket if already connected to ensure fresh token
      if (_channel != null) {
        _channel!.sink.close();
      }

      _channel = _rideService.connectToRideUpdates(accessToken);
      _channel?.stream.listen(
        (message) {
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
            _fetchRides();
          } else if (data['type'] == 'location_update') {
            final LatLng newPosition = LatLng(
              data['latitude'],
              data['longitude'],
            );
            final String markerId = 'user_${data['user_id']}';
            _updateMapMarkers(newPosition, markerId, 'Live Location');
            _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
          } else if (data['type'] == 'bid_update') {
            // Handle new bid updates
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'New Bid for Ride ${data['ride_id']}: \$${data['amount']}',
                ),
              ),
            );
            _fetchRides(); // Refresh rides to show new bids
          } else if (data['type'] == 'eta_update') {
            // Handle ETA updates
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'ETA for Ride ${data['ride_id']}: ${data['eta']} mins',
                ),
              ),
            );
            // Optionally update UI to display ETA
          } else if (data['type'] == 'bid.accepted') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bid Accepted for Ride ${data['ride_id']}!'),
              ),
            );
            _fetchRides();
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

    // Draw polyline using decoded string from backend
    if (ride['route_polyline'] != null) {
      final List<LatLng> decodedPolyline = decodePolyline(
        ride['route_polyline'],
      );
      _updateMapPolylines(decodedPolyline);
    } else {
      // Fallback to basic straight line if no polyline from backend
      _updateMapPolylines([pickupLatLng, destinationLatLng]);
    }

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

  void _updateAvailability(bool value) async {
    setState(() {
      _currentUser['is_available'] = value;
    });
    try {
      await _authService.updateUserProfile({'is_available': value});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Availability updated to $value')),
        );
        _fetchRides(); // Refresh rides list based on new availability
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update availability: $e')),
        );
      }
    }
  }

  Future<void> _fetchRides() async {
    try {
      print('Fetching rides for role: ${_currentUser['role']}'); // Debug print
      if (_currentUser['role'] == 'rider') {
        _rides = await _rideService.getRides(userRole: 'rider');
      } else if (_currentUser['role'] == 'driver') {
        _rides = await _rideService.getRides(userRole: 'driver');
      }
      print('Fetched ${_rides.length} rides.'); // Debug print
      setState(() {});
    } catch (e) {
      print('Error fetching rides: $e'); // Debug print
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
        proposedFare: double.parse(_fareController.text), // Added proposedFare
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ride requested! ID: ${newRide['id']}')),
        );
        _pickupController.clear();
        _destinationController.clear();
        _fareController.clear(); // Clear fare controller
        _fetchRides();
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

  Future<void> _acceptBid(int rideId, int bidIndex) async {
    try {
      await _rideService.acceptBid(rideId, bidIndex);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bid accepted!')));
        _fetchRides(); // Refresh rides list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error accepting bid: $e')));
      }
    }
  }

  // Helper to build list of driver bids for a ride
  List<Widget> _buildDriverBids(Map<String, dynamic> ride) {
    List<Widget> bidWidgets = [];
    if (ride['driver_proposals'] != null) {
      for (int i = 0; i < ride['driver_proposals'].length; i++) {
        final bid = ride['driver_proposals'][i];
        bidWidgets.add(
          ListTile(
            title: Text('Driver Bid: \$${bid['amount']}'),
            subtitle: Text('Message: ${bid['message'] ?? 'N/A'}'),
            trailing:
                _currentUser['role'] == 'rider' && ride['status'] == 'requested'
                ? ElevatedButton(
                    onPressed: () => _acceptBid(ride['id'], i),
                    child: const Text('Accept Bid'),
                  )
                : null,
          ),
        );
      }
    }
    return bidWidgets;
  }

  // Dialog for drivers to submit a bid
  Future<void> _showSubmitBidDialog(int rideId) async {
    final TextEditingController bidAmountController = TextEditingController();
    final TextEditingController bidMessageController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Submit Your Bid'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: bidAmountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bid Amount (\$)',
                    hintText: 'e.g., 15.00',
                  ),
                ),
                TextField(
                  controller: bidMessageController,
                  decoration: const InputDecoration(
                    labelText: 'Message (Optional)',
                    hintText: 'e.g., "Available in 5 mins"',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Submit'),
              onPressed: () async {
                try {
                  final double amount = double.parse(bidAmountController.text);
                  await _rideService.submitDriverBid(
                    rideId,
                    amount,
                    bidMessageController.text,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bid submitted!')),
                    );
                    _fetchRides(); // Refresh rides to show new bid
                  }
                  Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to submit bid: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InDrive'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRides,
            tooltip: 'Refresh Rides',
          ),
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
            tooltip: 'Logout',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            UserAccountsDrawerHeader(
              accountName: Text(_currentUser['phone_number'] ?? 'N/A'),
              accountEmail: Text('Role: ${_currentUser['role']}'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.black),
              ),
              decoration: const BoxDecoration(color: Colors.black),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch Role'),
              trailing: DropdownButton<String>(
                value: _currentUser['role'],
                onChanged: _updateRole,
                items: <String>['rider', 'driver'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value.toUpperCase()),
                  );
                }).toList(),
              ),
            ),
            if (_currentUser['role'] == 'driver')
              ListTile(
                leading: const Icon(Icons.drive_eta),
                title: const Text('Available for Rides'),
                trailing: Switch(
                  value: _currentUser['is_available'] ?? false,
                  onChanged: (bool value) {
                    _updateAvailability(value);
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Ride History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RideHistoryScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: _activeRide != null
          ? MapScreen(
              initialCameraPosition: CameraPosition(
                target: _parseLatLng(_activeRide!['pickup_location']),
                zoom: 12.0,
              ),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: _onMapCreated,
            )
          : _currentUser['role'] == 'rider'
          ? _buildRiderHome()
          : _buildDriverHome(),
      floatingActionButton:
          _currentUser['role'] == 'rider' && _activeRide == null
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RideRequestScreen(),
                  ),
                );
              },
              label: const Text('Request New Ride'),
              icon: const Icon(Icons.add),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildRiderHome() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Rides',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _rides.isEmpty
                ? const Center(
                    child: Text(
                      'No rides requested yet. Tap + to request one!',
                    ),
                  )
                : ListView.builder(
                    itemCount: _rides.length,
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'From: ${ride['pickup_location']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'To: ${ride['destination_location']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('Status: ${ride['status']}'),
                              Text('Proposed Fare: \$${ride['proposed_fare']}'),
                              if (ride['accepted_proposal'] != null)
                                Text(
                                  'Accepted Bid: \$${ride['accepted_proposal']['amount']} by Driver ${ride['accepted_proposal']['driver_id']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              if (ride['status'] == 'requested' &&
                                  ride['driver_proposals'] != null &&
                                  ride['driver_proposals'].isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Driver Bids:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    ..._buildDriverBids(ride),
                                  ],
                                )
                              else if (ride['status'] == 'requested')
                                const Text('Waiting for driver bids...'),
                              if (ride['status'] == 'accepted' ||
                                  ride['status'] == 'started')
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _activeRide = ride;
                                      _updateRideMap(_activeRide);
                                    });
                                  },
                                  child: const Text('View on Map'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverHome() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Rides',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _rides.isEmpty
                ? const Center(child: Text('No available rides at the moment.'))
                : ListView.builder(
                    itemCount: _rides.length,
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'From: ${ride['pickup_location']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'To: ${ride['destination_location']}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('Status: ${ride['status']}'),
                              Text('Proposed Fare: \$${ride['proposed_fare']}'),
                              const SizedBox(height: 10),
                              if (ride['status'] == 'requested')
                                ElevatedButton(
                                  onPressed: () =>
                                      _showSubmitBidDialog(ride['id']),
                                  child: const Text('Submit Bid'),
                                ),
                              if (ride['status'] == 'accepted' ||
                                  ride['status'] == 'started')
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Accepted Bid: \$${ride['accepted_proposal']['amount']}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _activeRide = ride;
                                          _updateRideMap(_activeRide);
                                        });
                                      },
                                      child: const Text('View on Map'),
                                    ),
                                    // Add buttons for 'Start Ride', 'Complete Ride' etc.
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
