import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrackingScreen extends StatefulWidget {
  final double userLat;
  final double userLng;
  final double labLat; // In a real app, this updates live via Supabase Realtime
  final double labLng;

  const TrackingScreen({
    super.key, 
    required this.userLat, 
    required this.userLng,
    required this.labLat,
    required this.labLng,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late GoogleMapController mapController;

  @override
  Widget build(BuildContext context) {
    // 1. Define Markers (Pins)
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('patient'),
        position: LatLng(widget.userLat, widget.userLng),
        infoWindow: const InfoWindow(title: 'You (Patient)'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId('runner'),
        position: LatLng(widget.labLat, widget.labLng),
        infoWindow: const InfoWindow(title: 'Lab Runner 🚗'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text("Track Order")),
      body: GoogleMap(
        onMapCreated: (controller) => mapController = controller,
        initialCameraPosition: CameraPosition(
          target: LatLng(widget.userLat, widget.userLng),
          zoom: 14.0,
        ),
        markers: markers,
        // Draws a simplified straight line (for MVP)
        polylines: {
          Polyline(
            polylineId: const PolylineId("route"),
            points: [
              LatLng(widget.userLat, widget.userLng),
              LatLng(widget.labLat, widget.labLng),
            ],
            color: Colors.blue,
            width: 5,
          )
        },
      ),
    );
  }
}