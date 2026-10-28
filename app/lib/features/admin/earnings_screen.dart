import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Completed orders, revenue and platform fee per lab. Lab owners see
/// their own lab; platform admins see every lab.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _lastMonth = false;

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final start = _lastMonth ? DateTime(now.year, now.month - 1) : DateTime(now.year, now.month);
    final end = _lastMonth ? DateTime(now.year, now.month) : DateTime(now.year, now.month + 1);
    return (start, end);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    final (from, to) = _range;
    return ContentWidth(
      maxWidth: 900,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(t.thisMonth)),
              ButtonSegment(value: true, label: Text(t.lastMonth)),
            ],
            selected: {_lastMonth},
            onSelectionChanged: (s) => setState(() => _lastMonth = s.first),
          ),
        ),
        Expanded(
          child: LoadView<List<EarningsRow>>(
            key: ValueKey(_lastMonth),
            load: () => services.staff.earnings(from, to),
            isEmpty: (r) => r.isEmpty,
            builder: (context, rows, _) {
              final total = rows.fold<int>(0, (s, r) => s + r.commissionIqd);
              final revenue = rows.fold<int>(0, (s, r) => s + r.revenueIqd);
              final count = rows.fold<int>(0, (s, r) => s + r.completedOrders);
              return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                Row(children: [
                  _Stat(label: t.completedOrders, value: formatIqd(count, lang)),
                  const SizedBox(width: 8),
                  _Stat(label: t.revenue, value: t.priceIqd(formatIqd(revenue, lang))),
                  const SizedBox(width: 8),
                  _Stat(label: t.platformFee, value: t.priceIqd(formatIqd(total, lang))),
                ]),
                const SizedBox(height: 16),
                if (rows.length > 1)
                  for (final r in rows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(lang == 'ar' ? r.labNameAr : r.labNameEn),
                        subtitle: Text('${t.completedOrders}: ${r.completedOrders} · ${t.revenue}: ${formatIqd(r.revenueIqd, lang)}'),
                        trailing: Text(t.priceIqd(formatIqd(r.commissionIqd, lang)),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
      );
}
