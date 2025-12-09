import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart'; // For distance math
import 'package:url_launcher/url_launcher.dart'; // To open Google Maps

class LabDashboardScreen extends StatefulWidget {
  const LabDashboardScreen({super.key});

  @override
  State<LabDashboardScreen> createState() => _LabDashboardScreenState();
}

class _LabDashboardScreenState extends State<LabDashboardScreen> {
  String? _myLabId;
  // Hardcoded Lab Location (Mansour) for MVP distance calculation
  // In a real app, we would fetch these from the 'labs' table columns
  final double _labLat = 33.3128;
  final double _labLng = 44.3614;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyLab();
  }

  Future<void> _fetchMyLab() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('labs')
          .select('id')
          .eq('owner_id', userId)
          .single();
      
      setState(() {
        _myLabId = data['id'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // --- ACTIONS ---

  Future<void> _uploadResultAndFinish(String orderId) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png'],
    );

    if (result != null) {
      // In web, use bytes. In mobile, use path. 
      // This implementation is safer for both in this specific context.
      final fileBytes = result.files.first.bytes; 
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_${result.files.first.name}";

      try {
        await Supabase.instance.client.storage
            .from('medical_reports')
            .uploadBinary(fileName, fileBytes!);

        final pdfUrl = Supabase.instance.client.storage
            .from('medical_reports')
            .getPublicUrl(fileName);

        await Supabase.instance.client.from('orders').update({
          'status': 'completed',
          'result_pdf_url': pdfUrl,
        }).eq('id', orderId);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report Sent! ✅")));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
      }
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    if (newStatus == 'results_ready') {
      _uploadResultAndFinish(orderId);
      return;
    }
    await Supabase.instance.client.from('orders').update({'status': newStatus}).eq('id', orderId);
  }

  Future<void> _openMap(double lat, double lng) async {
    final googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open Maps")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_myLabId == null) return const Scaffold(body: Center(child: Text("Access Denied")));

    final _ordersStream = Supabase.instance.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('lab_id', _myLabId!)
        .order('created_at', ascending: false);

    return Scaffold(
      appBar: AppBar(title: const Text("Lab Control Panel"), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snapshot.data!;
          if (orders.isEmpty) return const Center(child: Text("No Active Orders"));

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return OrderCard(
                order: order, 
                labLat: _labLat, 
                labLng: _labLng,
                onUpdateStatus: _updateStatus,
                onOpenMap: _openMap,
              );
            },
          );
        },
      ),
    );
  }
}

// --- HELPER WIDGET FOR CLEANER CODE ---
// REPLACE THE OLD OrderCard WITH THIS SMART VERSION
class OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final double labLat;
  final double labLng;
  final Future<void> Function(String, String) onUpdateStatus;
  final Function(double, double) onOpenMap;

  const OrderCard({
    super.key, 
    required this.order, 
    required this.labLat, 
    required this.labLng,
    required this.onUpdateStatus,
    required this.onOpenMap,
  });

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  bool _isProcessing = false; // Tracks if we are currently clicking a button

  // Wrapper to handle the "Loading" animation
  Future<void> _handleAction(String newStatus) async {
    setState(() => _isProcessing = true); // Start Spinner
    try {
      await widget.onUpdateStatus(widget.order['id'], newStatus);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      // STOP Spinner regardless of success or failure
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final userLat = order['delivery_lat'] ?? 0.0;
    final userLng = order['delivery_lng'] ?? 0.0;
    
    // Calculate Distance
    final distanceInMeters = Geolocator.distanceBetween(
      widget.labLat, widget.labLng, userLat, userLng
    );
    final distanceKm = (distanceInMeters / 1000).toStringAsFixed(1);

    // Fetch User Name
    final userFuture = Supabase.instance.client
        .from('profiles')
        .select('full_name, phone')
        .eq('id', order['user_id'])
        .single();

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("#${order['id'].toString().substring(0, 4)}", style: TextStyle(color: Colors.grey[600])),
                Text(order['package_name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(),

            // Patient Details
            FutureBuilder(
              future: userFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Text("Loading User...");
                final user = snapshot.data as Map<String, dynamic>;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user['full_name'] ?? "Unknown"),
                  subtitle: Text(user['phone'] ?? "No Phone"),
                  trailing: IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: () => launchUrl(Uri.parse("tel:${user['phone']}")),
                  ),
                );
              },
            ),

            // Location
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Distance: $distanceKm km", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text("Lat: $userLat, Lng: $userLng", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onOpenMap(userLat, userLng),
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text("Map"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[100], foregroundColor: Colors.blue[900]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // ACTION BUTTONS (With Loading Logic)
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else
              _buildActionButtons(order['status']),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(String status) {
    // 1. PENDING: Accept or Refuse
    if (status == 'pending') {
      return Row(children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleAction('refused'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Refuse", style: TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleAction('accepted'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Accept", style: TextStyle(color: Colors.white)),
          ),
        ),
      ]);
    }

    // 2. ACCEPTED: Dispatch
    if (status == 'accepted') {
      return SizedBox(
        width: double.infinity, 
        child: ElevatedButton(
          onPressed: () => _handleAction('on_way'),
          child: const Text("Dispatch Runner 🚗"),
        ),
      );
    }

    // 3. ON WAY: Arrived/Sample Taken
    if (status == 'on_way') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _handleAction('sample_taken'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: const Text("Sample Collected 🩸", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // 4. SAMPLE TAKEN: Upload Result
    if (status == 'sample_taken') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _handleAction('results_ready'), // This triggers PDF upload logic
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text("Upload PDF Report 📄", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // 5. COMPLETED
    return const Center(
      child: Text("✅ Order Completed", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16))
    );
  }
}