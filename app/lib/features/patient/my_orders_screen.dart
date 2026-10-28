import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final uid = session.userId!;
    final labNames = {for (final l in services.labs.cachedLabs() ?? <Lab>[]) l.id: l.name(session.lang)};

    List<LabOrder> withQueued(List<LabOrder> online) => [...services.orders.queuedOrders(uid), ...online];

    return Scaffold(
      appBar: AppBar(title: Text(t.myOrders)),
      body: LoadView<List<LabOrder>>(
        cached: () {
          final c = services.orders.cachedMyOrders();
          return c == null ? null : withQueued(c);
        },
        load: () async {
          await services.orders.flushQueue();
          return withQueued(await services.orders.fetchMyOrders(uid));
        },
        isEmpty: (o) => o.isEmpty,
        empty: EmptyState(message: t.noOrders, icon: Icons.receipt_long_outlined),
        builder: (context, orders, _) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final o = orders[i];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                onTap: o.queued ? null : () => context.push('/order/${o.id}'),
                title: Text(o.packageName(session.lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (labNames[o.labId] != null) Text(labNames[o.labId]!),
                  Text(formatDateTime(o.createdAt, session.lang), style: Theme.of(context).textTheme.bodySmall),
                ]),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusChip(o.status, queued: o.queued),
                  const SizedBox(height: 4),
                  Text(t.priceIqd(formatIqd(o.priceIqd, session.lang)), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
