import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:indrive/map_screen.dart';
import 'package:indrive/rides/ride_service.dart'; // Import RideService
import 'package:indrive/driver_selection_screen.dart'; // Import DriverSelectionScreen

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({Key? key}) : super(key: key);

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

enum PaymentMethod { cash, card }

class _RideRequestScreenState extends State<RideRequestScreen> {
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  int _numberOfPassengers = 1;
  String _vehicleType = 'Economy';
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _isRequestingRide = false; // Track ride request status
  final RideService _rideService = RideService(); // Initialize RideService

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _requestRide() async {
    setState(() {
      _isRequestingRide = true;
    });
    try {
      if (_pickupLocation == null || _destinationLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select pickup and destination locations')),
        );
        return;
      }

      final newRide = await _rideService.requestRide(
        pickupLocation: _pickupLocation!,
        destinationLocation: _destinationLocation!,
        proposedFare: 10.0, // Replace with actual fare input
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ride requested! ID: ${newRide['id']}')),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DriverSelectionScreen(rideId: newRide['id']),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error requesting ride: $e')),
        );
      }
    } finally {
      setState(() {
        _isRequestingRide = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request a Ride'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Where are you going?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _pickupController,
              readOnly: true,
              onTap: () async {
                final LatLng? selectedLocation = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MapScreen(showSelectionControls: true),
                  ),
                );
                if (selectedLocation != null) {
                  setState(() {
                    _pickupLocation = selectedLocation;
                    _pickupController.text =
                        '${selectedLocation.latitude}, ${selectedLocation.longitude}';
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Pickup Location',
                hintText: 'Tap to select from map',
                prefixIcon: const Icon(Icons.location_on),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _destinationController,
              readOnly: true,
              onTap: () async {
                final LatLng? selectedLocation = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MapScreen(showSelectionControls: true),
                  ),
                );
                if (selectedLocation != null) {
                  setState(() {
                    _destinationLocation = selectedLocation;
                    _destinationController.text =
                        '${selectedLocation.latitude}, ${selectedLocation.longitude}';
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Destination Location',
                hintText: 'Tap to select from map',
                prefixIcon: const Icon(Icons.flag),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Ride Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Number of Passengers',
                prefixIcon: const Icon(Icons.people),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              value: _numberOfPassengers,
              items: List.generate(5, (index) => index + 1)
                  .map((number) => DropdownMenuItem(
                        value: number,
                        child: Text('$number Passenger(s)'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _numberOfPassengers = value!;
                });
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Vehicle Type',
                prefixIcon: const Icon(Icons.car_rental),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              value: _vehicleType,
              items: ['Economy', 'Comfort', 'Premium']
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _vehicleType = value!;
                });
              },
            ),
            const SizedBox(height: 30),
            const Text(
              'Payment Method',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            RadioListTile<PaymentMethod>(
              title: const Text('Cash'),
              value: PaymentMethod.cash,
              groupValue: _paymentMethod,
              onChanged: (value) {
                setState(() {
                  _paymentMethod = value!;
                });
              },
              activeColor: Colors.black,
            ),
            RadioListTile<PaymentMethod>(
              title: const Text('Card'),
              value: PaymentMethod.card,
              groupValue: _paymentMethod,
              onChanged: (value) {
                setState(() {
                  _paymentMethod = value!;
                });
              },
              activeColor: Colors.black,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isRequestingRide ? null : _requestRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isRequestingRide
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Request Ride',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}