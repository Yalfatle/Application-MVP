import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../admin/earnings_screen.dart';
import '../admin/employees_screen.dart';
import '../admin/lab_details_screen.dart';
import '../admin/packages_screen.dart';
import '../common/settings_screen.dart';
import '../super_admin/labs_admin_screen.dart';
import '../super_admin/platform_settings_screen.dart';
import '../super_admin/users_screen.dart';
import 'lab_messages_screen.dart';
import 'orders_board.dart';
import 'patients_screen.dart';

class _Dest {
  const _Dest(this.icon, this.label, this.build);
  final IconData icon;
  final String label;
  final Widget Function() build;
}

/// Home for everyone who isn't a patient. What's in the menu depends on
/// the role: clerks and runners see daily work, owners also manage the
/// lab, platform admins manage every lab.
class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  int _index = 0;

  List<_Dest> _destinations(AppLocalizations t, Session s) {
    final lab = s.labId;
    if (s.role == UserRole.superAdmin) {
      return [
        _Dest(Icons.local_hospital_outlined, t.allLabs, () => const LabsAdminScreen()),
        _Dest(Icons.people_outline, t.users, () => const UsersScreen()),
        _Dest(Icons.payments_outlined, t.earnings, () => const EarningsScreen()),
        _Dest(Icons.tune, t.platformSettings, () => const PlatformSettingsScreen()),
        _Dest(Icons.settings_outlined, t.settings, () => const SettingsScreen(showAppBar: false)),
      ];
    }
    if (lab == null) return [_Dest(Icons.settings_outlined, t.settings, () => const SettingsScreen(showAppBar: false))];
    return [
      _Dest(Icons.assignment_outlined, t.ordersTitle, () => OrdersBoard(labId: lab)),
      _Dest(Icons.folder_shared_outlined, t.patients, () => PatientsScreen(labId: lab)),
      _Dest(Icons.chat_bubble_outline, t.messages, () => LabMessagesScreen(labId: lab)),
      if (s.role == UserRole.labAdmin) ...[
        _Dest(Icons.storefront_outlined, t.labDetails, () => LabDetailsScreen(labId: lab)),
        _Dest(Icons.science_outlined, t.testsAndPrices, () => PackagesScreen(labId: lab)),
        _Dest(Icons.badge_outlined, t.employees, () => EmployeesScreen(labId: lab)),
        _Dest(Icons.payments_outlined, t.earnings, () => const EarningsScreen()),
      ],
      _Dest(Icons.settings_outlined, t.settings, () => const SettingsScreen(showAppBar: false)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final dests = _destinations(t, session);
    if (_index >= dests.length) _index = 0;
    final current = dests[_index];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final body = KeyedSubtree(key: ValueKey('${session.role.db}-$_index'), child: current.build());

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.biotech_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: [
              for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _Titled(title: current.label, child: body)),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(current.label)),
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
            child: Text(session.profile?.fullName ?? t.appName, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final d in dests) NavigationDrawerDestination(icon: Icon(d.icon), label: Text(d.label)),
        ],
      ),
      body: body,
    );
  }
}

class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: child,
      );
}
