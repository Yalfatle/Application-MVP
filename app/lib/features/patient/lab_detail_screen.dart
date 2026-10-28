import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

class LabDetailScreen extends StatelessWidget {
  const LabDetailScreen({super.key, required this.labId});
  final String labId;

  Lab? _cachedLab() {
    for (final l in services.labs.cachedLabs() ?? <Lab>[]) {
      if (l.id == labId) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    final lab = _cachedLab();
    return Scaffold(
      appBar: AppBar(title: Text(lab?.name(lang) ?? t.testsTitle)),
      body: LoadView<(Lab, List<LabPackage>)>(
        cached: () {
          final pk = services.labs.cachedPackages(labId);
          return (lab != null && pk != null) ? (lab, pk) : null;
        },
        load: () async {
          final results = await Future.wait([
            services.labs.fetchLab(labId),
            services.labs.fetchPackages(labId),
          ]);
          return (results[0] as Lab, results[1] as List<LabPackage>);
        },
        builder: (context, data, _) {
          final (lab, packages) = data;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (lab.description(lang) != null) ...[
              Text(lab.description(lang)!),
              const SizedBox(height: 8),
            ],
            if ((lang == 'ar' ? lab.addressAr ?? lab.addressEn : lab.addressEn ?? lab.addressAr) != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text((lang == 'ar' ? lab.addressAr ?? lab.addressEn : lab.addressEn ?? lab.addressAr)!),
              ),
            SectionTitle(t.testsTitle),
            if (packages.isEmpty) EmptyState(message: t.noPackages),
            for (final p in packages) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(p.name(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (p.description(lang) != null) Text(p.description(lang)!),
                    const SizedBox(height: 4),
                    Text(t.priceIqd(formatIqd(p.priceIqd, lang)),
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ]),
                  trailing: FilledButton(
                    onPressed: () => context.push('/book/${lab.id}/${p.id}'),
                    child: Text(t.book),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ]);
        },
      ),
    );
  }
}
