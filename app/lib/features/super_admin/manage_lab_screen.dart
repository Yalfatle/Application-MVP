import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../admin/employees_screen.dart';
import '../admin/lab_details_screen.dart';
import '../admin/packages_screen.dart';
import '../staff/orders_board.dart';

/// Platform admins manage any lab with the same screens its owner uses.
class ManageLabScreen extends StatelessWidget {
  const ManageLabScreen({super.key, required this.labId});
  final String labId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.manage),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: t.labDetails),
            Tab(text: t.testsAndPrices),
            Tab(text: t.employees),
            Tab(text: t.ordersTitle),
          ]),
        ),
        body: TabBarView(children: [
          LabDetailsScreen(labId: labId),
          PackagesScreen(labId: labId),
          EmployeesScreen(labId: labId),
          OrdersBoard(labId: labId),
        ]),
      ),
    );
  }
}
