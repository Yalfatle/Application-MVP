import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

typedef _PatientRow = ({String id, String name, DateTime last});

/// Everyone who has booked with this lab. Staff can only ever see these.
class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key, required this.labId});
  final String labId;

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  String _query = '';

  Future<List<_PatientRow>> _load() async {
    final rows = await services.orders.labPatients(widget.labId);
    final names = await services.orders.patientNames(rows.map((r) => r.$1));
    return [for (final r in rows) (id: r.$1, name: names[r.$1] ?? '', last: r.$2)];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return LoadView<List<_PatientRow>>(
      load: _load,
      isEmpty: (r) => r.isEmpty,
      builder: (context, rows, _) {
        final q = _query.trim().toLowerCase();
        final shown = q.isEmpty ? rows : rows.where((r) => r.name.toLowerCase().contains(q)).toList();
        return ContentWidth(
          maxWidth: 900,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.search),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            for (final r in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(r.name.isEmpty ? '—' : r.name),
                  subtitle: Text(formatDateTime(r.last, lang)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/staff/patient/${r.id}'),
                ),
              ),
          ]),
        );
      },
    );
  }
}
