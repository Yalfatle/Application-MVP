import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'login_screen.dart'; 
import 'my_order_screen.dart';
import 'lab_dashboard_screen.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MukhtabaratApp());
}

class MukhtabaratApp extends StatefulWidget {
  const MukhtabaratApp({super.key});

  @override
  State<MukhtabaratApp> createState() => _MukhtabaratAppState();
}

class _MukhtabaratAppState extends State<MukhtabaratApp> {
  // By default, we show a loader until we check the role
  Widget _homeScreen = const Scaffold(body: Center(child: CircularProgressIndicator()));

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      // Not logged in? Show Login Screen (or Patient List)
      setState(() => _homeScreen = const LoginScreen()); 
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      // IF role is admin -> Dashboard. ELSE -> Patient List
      if (data['role'] == 'lab_admin') {
        setState(() => _homeScreen = const LabDashboardScreen());
      } else {
        setState(() => _homeScreen = const LabListScreen());
      }
    } catch (e) {
      // If profile is missing (the error you had), default to Patient List
      setState(() => _homeScreen = const LabListScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mukhtabarat',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Arial'),
      home: _homeScreen, // <--- Dynamic Home
    );
  }
}

class LabListScreen extends StatefulWidget {
  const LabListScreen({super.key});

  @override
  State<LabListScreen> createState() => _LabListScreenState();
}

class _LabListScreenState extends State<LabListScreen> {
  // Using Future to prevent infinite loading loop
  late Future<List<Map<String, dynamic>>> _labsFuture;

  @override
  void initState() {
    super.initState();
    _loadLabs();
  }

  void _loadLabs() {
    // Select * from labs
    _labsFuture = Supabase.instance.client
        .from('labs')
        .select()
        .order('name_ar', ascending: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("المختبرات القريبة"),
        centerTitle: true,
        // Left side: My Orders
        leading: IconButton(
          icon: const Icon(Icons.receipt_long), 
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersScreen()));
          },
        ),
        // Right side: Log Out
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              // 1. Sign out from Supabase
              await Supabase.instance.client.auth.signOut();
              
              // 2. Go back to Login Screen
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _labsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
             // If table is missing, this will tell us
            return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final labs = snapshot.data ?? [];
          if (labs.isEmpty) {
            return Center(
              child: ElevatedButton(
                onPressed: () => setState(() => _loadLabs()),
                child: const Text("No Labs Found. Refresh?"),
              ),
            );
          }
          return ListView.builder(
            itemCount: labs.length,
            itemBuilder: (context, index) {
              final lab = labs[index];
              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  leading: const Icon(Icons.local_hospital, size: 40, color: Colors.blue),
                  title: Text(lab['name_ar'], textDirection: TextDirection.rtl),
                  subtitle: const Text("المنصور - بغداد", textDirection: TextDirection.rtl),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LabDetailsScreen(
                          labId: lab['id'], 
                          labName: lab['name_ar']
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LabDetailsScreen extends StatelessWidget {
  final String labId;
  final String labName;

  const LabDetailsScreen({super.key, required this.labId, required this.labName});

  // THE LOGIC: Send Order to Database
  Future<void> _placeOrder(BuildContext context, Map<String, dynamic> pack) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    try {
      // 1. Calculate Financials
      final price = pack['price']; // e.g., 25000
      final commission = price * 0.10; // 10% fee = 2500

      // 2. Insert into Database
      await Supabase.instance.client.from('orders').insert({
        'user_id': user.id,
        'lab_id': labId,
        'status': 'pending', // Waiting for Lab to accept
        'total_price': price,
        'commission_fee': commission,
        'payment_method': 'cash', // Hardcoded for MVP
        'package_name': pack['name_ar'], // The column we just added
        'delivery_lat': 33.3128, // Hardcoded user location for now (Mansour)
        'delivery_lng': 44.3614,
      });

      // 3. Show Success Message
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("تم الحجز بنجاح!"), // Success
            content: Text("تم إرسال طلبك إلى $labName.\nسيتم الاتصال بك قريباً."),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final _packagesStream = Supabase.instance.client
        .from('packages')
        .stream(primaryKey: ['id'])
        .eq('lab_id', labId);

    return Scaffold(
      appBar: AppBar(title: Text(labName), centerTitle: true),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _packagesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final packages = snapshot.data!;
          
          if (packages.isEmpty) return const Center(child: Text("No packages"));

          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final pack = packages[index];
              return Card(
                child: ListTile(
                  title: Text(pack['name_ar'], textAlign: TextAlign.right),
                  subtitle: Text("${pack['price']} IQD", textAlign: TextAlign.right),
                  leading: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    onPressed: () => _placeOrder(context, pack),
                    child: const Text("حجز"),
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