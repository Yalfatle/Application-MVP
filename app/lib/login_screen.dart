import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // Navigate to Home

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Patient Controllers
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  
  // Lab Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // PATIENT LOGIN (Phone)
  Future<void> _signInPatient() async {
    setState(() => _isLoading = true);
    try {
      if (!_otpSent) {
        await Supabase.instance.client.auth.signInWithOtp(
          phone: "+964${_phoneController.text.trim()}",
        );
        setState(() => _otpSent = true);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code sent! (Use 123456)")));
      } else {
        final res = await Supabase.instance.client.auth.verifyOTP(
          type: OtpType.sms,
          token: _otpController.text.trim(),
          phone: "+964${_phoneController.text.trim()}",
        );
        if (res.session != null && mounted) {
          Navigator.of(context).pushAndRemoveUntil(
             MaterialPageRoute(builder: (_) => const MukhtabaratApp()), (route) => false);
        }
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  // LAB LOGIN (Email/Pass)
  Future<void> _signInLab() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (res.session != null && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MukhtabaratApp()), (route) => false);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 50),
            const Icon(Icons.science, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text("Mukhtabarat", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 30),
            
            // TABS
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
                tabs: const [
                  Tab(icon: Icon(Icons.person), text: "Patient"),
                  Tab(icon: Icon(Icons.business), text: "Lab Admin"),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // FORM AREA
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1. PATIENT FORM
                  Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      children: [
                        if (!_otpSent) ...[
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: "Phone Number", prefixText: "+964 ", border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(onPressed: _isLoading ? null : _signInPatient, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: _isLoading ? const CircularProgressIndicator() : const Text("Send Code"))
                        ] else ...[
                          TextField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(labelText: "Enter Code (123456)", border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(onPressed: _isLoading ? null : _signInPatient, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.green), child: _isLoading ? const CircularProgressIndicator() : const Text("Verify"))
                        ]
                      ],
                    ),
                  ),

                  // 2. LAB FORM
                  Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: "Lab Email", hintText: "lab@lab.com", border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _signInLab,
                          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.indigo),
                          child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Lab Login", style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}