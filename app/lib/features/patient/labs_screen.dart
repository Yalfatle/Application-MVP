import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

class LabsScreen extends StatefulWidget {
  const LabsScreen({super.key});
  @override
  State<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends State<LabsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(t.labsTitle)),
      body: LoadView<List<Lab>>(
        cached: services.labs.cachedLabs,
        load: () => services.labs.fetchLabs(),
        isEmpty: (labs) => labs.isEmpty,
        empty: EmptyState(message: t.noLabs, icon: Icons.local_hospital_outlined),
        builder: (context, labs, _) {
          final q = _query.trim().toLowerCase();
          final shown = q.isEmpty
              ? labs
              : labs.where((l) =>
                  l.nameAr.toLowerCase().contains(q) ||
                  l.nameEn.toLowerCase().contains(q) ||
                  (l.area(lang) ?? '').toLowerCase().contains(q)).toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: shown.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchLabs),
                  onChanged: (v) => setState(() => _query = v),
                );
              }
              return _LabCard(lab: shown[i - 1], lang: lang);
            },
          );
        },
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.lab, required this.lang});
  final Lab lab;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/lab/${lab.id}'),
        child: Row(children: [
          SizedBox(
            width: 96,
            height: 96,
            child: lab.coverPhotoPath == null
                ? ColoredBox(color: c.primaryContainer, child: Icon(Icons.biotech, size: 40, color: c.onPrimaryContainer))
                : Image.network(
                    services.labs.photoUrl(lab.coverPhotoPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    errorBuilder: (_, _, _) => ColoredBox(color: c.primaryContainer),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lab.name(lang), style: Theme.of(context).textTheme.titleMedium),
                if (lab.area(lang) != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.place_outlined, size: 16, color: c.outline),
                    const SizedBox(width: 4),
                    Expanded(child: Text(lab.area(lang)!, style: TextStyle(color: c.outline))),
                  ]),
                ],
              ]),
            ),
          ),
          const Padding(padding: EdgeInsetsDirectional.only(end: 12), child: Icon(Icons.chevron_right)),
        ]),
      ),
    );
  }
}
