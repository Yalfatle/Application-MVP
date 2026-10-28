import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/documents_list.dart';
import '../common/widgets.dart';
import 'runner_beacon.dart';

class StaffOrderScreen extends StatefulWidget {
  const StaffOrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  State<StaffOrderScreen> createState() => _StaffOrderScreenState();
}

class _StaffOrderScreenState extends State<StaffOrderScreen> {
  late final Stream<LabOrder?> _order = services.orders.watchOrder(widget.orderId);
  final _docsKey = GlobalKey<DocumentsListState>();
  String? _patientName;
  String? _runnerName;
  String? _runnerFor;
  List<StaffMember>? _runners;
  bool _askedPatient = false;

  void _loadPeople(LabOrder o) {
    if (!_askedPatient) {
      _askedPatient = true;
      services.orders.personName(o.patientId).then((n) {
        if (mounted) setState(() => _patientName = n ?? '');
      }).ignore();
    }
    if (o.runnerId != null && _runnerFor != o.runnerId) {
      _runnerFor = o.runnerId;
      services.orders.personName(o.runnerId!).then((n) {
        if (mounted) setState(() => _runnerName = n);
      }).ignore();
    }
  }

  Future<void> _status(LabOrder o, OrderStatus s, {String? reason}) async {
    await services.orders.setStatus(o.id, s, reason: reason);
  }

  Future<void> _refuse(LabOrder o) async {
    final t = AppLocalizations.of(context);
    final reason = await promptDialog(context, t.refuseReason);
    if (reason == null) return;
    await _status(o, OrderStatus.refused, reason: reason.isEmpty ? null : reason);
  }

  Future<void> _pickRunner(LabOrder o) async {
    final t = AppLocalizations.of(context);
    _runners ??= await services.staff.runners(o.labId);
    if (!mounted) return;
    if (_runners!.isEmpty) {
      showMessage(context, t.noRunners);
      return;
    }
    final picked = await showModalBottomSheet<StaffMember>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(t.assignRunner, style: Theme.of(ctx).textTheme.titleMedium)),
          for (final r in _runners!)
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(r.fullName ?? ''),
              selected: r.id == o.runnerId,
              onTap: () => Navigator.pop(ctx, r),
            ),
        ]),
      ),
    );
    if (picked != null) await services.orders.assignRunner(o.id, picked.id);
  }

  Future<void> _message(LabOrder o) async {
    try {
      final conv = await services.messages.open(o.labId, o.patientId);
      if (!mounted) return;
      context.push('/chat/${conv.id}?title=${Uri.encodeComponent(_patientName ?? '')}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final lang = session.lang;
    final role = session.role;
    final me = session.userId;
    final c = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_patientName ?? '')),
      body: StreamBuilder<LabOrder?>(
        stream: _order,
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return ErrorState(message: friendlyError(context, snap.error!), onRetry: () => setState(() {}));
          }
          final o = snap.data;
          if (o == null) return const Center(child: CircularProgressIndicator());
          _loadPeople(o);

          final isAdmin = role.atLeast(UserRole.labAdmin);
          final iAmRunner = o.runnerId != null && o.runnerId == me;
          final canDispatch = iAmRunner || isAdmin;
          final canDecide = role.atLeast(UserRole.clerk);
          final canAssignOthers = canDecide && role != UserRole.runner;

          return ContentWidth(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text(o.packageName(lang), style: Theme.of(context).textTheme.titleLarge)),
                StatusChip(o.status),
              ]),
              Text('${formatDateTime(o.createdAt, lang)} · ${t.priceIqd(formatIqd(o.priceIqd, lang))}'),
              if (o.statusReason != null) ...[
                const SizedBox(height: 6),
                Text(o.statusReason!, style: TextStyle(color: c.error)),
              ],
              const SizedBox(height: 16),

              // Where to go
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.place),
                    title: Text('${o.lat.toStringAsFixed(5)}, ${o.lng.toStringAsFixed(5)}', textDirection: TextDirection.ltr),
                    subtitle: o.locationNote == null ? null : Text('${t.patientNote}: ${o.locationNote}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.tonalIcon(
                        onPressed: () => openExternal(context, o.directionsLink),
                        icon: const Icon(Icons.directions),
                        label: Text(t.openInMaps),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: o.mapsLink));
                          if (context.mounted) showMessage(context, t.copied);
                        },
                        icon: const Icon(Icons.link),
                        label: Text(t.copyLocationLink),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // Runner
              if (o.status == OrderStatus.accepted || o.status.isActive)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_car_outlined),
                    title: Text(o.runnerId == null ? t.unassigned : t.assignedTo(_runnerName ?? '…')),
                    trailing: o.status == OrderStatus.accepted && canAssignOthers
                        ? TextButton(onPressed: () => _pickRunner(o), child: Text(t.assignRunner))
                        : null,
                  ),
                ),
              if (o.status == OrderStatus.onWay && iAmRunner) ...[
                const SizedBox(height: 12),
                RunnerBeacon(orderId: o.id),
              ],
              const SizedBox(height: 16),

              // Next step
              ..._actions(context, o, t,
                  canDecide: canDecide,
                  canDispatch: canDispatch,
                  canAssignOthers: canAssignOthers,
                  role: role),

              SectionTitle(t.results),
              DocumentsList(
                key: _docsKey,
                patientId: o.patientId,
                orderId: o.id,
                uploadLabId: canDecide && (o.status == OrderStatus.sampleTaken || o.status == OrderStatus.completed)
                    ? o.labId
                    : null,
                canDelete: canDecide,
                emptyText: t.noDocuments,
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _message(o),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(t.messages),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/staff/patient/${o.patientId}'),
                  icon: const Icon(Icons.folder_shared_outlined),
                  label: Text(t.patientHistory),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _actions(BuildContext context, LabOrder o, AppLocalizations t,
      {required bool canDecide, required bool canDispatch, required bool canAssignOthers, required UserRole role}) {
    final c = Theme.of(context).colorScheme;
    final me = SessionScope.read(context).userId;
    switch (o.status) {
      case OrderStatus.pending when canDecide:
        return [
          Row(children: [
            Expanded(
              child: BusyButton(label: t.refuse, style: BusyStyle.outlined, onPressed: () => _refuse(o)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BusyButton(label: t.accept, icon: Icons.check, onPressed: () => _status(o, OrderStatus.accepted)),
            ),
          ]),
        ];
      case OrderStatus.accepted:
        return [
          if (o.runnerId == null && role == UserRole.runner)
            BusyButton(label: t.takeIt, icon: Icons.pan_tool_alt_outlined, onPressed: () => services.orders.assignRunner(o.id, me!)),
          if (o.runnerId == null && canAssignOthers)
            BusyButton(label: t.assignRunner, icon: Icons.person_add_alt, onPressed: () => _pickRunner(o)),
          if (o.runnerId != null && canDispatch)
            BusyButton(label: t.startTrip, icon: Icons.directions_car, onPressed: () => _status(o, OrderStatus.onWay)),
        ];
      case OrderStatus.onWay when canDispatch:
        return [
          BusyButton(
            label: t.sampleCollected,
            icon: Icons.bloodtype_outlined,
            color: Colors.purple,
            onPressed: () => _status(o, OrderStatus.sampleTaken),
          ),
        ];
      case OrderStatus.sampleTaken when canDecide:
        return [
          BusyButton(
            label: t.markCompleted,
            icon: Icons.task_alt,
            color: Colors.green.shade700,
            onPressed: () => _status(o, OrderStatus.completed),
          ),
          const SizedBox(height: 4),
          Text(t.uploadResult, style: TextStyle(color: c.outline), textAlign: TextAlign.center),
        ];
      default:
        return const [];
    }
  }
}
