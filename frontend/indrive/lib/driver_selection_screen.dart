import 'package:flutter/material.dart';
import 'package:indrive/rides/ride_service.dart'; // Import RideService

class DriverSelectionScreen extends StatefulWidget {
  final int rideId;

  const DriverSelectionScreen({Key? key, required this.rideId}) : super(key: key);

  @override
  State<DriverSelectionScreen> createState() => _DriverSelectionScreenState();
}

class _DriverSelectionScreenState extends State<DriverSelectionScreen> {
  final RideService _rideService = RideService();
  List<dynamic> _availableDrivers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAvailableDrivers();
  }

  Future<void> _fetchAvailableDrivers() async {
    try {
      // In a real scenario, you'd fetch drivers relevant to the ride request
      // For now, we'll just fetch all 'requested' rides and assume their drivers are 'available'
      // This part needs to be refined with actual backend logic for driver matching.
      final allRides = await _rideService.getRides(status: 'requested');
      // Filter out the current ride and extract potential drivers (this is a placeholder)
      _availableDrivers = allRides.where((ride) => ride['id'] != widget.rideId).toList();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load drivers: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDriver(int driverId, int bidIndex) async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _rideService.acceptBid(widget.rideId, bidIndex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride confirmed with selected driver!')),
        );
        Navigator.pop(context); // Go back to previous screen (e.g., Home or Ride Details)
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm ride: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Driver'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _availableDrivers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No available drivers found for this ride yet. Please wait or try again later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _availableDrivers.length,
                      itemBuilder: (context, index) {
                        final ride = _availableDrivers[index];
                        // Assuming 'driver_proposals' contains bids from drivers for this ride
                        // and we are showing the ride details as a proxy for driver info.
                        // In a real app, _availableDrivers would be a list of actual driver objects.
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: 16.0),
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
                                  'Ride ID: ${ride['id']}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text('From: ${ride['pickup_location']}'),
                                Text('To: ${ride['destination_location']}'),
                                const SizedBox(height: 10),
                                if (ride['driver_proposals'] != null &&
                                    ride['driver_proposals'].isNotEmpty)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: ride['driver_proposals']
                                        .asMap()
                                        .entries
                                        .map<Widget>((entry) {
                                      int bidIndex = entry.key;
                                      Map<String, dynamic> bid = entry.value;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Driver: ${bid['driver_id']}', // Placeholder
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                Text('Bid: \$${bid['amount']}'),
                                                Text(
                                                    'Message: ${bid['message'] ?? 'N/A'}'),
                                              ],
                                            ),
                                            ElevatedButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : () => _selectDriver(
                                                      bid['driver_id'],
                                                      bidIndex),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.black,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Text('Select'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  )
                                else
                                  const Text('No bids from drivers yet.'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}