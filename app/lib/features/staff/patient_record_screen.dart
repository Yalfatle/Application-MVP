import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/documents_list.dart';
import '../common/widgets.dart';

/// A patient's history at this lab, plus every document on file.
/// Clerks (and above) can upload and delete documents and message them.
class PatientRecordScreen extends StatefulWidget {
  const PatientRecordScreen({super.key, required this.patientId});
  final String patientId;

  @override
  State<PatientRecordScreen> createState() => _PatientRecordScreenState();
}

class _PatientRecordScreenState extends State<PatientRecordScreen> {
  late final Future<String?> _name = services.orders.personName(widget.patientId);

  Future<void> _message(String labId, String name) async {
    try {
      final conv = await services.messages.open(labId, widget.patientId);
      if (!mounted) return;
      context.push('/chat/${conv.id}?title=${Uri.encodeComponent(name)}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final labId = session.labId;
    return FutureBuilder<String?>(
      future: _name,
      builder: (context, nameSnap) {
        final name = nameSnap.data ?? '';
        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: ContentWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (labId != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _message(labId, name),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(t.messages),
                  ),
                ),
              SectionTitle(t.patientHistory),
              FutureBuilder<List<LabOrder>>(
                future: services.orders.fetchPatientOrders(widget.patientId, labId: labId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return snap.hasError
                        ? Text(friendlyError(context, snap.error!))
                        : const Center(child: CircularProgressIndicator());
                  }
                  final orders = snap.data!;
                  if (orders.isEmpty) return Text(t.nothingHere);
                  return Column(children: [
                    for (final o in orders)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(o.packageName(session.lang)),
                          subtitle: Text(formatDateTime(o.createdAt, session.lang)),
                          trailing: StatusChip(o.status),
                          onTap: () => context.push('/staff/order/${o.id}'),
                        ),
                      ),
                  ]);
                },
              ),
              SectionTitle(t.documents),
              DocumentsList(
                patientId: widget.patientId,
                uploadLabId: labId,
                canDelete: true,
                emptyText: t.noDocuments,
              ),
            ]),
          ),
        );
      },
    );
  }
}
