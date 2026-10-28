import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Live list of the lab's orders, split into New / In progress / Done.
class OrdersBoard extends StatefulWidget {
  const OrdersBoard({super.key, required this.labId});
  final String labId;

  @override
  State<OrdersBoard> createState() => _OrdersBoardState();
}

class _OrdersBoardState extends State<OrdersBoard> {
  late Stream<List<LabOrder>> _stream = services.orders.watchLabOrders(widget.labId);
  final Map<String, String> _names = {};

  Future<void> _loadNames(List<LabOrder> orders) async {
    final missing = orders.map((o) => o.patientId).where((id) => !_names.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final found = await services.orders.patientNames(missing);
      if (mounted) setState(() => _names.addAll(found));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    return DefaultTabController(
      length: 3,
      child: StreamBuilder<List<LabOrder>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return ErrorState(
              message: friendlyError(context, snap.error!),
              onRetry: () => setState(() => _stream = services.orders.watchLabOrders(widget.labId)),
            );
          }
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          _loadNames(all);

          final me = session.userId;
          final isRunner = session.role == UserRole.runner;
          final fresh = all.where((o) => o.status == OrderStatus.pending).toList();
          var active = all.where((o) => o.status.isActive).toList();
          // Runners see their own trips first.
          if (isRunner) {
            active.sort((a, b) => (b.runnerId == me ? 1 : 0) - (a.runnerId == me ? 1 : 0));
          }
          final done = all.where((o) => o.status.isClosed).toList();

          return Column(children: [
            TabBar(tabs: [
              Tab(text: '${t.tabNew} (${fresh.length})'),
              Tab(text: '${t.tabActive} (${active.length})'),
              Tab(text: t.tabDone),
            ]),
            Expanded(
              child: TabBarView(children: [
                _list(context, fresh, session.lang, me),
                _list(context, active, session.lang, me),
                _list(context, done, session.lang, me),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<LabOrder> orders, String lang, String? me) {
    final t = AppLocalizations.of(context);
    if (orders.isEmpty) return EmptyState(message: t.nothingHere);
    return ContentWidth(
      maxWidth: 900,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final o = orders[i];
          final mine = o.runnerId != null && o.runnerId == me;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: () => context.push('/staff/order/${o.id}'),
              leading: CircleAvatar(child: Icon(mine ? Icons.directions_car : Icons.person_outline)),
              title: Text(_names[o.patientId]?.isNotEmpty == true ? _names[o.patientId]! : '…'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.packageName(lang)),
                Text(formatDateTime(o.createdAt, lang), style: Theme.of(context).textTheme.bodySmall),
              ]),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                StatusChip(o.status),
                const SizedBox(height: 4),
                Text(t.priceIqd(formatIqd(o.priceIqd, lang)), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }
}
