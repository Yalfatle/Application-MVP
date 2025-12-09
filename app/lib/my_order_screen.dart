import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracking_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  // Fetch Orders + Join with Labs table to get the logo/name
  final _ordersStream = Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  // Helper to color-code the status
  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'on_way': return Colors.purple;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending': return "قيد الانتظار";
      case 'accepted': return "تم القبول";
      case 'on_way': return "المندوب بالطريق";
      case 'completed': return "مكتمل";
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("طلباتي"), centerTitle: true),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snapshot.data!;

          if (orders.isEmpty) {
            return const Center(child: Text("لا توجد طلبات سابقة"));
          }

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              // Note: In a real app, we would use .select('*, labs(*)') to get the lab name.
              // For MVP, we'll just show the package name.
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(order['status'] ?? 'pending').withOpacity(0.2),
                    child: Icon(Icons.history, color: _getStatusColor(order['status'] ?? 'pending')),
                  ),
                  title: Text(
                    order['package_name'] ?? "Unknown Package",
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("السعر: ${order['total_price']} IQD"),
                      Text(
                        _getStatusText(order['status'] ?? 'pending'),
                        style: TextStyle(
                          color: _getStatusColor(order['status'] ?? 'pending'),
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.map, color: Colors.blue),
                    onPressed: () {
                      // For MVP, we pass the Lab's location as the "Runner's" location.
                      // In the future, we fetch the runner's live GPS from the database.
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TrackingScreen(
                        userLat: 33.3128, // Hardcoded Patient (Mansour)
                        userLng: 44.3614,
                        labLat: 33.3150, // Slight offset to simulate runner distance
                        labLng: 44.3650,
                      )));
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}