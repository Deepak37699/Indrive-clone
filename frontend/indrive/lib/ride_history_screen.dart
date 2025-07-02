import 'package:flutter/material.dart';
import 'package:indrive/rides/ride_service.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final RideService _rideService = RideService();
  List<dynamic> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRideHistory();
  }

  Future<void> _fetchRideHistory() async {
    try {
      final rides = await _rideService.getRides(status: 'completed');
      setState(() {
        _rides = rides;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching ride history: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rides.length,
              itemBuilder: (context, index) {
                final ride = _rides[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ride #${ride['id']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('From: ${ride['pickup_location']}'),
                        Text('To: ${ride['destination_location']}'),
                        const SizedBox(height: 8),
                        Text('Fare: \$${ride['final_fare'] ?? 'N/A'}'),
                        Text('Status: ${ride['status']}'),
                        if (ride['driver'] != null)
                          Text(
                            'Driver: ${ride['driver']['name'] ?? 'Unknown'}',
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
