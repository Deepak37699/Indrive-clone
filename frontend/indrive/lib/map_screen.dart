import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Function(GoogleMapController)? onMapCreated;
  final bool showSelectionControls; // New parameter

  const MapScreen({
    super.key,
    this.initialCameraPosition = const CameraPosition(
      target: LatLng(27.7172, 85.3240), // Default to Kathmandu, Nepal
      zoom: 12.0,
    ),
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.showSelectionControls = true, // Default to true
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    if (widget.showSelectionControls) {
      _getCurrentLocation();
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (widget.onMapCreated != null) {
      widget.onMapCreated!(controller);
    }
  }

  Future<void> _getCurrentLocation() async {
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

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _selectedLocation = LatLng(position.latitude, position.longitude);
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(_selectedLocation!),
    );
  }

  void _onTap(LatLng latLng) {
    if (widget.showSelectionControls) {
      setState(() {
        _selectedLocation = latLng;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showSelectionControls
          ? AppBar(
              title: const Text('Select Location'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    Navigator.pop(context, _selectedLocation);
                  },
                ),
              ],
            )
          : null, // No AppBar if not showing selection controls
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: widget.initialCameraPosition,
        onTap: widget.showSelectionControls ? _onTap : null,
        markers: widget.showSelectionControls && _selectedLocation != null
            ? {
                Marker(
                  markerId: const MarkerId('selected-location'),
                  position: _selectedLocation!,
                ),
              }
            : widget.markers,
        polylines: widget.polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
      floatingActionButton: widget.showSelectionControls
          ? FloatingActionButton(
              onPressed: _getCurrentLocation,
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }
}
