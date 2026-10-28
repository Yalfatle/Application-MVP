import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../common/settings_screen.dart';
import 'labs_screen.dart';
import 'my_orders_screen.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [
        LabsScreen(),
        MyOrdersScreen(),
        SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.local_hospital_outlined), selectedIcon: const Icon(Icons.local_hospital), label: t.labsTitle),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: t.myOrders),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: t.settings),
        ],
      ),
    );
  }
}
